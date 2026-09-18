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
    
    func testRegisterDeviceProcessing() async throws {
        let recorder = RequestRecorder()
        let api = makeRawAPI(recorder: recorder, status: 201, json: """
        {"data":{"type":"devices","id":"device-123","attributes":{"name":"iPhone","platform":"IOS","udid":"udid-123","deviceClass":"IPHONE","status":"PROCESSING","model":"iPhone 13 Pro Max","addedDate":"2026-09-18T08:52:07.000+00:00"},"links":{"self":"http://test"}},"links":{"self":"http://test"}}
        """)

        let device = try await api.registerDevice(name: "iPhone", udid: "udid-123", platform: .ios)

        XCTAssertEqual(device.id, "device-123")
        XCTAssertEqual(device.name, "iPhone")
        XCTAssertEqual(device.udid, "udid-123")
        XCTAssertEqual(device.platform, .ios)
        XCTAssertEqual(device.status, .processing)
    }

    func testRegisterDeviceEnabledSendsCreateRequest() async throws {
        let recorder = RequestRecorder()
        let api = makeRawAPI(recorder: recorder, status: 201, json: """
        {"data":{"type":"devices","id":"device-123","attributes":{"name":"iPhone","platform":"IOS","udid":"udid-123","status":"ENABLED"},"links":{"self":"http://test"}},"links":{"self":"http://test"}}
        """)

        let device = try await api.registerDevice(name: "iPhone", udid: "udid-123", platform: .ios)

        XCTAssertEqual(device.status, .enabled)
        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/v1/devices")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer mock_token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
        let attributes = (body?["data"] as? [String: Any])?["attributes"] as? [String: Any]
        XCTAssertEqual(attributes?["udid"] as? String, "udid-123")
        XCTAssertEqual(attributes?["name"] as? String, "iPhone")
        XCTAssertEqual(attributes?["platform"] as? String, "IOS")
    }

    func testRegisterDeviceUnknownStatusIsPreserved() async throws {
        let api = makeRawAPI(recorder: RequestRecorder(), status: 201, json: """
        {"data":{"type":"devices","id":"device-123","attributes":{"name":"iPhone","platform":"IOS","udid":"udid-123","status":"INELIGIBLE"},"links":{"self":"http://test"}},"links":{"self":"http://test"}}
        """)

        let device = try await api.registerDevice(name: "iPhone", udid: "udid-123", platform: .ios)

        XCTAssertEqual(device.status, .unknown("INELIGIBLE"))
    }

    func testRegisterDeviceConflict() async throws {
        let api = makeRawAPI(recorder: RequestRecorder(), status: 409, json: """
        {"errors":[{"id":"e1","status":"409","code":"ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE","title":"Duplicate","detail":"A device with UDID 'udid-123' already exists on this team."}]}
        """)

        do {
            _ = try await api.registerDevice(name: "iPhone", udid: "udid-123", platform: .ios)
            XCTFail("Expected conflict")
        } catch ProvisioningAPI.Error.conflict(let message) {
            XCTAssertEqual(message, "A device with UDID 'udid-123' already exists on this team.")
        }
    }

    func testRegisterDeviceErrorMapping() async throws {
        let errorJSON = """
        {"errors":[{"id":"e1","status":"400","code":"PARAMETER_ERROR.INVALID","title":"Invalid","detail":"Something went wrong."}]}
        """
        let cases: [(status: Int, check: (ProvisioningAPI.Error) -> Bool)] = [
            (400, { if case .badRequest("Something went wrong.") = $0 { true } else { false } }),
            (422, { if case .badRequest("Something went wrong.") = $0 { true } else { false } }),
            (403, { if case .badResponse("Something went wrong.") = $0 { true } else { false } }),
            (500, { if case .undocumented = $0 { true } else { false } }),
        ]

        for testCase in cases {
            let api = makeRawAPI(recorder: RequestRecorder(), status: testCase.status, json: errorJSON)
            do {
                _ = try await api.registerDevice(name: "iPhone", udid: "udid-123", platform: .ios)
                XCTFail("Expected error for HTTP \(testCase.status)")
            } catch let error as ProvisioningAPI.Error {
                XCTAssertTrue(testCase.check(error), "Unexpected mapping for HTTP \(testCase.status): \(error)")
            }
        }
    }

    private func makeRawAPI(recorder: RequestRecorder, status: Int, json: String) -> ProvisioningAPI {
        ProvisioningAPI(client: mockClient, jwtProvider: mockJWT) { request in
            recorder.record(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(json.utf8), response)
        }
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

