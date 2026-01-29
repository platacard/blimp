import XCTest
@testable import ProvisioningAPI

final class ProvisioningAPITests: XCTestCase {
    var api: ProvisioningAPI!
    var mockClient: MockAPIClient!
    var mockJWT: MockJWTProvider!
    
    override func setUp() {
        super.setUp()
        mockClient = MockAPIClient()
        mockJWT = MockJWTProvider()
        api = ProvisioningAPI(client: mockClient, jwtProvider: mockJWT)
    }
    
    func testGetBundleId() async throws {
        // Setup
        mockClient.bundleIdsGetCollectionResponse = .ok(.init(body: .json(
            .init(data: [
                .init(
                    _type: .bundleIds,
                    id: "bundle-123",
                    attributes: .init(identifier: "com.example.app"),
                    links: .init(_self: "http://test")
                )
            ], links: .init(_self: "http://test"))
        )))
        
        // Execute
        let id = try await api.getBundleId(identifier: "com.example.app")
        
        // Verify
        XCTAssertEqual(id, "bundle-123")
    }
    
    func testCreateCertificate() async throws {
        // Setup
        mockClient.certificatesCreateInstanceResponse = .created(.init(body: .json(
            .init(data: .init(
                _type: .certificates,
                id: "cert-123",
                attributes: .init(
                    name: "Cert Name",
                    certificateType: .development,
                    serialNumber: "serial",
                    certificateContent: "base64content"
                ),
                links: .init(_self: "http://test")
            ), links: .init(_self: "http://test"))
        )))
        
        // Execute
        let cert = try await api.createCertificate(csrContent: "csr", type: .development)
        
        // Verify
        XCTAssertEqual(cert.id, "cert-123")
        XCTAssertEqual(cert.content, Data(base64Encoded: "base64content"))
        XCTAssertEqual(cert.type, .development)
    }
    
    func testRegisterDevice() async throws {
        // Setup
        mockClient.devicesCreateInstanceResponse = .created(.init(body: .json(
            .init(data: .init(
                _type: .devices,
                id: "device-123",
                attributes: .init(
                    name: "iPhone",
                    platform: .ios,
                    udid: "udid-123",
                    status: .enabled
                ),
                links: .init(_self: "http://test")
            ), links: .init(_self: "http://test"))
        )))
        
        // Execute
        let device = try await api.registerDevice(name: "iPhone", udid: "udid-123", platform: .ios)
        
        // Verify
        XCTAssertEqual(device.id, "device-123")
        XCTAssertEqual(device.name, "iPhone")
        XCTAssertEqual(device.status, .enabled)
    }
    
    func testCreateProfile() async throws {
        // Setup
        mockClient.profilesCreateInstanceResponse = .created(.init(body: .json(
            .init(data: .init(
                _type: .profiles,
                id: "profile-123",
                attributes: .init(
                    name: "Profile Name",
                    profileType: .iosAppDevelopment,
                    profileContent: "base64profile",
                    expirationDate: Date()
                ),
                links: .init(_self: "http://test")
            ), links: .init(_self: "http://test"))
        )))
        
        // Execute
        let profile = try await api.createProfile(name: "Profile Name", type: .iosAppDevelopment, bundleId: "bundle-123", certificateIds: ["cert-123"])
        
        // Verify
        XCTAssertEqual(profile.id, "profile-123")
        XCTAssertEqual(profile.content, Data(base64Encoded: "base64profile"))
    }
}

