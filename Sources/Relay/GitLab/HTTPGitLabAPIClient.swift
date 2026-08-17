import AsyncHTTPClient
import Foundation
import NIOCore

struct GitLabAPIError: Error, CustomStringConvertible {
    let endpoint: String
    let status: UInt

    var description: String {
        "GitLab API call '\(endpoint)' failed with status \(status)"
    }
}

struct HTTPGitLabAPIClient: GitLabAPIClient {

    private static let requestTimeout = TimeAmount.seconds(30)
    private static let maxResponseBytes = 1 << 20

    private let httpClient: HTTPClient
    private let baseURL: String
    private let projectPath: String
    private let apiToken: String
    private let triggerToken: String

    init(httpClient: HTTPClient, configuration: GitLabSinkConfiguration) {
        self.httpClient = httpClient
        self.baseURL = configuration.baseURL.hasSuffix("/")
            ? String(configuration.baseURL.dropLast())
            : configuration.baseURL
        self.projectPath = configuration.projectId.formURLEncoded
        self.apiToken = configuration.apiToken
        self.triggerToken = configuration.triggerToken
    }

    func getVariable(key: String) async throws -> GitLabVariable? {
        var request = HTTPClientRequest(url: "\(baseURL)/projects/\(projectPath)/variables/\(key.formURLEncoded)")
        request.method = .GET
        request.headers.add(name: "PRIVATE-TOKEN", value: apiToken)

        let response = try await httpClient.execute(request, timeout: Self.requestTimeout)
        if response.status.code == 404 {
            return nil
        }
        guard (200..<300).contains(response.status.code) else {
            throw GitLabAPIError(endpoint: "get variable", status: response.status.code)
        }

        let body = try await response.body.collect(upTo: Self.maxResponseBytes)
        let decoded = try JSONDecoder().decode(VariableResponse.self, from: Data(body.readableBytesView))
        return GitLabVariable(key: decoded.key, value: decoded.value)
    }

    func deleteVariable(key: String) async throws -> Bool {
        var request = HTTPClientRequest(url: "\(baseURL)/projects/\(projectPath)/variables/\(key.formURLEncoded)")
        request.method = .DELETE
        request.headers.add(name: "PRIVATE-TOKEN", value: apiToken)

        let response = try await httpClient.execute(request, timeout: Self.requestTimeout)
        if response.status.code == 404 {
            return false
        }
        guard (200..<300).contains(response.status.code) else {
            throw GitLabAPIError(endpoint: "delete variable", status: response.status.code)
        }
        return true
    }

    func createVariable(key: String, value: String) async throws {
        var request = HTTPClientRequest(url: "\(baseURL)/projects/\(projectPath)/variables")
        request.method = .POST
        request.headers.add(name: "PRIVATE-TOKEN", value: apiToken)
        request.headers.add(name: "content-type", value: "application/x-www-form-urlencoded")
        request.body = .bytes(ByteBuffer(string: [
            ("key", key),
            ("value", value),
            ("masked", "false"),
            ("protected", "false")
        ].formURLEncoded))

        let response = try await httpClient.execute(request, timeout: Self.requestTimeout)
        guard (200..<300).contains(response.status.code) else {
            throw GitLabAPIError(endpoint: "create variable", status: response.status.code)
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

    private struct VariableResponse: Decodable {
        let key: String
        let value: String
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
