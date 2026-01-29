import Foundation
@testable import ProvisioningAPI
import JWTProvider

class MockAPIClient: APIProtocol, @unchecked Sendable {
    var bundleIdsGetCollectionResponse: Operations.BundleIdsGetCollection.Output?
    var certificatesGetCollectionResponse: Operations.CertificatesGetCollection.Output?
    var certificatesCreateInstanceResponse: Operations.CertificatesCreateInstance.Output?
    var certificatesGetInstanceResponse: Operations.CertificatesGetInstance.Output?
    var certificatesDeleteInstanceResponse: Operations.CertificatesDeleteInstance.Output?
    var devicesGetCollectionResponse: Operations.DevicesGetCollection.Output?
    var devicesCreateInstanceResponse: Operations.DevicesCreateInstance.Output?
    var devicesUpdateInstanceResponse: Operations.DevicesUpdateInstance.Output?
    var profilesGetCollectionResponse: Operations.ProfilesGetCollection.Output?
    var profilesCreateInstanceResponse: Operations.ProfilesCreateInstance.Output?
    var profilesDeleteInstanceResponse: Operations.ProfilesDeleteInstance.Output?

    func bundleIdsGetCollection(_ input: Operations.BundleIdsGetCollection.Input) async throws -> Operations.BundleIdsGetCollection.Output {
        return bundleIdsGetCollectionResponse ?? .ok(.init(body: .json(.init(data: [], links: .init(_self: "http://test")))))
    }

    func certificatesGetCollection(_ input: Operations.CertificatesGetCollection.Input) async throws -> Operations.CertificatesGetCollection.Output {
        return certificatesGetCollectionResponse ?? .ok(.init(body: .json(.init(data: [], links: .init(_self: "http://test")))))
    }

    func certificatesCreateInstance(_ input: Operations.CertificatesCreateInstance.Input) async throws -> Operations.CertificatesCreateInstance.Output {
        if let response = certificatesCreateInstanceResponse { return response }
        throw NSError(domain: "MockAPIClient", code: 500, userInfo: [NSLocalizedDescriptionKey: "Response not set"])
    }

    func certificatesGetInstance(_ input: Operations.CertificatesGetInstance.Input) async throws -> Operations.CertificatesGetInstance.Output {
        if let response = certificatesGetInstanceResponse { return response }
        throw NSError(domain: "MockAPIClient", code: 500, userInfo: [NSLocalizedDescriptionKey: "Response not set"])
    }

    func certificatesDeleteInstance(_ input: Operations.CertificatesDeleteInstance.Input) async throws -> Operations.CertificatesDeleteInstance.Output {
        return certificatesDeleteInstanceResponse ?? .noContent(.init())
    }

    func devicesGetCollection(_ input: Operations.DevicesGetCollection.Input) async throws -> Operations.DevicesGetCollection.Output {
        return devicesGetCollectionResponse ?? .ok(.init(body: .json(.init(data: [], links: .init(_self: "http://test")))))
    }

    func devicesCreateInstance(_ input: Operations.DevicesCreateInstance.Input) async throws -> Operations.DevicesCreateInstance.Output {
        if let response = devicesCreateInstanceResponse { return response }
        throw NSError(domain: "MockAPIClient", code: 500, userInfo: [NSLocalizedDescriptionKey: "Response not set"])
    }

    func devicesUpdateInstance(_ input: Operations.DevicesUpdateInstance.Input) async throws -> Operations.DevicesUpdateInstance.Output {
        if let response = devicesUpdateInstanceResponse { return response }
        throw NSError(domain: "MockAPIClient", code: 500, userInfo: [NSLocalizedDescriptionKey: "Response not set"])
    }

    func profilesGetCollection(_ input: Operations.ProfilesGetCollection.Input) async throws -> Operations.ProfilesGetCollection.Output {
        return profilesGetCollectionResponse ?? .ok(.init(body: .json(.init(data: [], links: .init(_self: "http://test")))))
    }

    func profilesCreateInstance(_ input: Operations.ProfilesCreateInstance.Input) async throws -> Operations.ProfilesCreateInstance.Output {
        if let response = profilesCreateInstanceResponse { return response }
        throw NSError(domain: "MockAPIClient", code: 500, userInfo: [NSLocalizedDescriptionKey: "Response not set"])
    }

    func profilesDeleteInstance(_ input: Operations.ProfilesDeleteInstance.Input) async throws -> Operations.ProfilesDeleteInstance.Output {
        return profilesDeleteInstanceResponse ?? .noContent(.init())
    }
}

class MockJWTProvider: JWTProviding, @unchecked Sendable {
    func token() throws -> String {
        return "mock_token"
    }
    
    func token(expiration: TimeInterval) throws -> String {
        return "mock_token"
    }
    
    func token(keyId: String, keyIssuer: String, privateKey: String, lifetimeSec: TimeInterval) throws -> String {
        return "mock_token"
    }
}
