import AsyncHTTPClient
import Foundation
import NIOCore

struct GitLabAPIError: Error, CustomStringConvertible {
    let endpoint: String
    let status: UInt

    var description: String {
        "GitLab API call '\(endpoint)' failed with HTTP \(status)"
    }
}

struct HTTPGitLabAPIClient: PendingStateStore, PipelineTrigger {

    private static let requestTimeout = TimeAmount.seconds(30)
    private static let maxResponseBytes = 4 << 20
    private static let maxListPages = 10

    private let httpClient: HTTPClient
    private let baseURL: String
    private let projectPath: String
    private let packageName: String
    private let apiToken: String
    private let triggerToken: String

    init(httpClient: HTTPClient, configuration: GitLabSinkConfiguration) {
        self.httpClient = httpClient
        self.baseURL = configuration.baseURL.hasSuffix("/")
            ? String(configuration.baseURL.dropLast())
            : configuration.baseURL
        // Numeric id or an already-percent-encoded path (GitLab API convention) —
        // never re-encode, or `group%2Fproject` becomes `group%252Fproject`.
        self.projectPath = configuration.projectId
        self.packageName = configuration.pendingPackageName
        self.apiToken = configuration.apiToken
        self.triggerToken = configuration.triggerToken
    }

    func getPendingState(uploadId version: String) async throws -> String? {
        var request = HTTPClientRequest(url: pendingFileURL(version: version))
        request.method = .GET
        request.headers.add(name: "PRIVATE-TOKEN", value: apiToken)

        let response = try await httpClient.execute(request, timeout: Self.requestTimeout)
        if response.status.code == 404 {
            return nil
        }
        guard (200..<300).contains(response.status.code) else {
            throw GitLabAPIError(endpoint: "get pending state", status: response.status.code)
        }

        let body = try await response.body.collect(upTo: Self.maxResponseBytes)
        return String(buffer: body)
    }

    func claimPendingState(uploadId version: String) async throws -> Bool {
        guard let packageId = try await findPackageId(version: version) else {
            return false
        }

        var request = HTTPClientRequest(url: "\(baseURL)/projects/\(projectPath)/packages/\(packageId)")
        request.method = .DELETE
        request.headers.add(name: "PRIVATE-TOKEN", value: apiToken)

        let response = try await httpClient.execute(request, timeout: Self.requestTimeout)
        if response.status.code == 404 {
            return false
        }
        guard (200..<300).contains(response.status.code) else {
            throw GitLabAPIError(endpoint: "delete pending package", status: response.status.code)
        }
        return true
    }

    // Re-publishing after a claim DELETE is safe even with duplicate-package
    // rejection enabled: GitLab's generic duplicate check excludes entries in
    // pending_destruction (not_pending_destruction scope in
    // packages/generic/create_package_file_service.rb).
    func restorePendingState(uploadId version: String, content: String) async throws {
        var request = HTTPClientRequest(url: pendingFileURL(version: version))
        request.method = .PUT
        request.headers.add(name: "PRIVATE-TOKEN", value: apiToken)
        request.body = .bytes(ByteBuffer(string: content))

        let response = try await httpClient.execute(request, timeout: Self.requestTimeout)
        guard (200..<300).contains(response.status.code) else {
            throw GitLabAPIError(endpoint: "restore pending state", status: response.status.code)
        }
    }

    func triggerPipeline(ref: String, variables: [String: String]) async throws {
        var fields: [(String, String)] = [
            ("token", triggerToken),
            ("ref", ref)
        ]
        for (key, value) in variables.sorted(by: { $0.key < $1.key }) {
            fields.append(("variables[\(key)]", value))
        }

        var request = HTTPClientRequest(url: "\(baseURL)/projects/\(projectPath)/trigger/pipeline")
        request.method = .POST
        request.headers.add(name: "content-type", value: "application/x-www-form-urlencoded")
        request.body = .bytes(ByteBuffer(string: fields.formURLEncoded))

        let response = try await httpClient.execute(request, timeout: Self.requestTimeout)
        guard (200..<300).contains(response.status.code) else {
            throw GitLabAPIError(endpoint: "trigger pipeline", status: response.status.code)
        }
    }

    // MARK: - Helpers

    private func pendingFileURL(version: String) -> String {
        "\(baseURL)/projects/\(projectPath)/packages/generic/\(packageName.formURLEncoded)/\(version.formURLEncoded)/state.json"
    }

    private func findPackageId(version: String) async throws -> Int? {
        for page in 1...Self.maxListPages {
            let url = "\(baseURL)/projects/\(projectPath)/packages"
                + "?package_type=generic&package_name=\(packageName.formURLEncoded)&per_page=100&page=\(page)"
            var request = HTTPClientRequest(url: url)
            request.method = .GET
            request.headers.add(name: "PRIVATE-TOKEN", value: apiToken)

            let response = try await httpClient.execute(request, timeout: Self.requestTimeout)
            guard (200..<300).contains(response.status.code) else {
                throw GitLabAPIError(endpoint: "list pending packages", status: response.status.code)
            }

            let body = try await response.body.collect(upTo: Self.maxResponseBytes)
            let packages = try JSONDecoder().decode([PackageListItem].self, from: Data(body.readableBytesView))
            if let match = packages.first(where: { $0.version == version }) {
                return match.id
            }
            if packages.isEmpty {
                return nil
            }
        }
        return nil
    }

    private struct PackageListItem: Decodable {
        let id: Int
        let version: String
    }
}

// MARK: - Form URL encoding

extension String {

    private static let formURLAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    var formURLEncoded: String {
        addingPercentEncoding(withAllowedCharacters: Self.formURLAllowed) ?? self
    }
}

extension [(String, String)] {
    var formURLEncoded: String {
        map { "\($0.formURLEncoded)=\($1.formURLEncoded)" }.joined(separator: "&")
    }
}
