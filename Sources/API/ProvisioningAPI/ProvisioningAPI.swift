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

    public func getBundleId(identifier: String) async throws -> String? {
        let query = Operations.BundleIdsGetCollection.Input.Query(
            filter_lbrack_identifier_rbrack_: [identifier]
        )
        let input = Operations.BundleIdsGetCollection.Input(query: query)
        let response = try await client.bundleIdsGetCollection(input)

        switch response {
        case .ok(let ok):
            // Filter for EXACT match (API returns substring/prefix matches)
            let exactMatch = try ok.body.json.data.first { $0.attributes?.identifier == identifier }
            return exactMatch?.id
        case .forbidden(let forbidden):
             let message = (try? forbidden.body.json.errorDescription) ?? "Forbidden"
             throw Error.badResponse(message)
        default:
            throw Error.badResponse("Failed to list bundle IDs")
        }
    }

    /// Bypasses the generated client: newly registered devices come back with statuses
    /// the published spec doesn't declare, which the generated closed enums refuse to decode.
    public func registerDevice(name: String, udid: String, platform: Platform) async throws -> Device {
        let body = Components.Schemas.DeviceCreateRequest(data: .init(
            _type: .devices,
            attributes: .init(name: name, platform: platform.asApiPlatform, udid: udid)
        ))
        var request = URLRequest(url: serverURL.appendingPathComponent("v1/devices"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(try jwtProvider.token())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await performRequest(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw Error.badResponse("Non-HTTP response while registering device")
        }

        switch httpResponse.statusCode {
        case 201:
            let created = try jsonDecoder.decode(RegisteredDeviceResponse.self, from: data)
            return created.data.device(platform: platform, fallbackName: name, fallbackUDID: udid)
        case 409:
            let message = errorMessage(from: data) ?? "Device already exists"
            logger.warning("\(message). This might not be a blocker.")
            throw Error.conflict(message)
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
        var queryItems = [URLQueryItem(name: "limit", value: String(Self.devicesPageLimit))]
        if let platform {
            queryItems.append(URLQueryItem(name: "filter[platform]", value: platform.asDeviceFilterValue))
        }
        if let status {
            queryItems.append(URLQueryItem(name: "filter[status]", value: status.apiValue))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw Error.badRequest("Could not build devices URL")
        }

        var allDevices: [Device] = []
        var nextURL: String? = url.absoluteString
        while let url = nextURL {
            let (devices, nextLink) = try await fetchDevicesPage(url: url)
            allDevices.append(contentsOf: devices)
            nextURL = nextLink
        }
        return allDevices
    }

    private static let devicesPageLimit = 200

    private func fetchDevicesPage(url: String) async throws -> ([Device], String?) {
        let (data, response) = try await fetchPage(url: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw Error.badResponse("Non-HTTP response while listing devices")
        }
        switch httpResponse.statusCode {
        case 200:
            let page = try jsonDecoder.decode(DevicesPageResponse.self, from: data)
            let devices = page.data.map { $0.device(platform: $0.apiPlatform) }
            return (devices, page.links.next)
        case 403:
            throw Error.badResponse(errorMessage(from: data) ?? "Forbidden")
        default:
            throw Error.badResponse(errorMessage(from: data) ?? "Failed to list devices (HTTP \(httpResponse.statusCode))")
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
                serialNumber: cert.attributes?.serialNumber
            )
        }
    }

    private func fetchCertificatesPage(url: String) async throws -> ([Certificate], String?) {
        let (data, response) = try await fetchPage(url: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw Error.badResponse("Failed to fetch certificates page")
        }
        let certificatesResponse = try jsonDecoder.decode(Components.Schemas.CertificatesResponse.self, from: data)
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
                serialNumber: cert.attributes?.serialNumber
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

    public func createProfile(name: String, type: ProfileType, bundleId: String, certificateIds: [String], deviceIds: [String]? = nil) async throws -> Profile {
        let bundleIdRelationship = Components.Schemas.ProfileCreateRequest.DataPayload.RelationshipsPayload.BundleIdPayload(
            data: .init(_type: .bundleIds, id: bundleId)
        )
        
        let devicesRelationship: Components.Schemas.ProfileCreateRequest.DataPayload.RelationshipsPayload.DevicesPayload?
        if let deviceIds = deviceIds {
            devicesRelationship = Components.Schemas.ProfileCreateRequest.DataPayload.RelationshipsPayload.DevicesPayload(
                data: deviceIds.map { .init(_type: .devices, id: $0) }
            )
        } else {
            devicesRelationship = nil
        }
        
        let certificatesRelationship = Components.Schemas.ProfileCreateRequest.DataPayload.RelationshipsPayload.CertificatesPayload(
            data: certificateIds.map { .init(_type: .certificates, id: $0) }
        )
        
        let relationships = Components.Schemas.ProfileCreateRequest.DataPayload.RelationshipsPayload(
            bundleId: bundleIdRelationship,
            devices: devicesRelationship,
            certificates: certificatesRelationship
        )
        
        let attributes = Components.Schemas.ProfileCreateRequest.DataPayload.AttributesPayload(
            name: name,
            profileType: type.asApiType
        )
        
        let data = Components.Schemas.ProfileCreateRequest.DataPayload(
            _type: .profiles,
            attributes: attributes,
            relationships: relationships
        )
        
        let body = Components.Schemas.ProfileCreateRequest(data: data)
        let input = Operations.ProfilesCreateInstance.Input(body: .json(body))
        
        let response = try await client.profilesCreateInstance(input)
        
        switch response {
        case .created(let created):
            let profile = try created.body.json.data
            return Profile(
                id: profile.id,
                name: profile.attributes?.name ?? "",
                type: profile.attributes?.profileType.map { ProfileType(rawValue: $0.rawValue) } ?? nil,
                content: profile.attributes?.profileContent.flatMap { Data(base64Encoded: $0) },
                expirationDate: profile.attributes?.expirationDate
            )
        case .badRequest(let error):
             let message = (try? error.body.json.errorDescription) ?? "Bad request"
             throw Error.badRequest(message)
        case .conflict(let conflict):
            let message = (try? conflict.body.json.errorDescription) ?? "Profile already exists"
            throw Error.conflict(message)
        case .forbidden(let forbidden):
             let message = (try? forbidden.body.json.errorDescription) ?? "Forbidden"
             throw Error.badResponse(message)
        default:
            throw Error.badResponse("Failed to create profile")
        }
    }

    public func listProfiles(name: String? = nil) async throws -> [Profile] {
        var allProfiles: [Profile] = []
        var nextURL: String? = nil

        let query = Operations.ProfilesGetCollection.Input.Query(
            filter_lbrack_name_rbrack_: name.map { [$0] }
        )
        let input = Operations.ProfilesGetCollection.Input(query: query)
        let response = try await client.profilesGetCollection(input)

        switch response {
        case .ok(let ok):
            let json = try ok.body.json
            allProfiles.append(contentsOf: parseProfiles(from: json.data))
            nextURL = json.links.next
        case .forbidden(let forbidden):
            let message = (try? forbidden.body.json.errorDescription) ?? "Forbidden"
            throw Error.badResponse(message)
        default:
            throw Error.badResponse("Failed to list profiles")
        }

        while let url = nextURL {
            let (data, nextLink) = try await fetchProfilesPage(url: url)
            allProfiles.append(contentsOf: data)
            nextURL = nextLink
        }

        // Filter for EXACT name match (API returns substring/prefix matches)
        if let name {
            return allProfiles.filter { $0.name == name }
        }
        return allProfiles
    }

    private func parseProfiles(from data: [Components.Schemas.Profile]) -> [Profile] {
        data.map { profile in
            Profile(
                id: profile.id,
                name: profile.attributes?.name ?? "",
                type: profile.attributes?.profileType.map { ProfileType(rawValue: $0.rawValue) } ?? nil,
                content: profile.attributes?.profileContent.flatMap { Data(base64Encoded: $0) },
                expirationDate: profile.attributes?.expirationDate
            )
        }
    }

    private func fetchProfilesPage(url: String) async throws -> ([Profile], String?) {
        let (data, response) = try await fetchPage(url: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw Error.badResponse("Failed to fetch profiles page")
        }
        let profilesResponse = try jsonDecoder.decode(Components.Schemas.ProfilesResponse.self, from: data)
        return (parseProfiles(from: profilesResponse.data), profilesResponse.links.next)
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
            throw Error.badResponse("Profile not found")
        default:
            throw Error.badResponse("Failed to delete profile")
        }
    }

    public enum Error: Swift.Error, LocalizedError {
        case badRequest(String)
        case badResponse(String)
        case conflict(String)
        case undocumented(String)
        
        public var errorDescription: String? {
            switch self {
            case .badRequest(let message): return "Bad request: \(message)"
            case .badResponse(let message): return "Bad response: \(message)"
            case .conflict(let message): return "Conflict: \(message)"
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

extension ProvisioningAPI: DeviceService {}
extension ProvisioningAPI: ProfileService {}
extension ProvisioningAPI: CertificateService {}
