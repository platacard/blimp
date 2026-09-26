import OpenAPIRuntime
import OpenAPIURLSession
import JWTProvider
import Cronista
import Auth
import Foundation

public struct ProvisioningAPI: Sendable {

    typealias RequestPerformer = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let jwtProvider: any JWTProviding
    private let client: any APIProtocol
    private let serverURL: URL
    private let performRequest: RequestPerformer

    nonisolated(unsafe) private let logger: Cronista

    // Server URL is constant, fallback is defensive only
    private static var defaultServerURL: URL {
        (try? Servers.Server1.url()) ?? URL(string: "https://api.appstoreconnect.apple.com")!
    }

    static let sharedSessionPerformer: RequestPerformer = { try await URLSession.shared.data(for: $0) }

    public init(jwtProvider: any JWTProviding) {
        let serverURL = Self.defaultServerURL
        self.jwtProvider = jwtProvider
        self.logger = Cronista(module: "blimp", category: "ProvisioningAPI")
        self.serverURL = serverURL
        self.performRequest = Self.sharedSessionPerformer

        self.client = Client(
            serverURL: serverURL,
            configuration: .init(dateTranscoder: .iso8601WithFractionalSeconds),
            transport: URLSessionTransport(),
            middlewares: [
                AuthMiddleware { try jwtProvider.token() }
            ]
        )
    }

    internal init(
        client: any APIProtocol,
        jwtProvider: any JWTProviding,
        performRequest: @escaping RequestPerformer = ProvisioningAPI.sharedSessionPerformer
    ) {
        self.client = client
        self.jwtProvider = jwtProvider
        self.serverURL = Self.defaultServerURL
        self.performRequest = performRequest
        self.logger = Cronista(module: "blimp", category: "ProvisioningAPI")
    }

    // MARK: - Pagination Helpers

    private static let pageLimit = 200

    private var jsonDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) {
                return date
            }
            // Fallback without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format: \(dateString)")
        }
        return decoder
    }

    private func fetchPage(url: String) async throws -> (Data, URLResponse) {
        guard let requestURL = URL(string: url) else {
            throw Error.badResponse("Invalid pagination URL")
        }
        return try await fetchPage(url: requestURL)
    }

    private func fetchPage(url requestURL: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: requestURL)
        request.setValue("Bearer \(try jwtProvider.token())", forHTTPHeaderField: "Authorization")
        return try await performRequest(request)
    }

    private func errorMessage(from data: Data) -> String? {
        (try? jsonDecoder.decode(Components.Schemas.ErrorResponse.self, from: data))?.errorDescription
    }

    // MARK: - Bundle IDs

    /// Raw request for the same reason as `listDevices`: the identifier filter also returns longer
    /// identifiers, whose platform may be one the generated collection decoder rejects.
    public func getBundleId(identifier: String) async throws -> String? {
        var components = URLComponents(url: serverURL.appendingPathComponent("v1/bundleIds"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "filter[identifier]", value: identifier),
            URLQueryItem(name: "limit", value: String(Self.pageLimit))
        ]
        guard let url = components?.url else {
            throw Error.badRequest("Could not build bundle IDs URL")
        }

        var nextURL: String? = url.absoluteString
        while let url = nextURL {
            let page = try await fetchCollectionPage(BundleIdsPageResponse.self, url: url, listing: "bundle IDs")
            // The filter also matches longer identifiers: only the exact one counts
            if let exactMatch = page.data.first(where: { $0.attributes?.identifier == identifier }) {
                return exactMatch.id
            }
            nextURL = page.links.next
        }
        return nil
    }

    /// Bypasses the generated client: newly registered devices come back with statuses
    /// the published spec doesn't declare, which the generated closed enums refuse to decode.
    /// A UDID already on the team is not an error: the existing device is returned.
    public func registerDevice(name: String, udid: String, platform: Platform) async throws -> DeviceRegistration {
        let body = Components.Schemas.DeviceCreateRequest(data: .init(
            _type: .devices,
            attributes: .init(name: name, platform: platform.asApiPlatform, udid: udid)
        ))
        let (data, response) = try await performRequest(try postRequest(path: "v1/devices", body: body))
        guard let httpResponse = response as? HTTPURLResponse else {
            throw Error.badResponse("Non-HTTP response while registering device")
        }

        switch httpResponse.statusCode {
        case 201:
            let created = try decode(RegisteredDeviceResponse.self, from: data, reading: "the registered device")
            return .registered(created.data.device(platform: platform, fallbackName: name, fallbackUDID: udid))
        case 409:
            guard let existing = try await device(udid: udid, platform: platform) else {
                throw Error.conflict(errorMessage(from: data) ?? "Device already exists")
            }
            return .alreadyRegistered(existing)
        case 403:
            throw Error.badResponse(errorMessage(from: data) ?? "Forbidden")
        case 400, 422:
            throw Error.badRequest(errorMessage(from: data) ?? "Bad request")
        default:
            throw Error.undocumented("Unexpected HTTP \(httpResponse.statusCode) while registering device")
        }
    }
    
    /// Raw request for the same reason as `registerDevice`: the generated collection
    /// decoder rejects devices whose status Apple hasn't documented.
    public func listDevices(platform: Platform? = nil, status: Device.Status? = .enabled) async throws -> [Device] {
        var components = URLComponents(url: serverURL.appendingPathComponent("v1/devices"), resolvingAgainstBaseURL: false)
        var queryItems = [URLQueryItem(name: "limit", value: String(Self.pageLimit))]
        if let platform {
            queryItems.append(URLQueryItem(name: "filter[platform]", value: platform.asDeviceFilterValue))
        }
        if let status {
            queryItems.append(URLQueryItem(name: "filter[status]", value: try Self.deviceStatusFilterValue(status)))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw Error.badRequest("Could not build devices URL")
        }

        var allDevices: [Device] = []
        var nextURL: String? = url.absoluteString
        while let url = nextURL {
            let page = try await fetchCollectionPage(DevicesPageResponse.self, url: url, listing: "devices")
            allDevices.append(contentsOf: page.data.map { $0.device(platform: $0.apiPlatform) })
            nextURL = page.links.next
        }
        return allDevices
    }

    /// Any status: a duplicate may still be processing or be disabled. The
    /// listing reports platforms coarsely, so the requested one is kept, as
    /// the create path does.
    private func device(udid: String, platform: Platform) async throws -> Device? {
        try await listDevices(platform: nil, status: nil)
            .first { $0.udid.caseInsensitiveCompare(udid) == .orderedSame }
            .map { Device(id: $0.id, name: $0.name, udid: $0.udid, platform: platform, status: $0.status) }
    }

    /// Apple documents only these two values for `filter[status]`.
    private static func deviceStatusFilterValue(_ status: Device.Status) throws -> String {
        switch status {
        case .enabled: "ENABLED"
        case .disabled: "DISABLED"
        case .processing, .unknown:
            throw Error.badRequest("Devices can only be filtered by enabled or disabled status")
        }
    }

    public func listCertificates(filterType: CertificateType? = nil) async throws -> [Certificate] {
        var allCertificates: [Certificate] = []
        var nextURL: String? = nil

        let query = Operations.CertificatesGetCollection.Input.Query(
            filter_lbrack_certificateType_rbrack_: filterType.map { [$0.asFilterType] }
        )
        let input = Operations.CertificatesGetCollection.Input(query: query)
        let response = try await client.certificatesGetCollection(input)

        switch response {
        case .ok(let ok):
            let json = try ok.body.json
            allCertificates.append(contentsOf: parseCertificates(from: json.data))
            nextURL = json.links.next
        case .forbidden(let forbidden):
            let message = (try? forbidden.body.json.errorDescription) ?? "Forbidden"
            throw Error.badResponse(message)
        default:
            throw Error.badResponse("Failed to list certificates")
        }

        while let url = nextURL {
            let (data, nextLink) = try await fetchCertificatesPage(url: url)
            allCertificates.append(contentsOf: data)
            nextURL = nextLink
        }

        return allCertificates
    }

    private func parseCertificates(from data: [Components.Schemas.Certificate]) -> [Certificate] {
        data.map { cert in
            Certificate(
                id: cert.id,
                name: cert.attributes?.name ?? "",
                type: cert.attributes?.certificateType.map { CertificateType(rawValue: $0.rawValue) } ?? nil,
                content: cert.attributes?.certificateContent.flatMap { Data(base64Encoded: $0) },
                serialNumber: cert.attributes?.serialNumber,
                expirationDate: cert.attributes?.expirationDate
            )
        }
    }

    private func fetchCertificatesPage(url: String) async throws -> ([Certificate], String?) {
        let (data, response) = try await fetchPage(url: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw Error.badResponse("Failed to fetch certificates page")
        }
        let certificatesResponse = try decode(Components.Schemas.CertificatesResponse.self, from: data, reading: "certificates")
        return (parseCertificates(from: certificatesResponse.data), certificatesResponse.links.next)
    }
    
    public func createCertificate(csrContent: String, type: CertificateType) async throws -> Certificate {
        let attributes = Components.Schemas.CertificateCreateRequest.DataPayload.AttributesPayload(
            csrContent: csrContent,
            certificateType: type.asApiType
        )
        let data = Components.Schemas.CertificateCreateRequest.DataPayload(
            _type: .certificates,
            attributes: attributes
        )
        let body = Components.Schemas.CertificateCreateRequest(data: data)
        let input = Operations.CertificatesCreateInstance.Input(body: .json(body))
        
        let response = try await client.certificatesCreateInstance(input)
        
        switch response {
        case .created(let created):
            let cert = try created.body.json.data
            return Certificate(
                id: cert.id,
                name: cert.attributes?.name ?? "",
                type: cert.attributes?.certificateType.map { CertificateType(rawValue: $0.rawValue) } ?? nil,
                content: cert.attributes?.certificateContent.flatMap { Data(base64Encoded: $0) },
                serialNumber: cert.attributes?.serialNumber,
                expirationDate: cert.attributes?.expirationDate
            )
        case .badRequest(let error):
             let message = (try? error.body.json.errorDescription) ?? "Bad request"
             throw Error.badRequest(message)
        case .forbidden(let forbidden):
             let message = (try? forbidden.body.json.errorDescription) ?? "Forbidden"
             throw Error.badResponse(message)
        default:
             throw Error.badResponse("Failed to create certificate")
        }
    }

    public func deleteCertificate(id: String) async throws {
        let input = Operations.CertificatesDeleteInstance.Input(path: .init(id: id))
        let response = try await client.certificatesDeleteInstance(input)

        switch response {
        case .noContent:
            return
        case .forbidden(let forbidden):
            let message = (try? forbidden.body.json.errorDescription) ?? "Forbidden"
            throw Error.badResponse(message)
        case .notFound:
            throw Error.badResponse("Certificate not found")
        default:
            throw Error.badResponse("Failed to delete certificate")
        }
    }

    /// Raw request for the same reason as `registerDevice`: a profile type, state or platform
    /// the generated decoder rejects would fail the call after the portal created the profile.
    public func createProfile(name: String, type: ProfileType, bundleId: String, certificateIds: [String], deviceIds: [String]? = nil) async throws -> Profile {
        let body = Components.Schemas.ProfileCreateRequest(data: .init(
            _type: .profiles,
            attributes: .init(name: name, profileType: type.asApiType),
            relationships: .init(
                bundleId: .init(data: .init(_type: .bundleIds, id: bundleId)),
                devices: deviceIds.map { .init(data: $0.map { .init(_type: .devices, id: $0) }) },
                certificates: .init(data: certificateIds.map { .init(_type: .certificates, id: $0) })
            )
        ))

        let (data, response) = try await performRequest(try postRequest(path: "v1/profiles", body: body))
        guard let httpResponse = response as? HTTPURLResponse else {
            throw Error.badResponse("Non-HTTP response while creating profile")
        }

        switch httpResponse.statusCode {
        case 201:
            return try decode(CreatedProfileResponse.self, from: data, reading: "the created profile").data.profile
        case 409:
            throw Error.conflict(errorMessage(from: data) ?? "Profile already exists")
        case 400, 422:
            throw Error.badRequest(errorMessage(from: data) ?? "Bad request")
        default:
            throw Error.badResponse(errorMessage(from: data) ?? "Failed to create profile (HTTP \(httpResponse.statusCode))")
        }
    }

    /// Raw request for the same reason as `listDevices`: the name filter also returns other
    /// profiles, and one the generated decoder rejects would fail the whole listing.
    public func listProfiles(name: String? = nil) async throws -> [Profile] {
        var components = URLComponents(url: serverURL.appendingPathComponent("v1/profiles"), resolvingAgainstBaseURL: false)
        var queryItems = [URLQueryItem(name: "limit", value: String(Self.pageLimit))]
        if let name {
            queryItems.append(URLQueryItem(name: "filter[name]", value: name))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw Error.badRequest("Could not build profiles URL")
        }

        var allProfiles: [Profile] = []
        var nextURL: String? = url.absoluteString
        while let url = nextURL {
            let page = try await fetchCollectionPage(ProfilesPageResponse.self, url: url, listing: "profiles")
            allProfiles.append(contentsOf: page.data.map(\.profile))
            nextURL = page.links.next
        }

        // The name filter also matches longer names: only the exact one counts
        guard let name else { return allProfiles }
        return allProfiles.filter { $0.name == name }
    }

    public func deleteProfile(id: String) async throws {
        let input = Operations.ProfilesDeleteInstance.Input(path: .init(id: id))
        let response = try await client.profilesDeleteInstance(input)
        
        switch response {
        case .noContent:
            return
        case .forbidden(let forbidden):
             let message = (try? forbidden.body.json.errorDescription) ?? "Forbidden"
             throw Error.badResponse(message)
        case .notFound:
            throw Error.notFound("Profile \(id)")
        default:
            throw Error.badResponse("Failed to delete profile")
        }
    }

    public enum Error: Swift.Error, LocalizedError {
        case badRequest(String)
        case badResponse(String)
        case conflict(String)
        case notFound(String)
        case undocumented(String)
        
        public var errorDescription: String? {
            switch self {
            case .badRequest(let message): return "Bad request: \(message)"
            case .badResponse(let message): return "Bad response: \(message)"
            case .conflict(let message): return "Conflict: \(message)"
            case .notFound(let message): return "Not found: \(message)"
            case .undocumented(let message): return "Undocumented: \(message)"
            }
        }
    }
}

extension Components.Schemas.ErrorResponse {
    var errorDescription: String? {
        return errors?.compactMap { $0.detail }.joined(separator: ", ")
    }
}

private extension ProvisioningAPI {
    func postRequest(path: String, body: some Encodable) throws -> URLRequest {
        var request = URLRequest(url: serverURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("Bearer \(try jwtProvider.token())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    func fetchCollectionPage<Page: Decodable>(_ type: Page.Type, url: String, listing subject: String) async throws -> Page {
        let (data, response) = try await fetchPage(url: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw Error.badResponse("Non-HTTP response while listing \(subject)")
        }
        guard httpResponse.statusCode == 200 else {
            throw Error.badResponse(errorMessage(from: data) ?? "Failed to list \(subject) (HTTP \(httpResponse.statusCode))")
        }
        return try decode(type, from: data, reading: subject)
    }

    /// A bare `DecodingError` prints as "The data couldn't be read…"; this names the reply and the field.
    func decode<T: Decodable>(_ type: T.Type, from data: Data, reading subject: String) throws -> T {
        do {
            return try jsonDecoder.decode(type, from: data)
        } catch let error as DecodingError {
            throw Error.badResponse("Could not decode \(subject)\(Self.location(of: error))")
        }
    }

    static func location(of error: DecodingError) -> String {
        let (codingPath, detail): ([any CodingKey], String) = switch error {
        case .keyNotFound(let key, let context): (context.codingPath + [key], context.debugDescription)
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context): (context.codingPath, context.debugDescription)
        @unknown default: ([], String(describing: error))
        }
        let path = codingPath.reduce("") { path, key in
            key.intValue.map { "\(path)[\($0)]" } ?? (path.isEmpty ? key.stringValue : "\(path).\(key.stringValue)")
        }
        return path.isEmpty ? ": \(detail)" : " at \(path): \(detail)"
    }
}

extension ProvisioningAPI: DeviceService {}
extension ProvisioningAPI: ProfileService {}
extension ProvisioningAPI: CertificateService {}
