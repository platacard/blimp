import OpenAPIRuntime
import OpenAPIURLSession
import JWTProvider
import Cronista
import Auth
import Foundation

public struct ProvisioningAPI: Sendable {

    private let jwtProvider: any JWTProviding
    private let client: any APIProtocol

    nonisolated(unsafe) private let logger: Cronista

    public init(jwtProvider: any JWTProviding) {
        self.jwtProvider = jwtProvider
        self.logger = Cronista(module: "blimp", category: "ProvisioningAPI")

        // Server URL is constant, fallback is defensive only
        let serverURL = (try? Servers.Server1.url()) ?? URL(string: "https://api.appstoreconnect.apple.com")!

        self.client = Client(
            serverURL: serverURL,
            configuration: .init(dateTranscoder: .iso8601WithFractionalSeconds),
            transport: URLSessionTransport(),
            middlewares: [
                AuthMiddleware { try jwtProvider.token() }
            ]
        )
    }

    internal init(client: any APIProtocol, jwtProvider: any JWTProviding) {
        self.client = client
        self.jwtProvider = jwtProvider
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
        var request = URLRequest(url: requestURL)
        request.setValue("Bearer \(try jwtProvider.token())", forHTTPHeaderField: "Authorization")
        return try await URLSession.shared.data(for: request)
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

    public func registerDevice(name: String, udid: String, platform: Platform) async throws -> Device {
        let attributes = Components.Schemas.DeviceCreateRequest.DataPayload.AttributesPayload(
            name: name,
            platform: platform.asApiPlatform,
            udid: udid
        )
        let data = Components.Schemas.DeviceCreateRequest.DataPayload(
            _type: .devices,
            attributes: attributes
        )
        let body = Components.Schemas.DeviceCreateRequest(data: data)
        let input = Operations.DevicesCreateInstance.Input(body: .json(body))
        
        let response = try await client.devicesCreateInstance(input)
        
        switch response {
        case .created(let created):
            let data = try created.body.json.data
            return Device(
                id: data.id,
                name: data.attributes?.name ?? name,
                udid: data.attributes?.udid ?? udid,
                platform: platform,
                status: data.attributes?.status == .enabled ? .enabled : .disabled
            )
        case .conflict(let conflict):
            let message = (try? conflict.body.json.errorDescription) ?? "Device already exists"
            logger.warning("\(message). This might not be a blocker.")
            throw Error.conflict(message)
        case .forbidden(let forbidden):
             let message = (try? forbidden.body.json.errorDescription) ?? "Forbidden"
             throw Error.badResponse(message)
        case .badRequest(let error):
             let message = (try? error.body.json.errorDescription) ?? "Bad request"
             throw Error.badRequest(message)
        default:
            throw Error.undocumented("Unexpected response: \(response)")
        }
    }
    
    public func listDevices(platform: Platform? = nil, status: Device.Status? = .enabled) async throws -> [Device] {
        var allDevices: [Device] = []
        var nextURL: String? = nil

        // First request via typed client
        // Filter by ENABLED status by default to avoid decoding issues with PROCESSING devices
        let statusFilter: [Operations.DevicesGetCollection.Input.Query.FilterLbrackStatusRbrackPayloadPayload]? = status.map {
            switch $0 {
            case .enabled: return [.enabled]
            case .disabled: return [.disabled]
            }
        }
        let query = Operations.DevicesGetCollection.Input.Query(
            filter_lbrack_platform_rbrack_: platform.map { [$0.asDeviceFilterPlatform] },
            filter_lbrack_status_rbrack_: statusFilter
        )
        let input = Operations.DevicesGetCollection.Input(query: query)
        let response = try await client.devicesGetCollection(input)

        switch response {
        case .ok(let ok):
            let json = try ok.body.json
            allDevices.append(contentsOf: parseDevices(from: json.data))
            nextURL = json.links.next
        case .forbidden(let forbidden):
            let message = (try? forbidden.body.json.errorDescription) ?? "Forbidden"
            throw Error.badResponse(message)
        default:
            throw Error.badResponse("Failed to list devices")
        }

        // Paginate through remaining pages
        while let url = nextURL {
            let (data, nextLink) = try await fetchDevicesPage(url: url)
            allDevices.append(contentsOf: data)
            nextURL = nextLink
        }

        return allDevices
    }

    private func parseDevices(from data: [Components.Schemas.Device]) -> [Device] {
        data.compactMap { device -> Device? in
            guard let attributes = device.attributes else { return nil }
            let platform: Platform? = {
                switch attributes.platform {
                case .ios: return .ios
                case .macOs: return .macos
                default: return nil
                }
            }()
            return Device(
                id: device.id,
                name: attributes.name ?? "",
                udid: attributes.udid ?? "",
                platform: platform,
                status: attributes.status == .enabled ? .enabled : .disabled
            )
        }
    }

    private func fetchDevicesPage(url: String) async throws -> ([Device], String?) {
        let (data, response) = try await fetchPage(url: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw Error.badResponse("Failed to fetch devices page")
        }
        let devicesResponse = try jsonDecoder.decode(Components.Schemas.DevicesResponse.self, from: data)
        return (parseDevices(from: devicesResponse.data), devicesResponse.links.next)
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
