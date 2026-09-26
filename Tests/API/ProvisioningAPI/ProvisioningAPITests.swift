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
    
    func testGetBundleIdPicksTheExactMatchNextToAnUndocumentedPlatform() async throws {
        let recorder = RequestRecorder()
        let api = makeRawAPI(recorder: recorder, status: 200, json: Self.bundleIdsWithServicesID)

        let id = try await api.getBundleId(identifier: "com.example.app")

        XCTAssertEqual(id, "bundle-123")
        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/v1/bundleIds")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer mock_token")
        let query = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(query.first { $0.name == "filter[identifier]" }?.value, "com.example.app")
        XCTAssertEqual(query.first { $0.name == "limit" }?.value, "200")
    }

    func testGetBundleIdFollowsPagesToTheExactMatch() async throws {
        let recorder = RequestRecorder()
        let api = makeRawAPI(recorder: recorder, responses: [
            (200, """
            {"data":[{"type":"bundleIds","id":"widget-1","attributes":{"identifier":"com.example.app.widget","platform":"IOS"}}],"links":{"self":"http://test","next":"https://api.appstoreconnect.apple.com/v1/bundleIds?cursor=abc"}}
            """),
            (200, """
            {"data":[{"type":"bundleIds","id":"bundle-123","attributes":{"identifier":"com.example.app","platform":"UNIVERSAL"}}],"links":{"self":"http://test"}}
            """),
        ])

        let id = try await api.getBundleId(identifier: "com.example.app")

        XCTAssertEqual(id, "bundle-123")
        XCTAssertEqual(recorder.requests.last?.url?.absoluteString, "https://api.appstoreconnect.apple.com/v1/bundleIds?cursor=abc")
    }

    func testGetBundleIdWithoutAnExactMatchIsNil() async throws {
        let api = makeRawAPI(recorder: RequestRecorder(), status: 200, json: """
        {"data":[{"type":"bundleIds","id":"services-1","attributes":{"identifier":"com.example.app.signin","platform":"SERVICES"}}],"links":{"self":"http://test"}}
        """)

        let id = try await api.getBundleId(identifier: "com.example.app")

        XCTAssertNil(id)
    }

    func testGetBundleIdForbidden() async throws {
        let api = makeRawAPI(recorder: RequestRecorder(), status: 403, json: """
        {"errors":[{"id":"e1","status":"403","code":"FORBIDDEN","title":"Forbidden","detail":"Key lacks permission."}]}
        """)

        do {
            _ = try await api.getBundleId(identifier: "com.example.app")
            XCTFail("Expected forbidden")
        } catch ProvisioningAPI.Error.badResponse(let message) {
            XCTAssertEqual(message, "Key lacks permission.")
        }
    }

    func testUndecodableBundleIdsReplyNamesTheOperationAndThePath() async throws {
        let api = makeRawAPI(recorder: RequestRecorder(), status: 200, json: """
        {"data":[{"type":"bundleIds","attributes":{"identifier":"com.example.app","platform":"IOS"}}],"links":{"self":"http://test"}}
        """)

        do {
            _ = try await api.getBundleId(identifier: "com.example.app")
            XCTFail("Expected a decoding failure")
        } catch ProvisioningAPI.Error.badResponse(let message) {
            XCTAssertTrue(message.hasPrefix("Could not decode bundle IDs at data[0].id: "), message)
        }
    }

    /// Why bundle IDs and profiles bypass the generated client: its closed enums reject these replies.
    func testGeneratedDecodersRejectUndocumentedValuesTheRawPathsAccept() throws {
        let bundleIds = Data(Self.bundleIdsWithServicesID.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Components.Schemas.BundleIdsResponse.self, from: bundleIds)) {
            XCTAssertEqual(Self.codingPath(of: $0), "data[0].attributes.platform")
        }
        XCTAssertNoThrow(try JSONDecoder().decode(BundleIdsPageResponse.self, from: bundleIds))

        let profiles = Data(Self.profilesWithUndocumentedType.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Components.Schemas.ProfilesResponse.self, from: profiles)) {
            XCTAssertEqual(Self.codingPath(of: $0), "data[0].attributes.profileType")
        }
        XCTAssertNoThrow(try JSONDecoder().decode(ProfilesPageResponse.self, from: profiles))
    }

    func testListCertificatesMapsTheExpirationDate() async throws {
        let expiry = Date(timeIntervalSince1970: 1_800_000_000)
        mockClient.certificatesGetCollectionResponse = .ok(.init(body: .json(.init(
            data: [.init(
                _type: .certificates,
                id: "cert-123",
                attributes: .init(name: "Apple Distribution", certificateType: .distribution, expirationDate: expiry)
            )],
            links: .init(_self: "http://test")
        ))))

        let certificates = try await api.listCertificates(filterType: .distribution)

        XCTAssertEqual(certificates.map(\.expirationDate), [expiry])
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
                    expirationDate: Date(timeIntervalSince1970: 1_800_000_000),
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
        XCTAssertEqual(cert.expirationDate, Date(timeIntervalSince1970: 1_800_000_000))
    }
    
    func testRegisterDeviceProcessing() async throws {
        let recorder = RequestRecorder()
        let api = makeRawAPI(recorder: recorder, status: 201, json: """
        {"data":{"type":"devices","id":"device-123","attributes":{"name":"iPhone","platform":"IOS","udid":"udid-123","deviceClass":"IPHONE","status":"PROCESSING","model":"iPhone 13 Pro Max","addedDate":"2026-09-18T08:52:07.000+00:00"},"links":{"self":"http://test"}},"links":{"self":"http://test"}}
        """)

        let device = try await api.registerDevice(name: "iPhone", udid: "udid-123", platform: .ios).device

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

        let device = try await api.registerDevice(name: "iPhone", udid: "udid-123", platform: .ios).device

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

        let device = try await api.registerDevice(name: "iPhone", udid: "udid-123", platform: .ios).device

        XCTAssertEqual(device.status, .unknown("INELIGIBLE"))
    }

    func testRegisterDeviceConflictReturnsTheExistingDevice() async throws {
        let recorder = RequestRecorder()
        let api = makeRawAPI(recorder: recorder, responses: [
            (409, """
            {"errors":[{"id":"e1","status":"409","code":"ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE","title":"Duplicate","detail":"A device with UDID 'udid-123' already exists on this team."}]}
            """),
            (200, """
            {"data":[{"type":"devices","id":"device-old","attributes":{"name":"Old iPhone","platform":"IOS","udid":"UDID-123","status":"ENABLED"},"links":{"self":"http://test"}}],"links":{"self":"http://test"}}
            """),
        ])

        let registration = try await api.registerDevice(name: "Apple TV", udid: "udid-123", platform: .tvos)

        guard case .alreadyRegistered(let device) = registration else { return XCTFail("\(registration)") }
        XCTAssertEqual(device.id, "device-old")
        XCTAssertEqual(device.name, "Old iPhone")
        XCTAssertEqual(device.status, .enabled)
        XCTAssertEqual(device.platform, .tvos)
        XCTAssertEqual(recorder.requests.map(\.httpMethod), ["POST", "GET"])
        XCTAssertEqual(recorder.requests.last?.url?.path, "/v1/devices")
    }

    func testRegisterDeviceConflictWithoutAMatchingDeviceIsStillAnError() async throws {
        let api = makeRawAPI(recorder: RequestRecorder(), responses: [
            (409, """
            {"errors":[{"id":"e1","status":"409","code":"ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE","title":"Duplicate","detail":"A device with UDID 'udid-123' already exists on this team."}]}
            """),
            (200, """
            {"data":[],"links":{"self":"http://test"}}
            """),
        ])

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

    func testRegisterDevicePreservesRequestedPlatform() async throws {
        let api = makeRawAPI(recorder: RequestRecorder(), status: 201, json: """
        {"data":{"type":"devices","id":"device-123","attributes":{"name":"Apple TV","platform":"IOS","udid":"udid-123","status":"ENABLED"},"links":{"self":"http://test"}},"links":{"self":"http://test"}}
        """)

        let device = try await api.registerDevice(name: "Apple TV", udid: "udid-123", platform: .tvos).device

        XCTAssertEqual(device.platform, .tvos)
    }

    func testListDevicesDecodesProcessingDevicesAndPaginates() async throws {
        let recorder = RequestRecorder()
        let api = makeRawAPI(recorder: recorder, responses: [
            (200, """
            {"data":[{"type":"devices","id":"d1","attributes":{"name":"New","platform":"IOS","udid":"u1","status":"PROCESSING"}}],"links":{"self":"http://test","next":"https://api.appstoreconnect.apple.com/v1/devices?cursor=abc"}}
            """),
            (200, """
            {"data":[{"type":"devices","id":"d2","attributes":{"name":"Old","platform":"MAC_OS","udid":"u2","status":"ENABLED"}}],"links":{"self":"http://test"}}
            """),
        ])

        let devices = try await api.listDevices(platform: .ios, status: nil)

        XCTAssertEqual(devices.map(\.id), ["d1", "d2"])
        XCTAssertEqual(devices.map(\.status), [.processing, .enabled])
        XCTAssertEqual(devices.map(\.platform), [.ios, .macos])

        let first = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(first.httpMethod, "GET")
        XCTAssertEqual(first.url?.path, "/v1/devices")
        XCTAssertEqual(first.value(forHTTPHeaderField: "Authorization"), "Bearer mock_token")
        let query = URLComponents(url: try XCTUnwrap(first.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(query.first { $0.name == "filter[platform]" }?.value, "IOS")
        XCTAssertEqual(query.first { $0.name == "limit" }?.value, "200")
        XCTAssertNil(query.first { $0.name == "filter[status]" })
        XCTAssertEqual(recorder.requests.last?.url?.absoluteString, "https://api.appstoreconnect.apple.com/v1/devices?cursor=abc")
    }

    func testListDevicesAppliesStatusFilter() async throws {
        let recorder = RequestRecorder()
        let api = makeRawAPI(recorder: recorder, status: 200, json: """
        {"data":[],"links":{"self":"http://test"}}
        """)

        let devices = try await api.listDevices(platform: nil, status: .disabled)

        XCTAssertTrue(devices.isEmpty)
        let query = URLComponents(url: try XCTUnwrap(recorder.requests.first?.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(query.first { $0.name == "filter[status]" }?.value, "DISABLED")
        XCTAssertNil(query.first { $0.name == "filter[platform]" })
    }

    func testListDevicesRejectsUnsupportedStatusFilterLocally() async throws {
        let recorder = RequestRecorder()
        let api = makeRawAPI(recorder: recorder, status: 200, json: """
        {"data":[],"links":{"self":"http://test"}}
        """)

        for status in [ProvisioningAPI.Device.Status.processing, .unknown("INELIGIBLE"), .unknown("")] {
            do {
                _ = try await api.listDevices(platform: nil, status: status)
                XCTFail("Expected local rejection for \(status)")
            } catch ProvisioningAPI.Error.badRequest(let message) {
                XCTAssertTrue(message.contains("enabled"), "Unexpected message: \(message)")
            }
        }
        XCTAssertTrue(recorder.requests.isEmpty, "No request should reach the API")
    }

    func testListDevicesForbidden() async throws {
        let api = makeRawAPI(recorder: RequestRecorder(), status: 403, json: """
        {"errors":[{"id":"e1","status":"403","code":"FORBIDDEN","title":"Forbidden","detail":"Key lacks permission."}]}
        """)

        do {
            _ = try await api.listDevices()
            XCTFail("Expected forbidden")
        } catch ProvisioningAPI.Error.badResponse(let message) {
            XCTAssertEqual(message, "Key lacks permission.")
        }
    }

    private func makeRawAPI(recorder: RequestRecorder, status: Int, json: String) -> ProvisioningAPI {
        makeRawAPI(recorder: recorder, responses: [(status, json)])
    }

    private func makeRawAPI(recorder: RequestRecorder, responses: [(status: Int, json: String)]) -> ProvisioningAPI {
        let queue = ResponseQueue(responses)
        return ProvisioningAPI(client: mockClient, jwtProvider: mockJWT) { request in
            recorder.record(request)
            let next = try queue.dequeue()
            let response = HTTPURLResponse(url: request.url!, statusCode: next.status, httpVersion: nil, headerFields: nil)!
            return (Data(next.json.utf8), response)
        }
    }

    func testCreateProfileSendsTheRequestAndDecodesUndocumentedValues() async throws {
        let recorder = RequestRecorder()
        let api = makeRawAPI(recorder: recorder, status: 201, json: """
        {"data":{"type":"profiles","id":"profile-123","attributes":{"name":"Profile Name","platform":"IOS","profileType":"IOS_APP_DEVELOPMENT","profileState":"PROCESSING","profileContent":"YmFzZTY0cHJvZmlsZQ==","uuid":"u-1","createdDate":"2026-09-26T10:00:00.000+00:00","expirationDate":"2027-01-15T08:00:00.000+00:00"},"links":{"self":"http://test"}},"links":{"self":"http://test"}}
        """)

        let profile = try await api.createProfile(
            name: "Profile Name",
            type: .iosAppDevelopment,
            bundleId: "bundle-123",
            certificateIds: ["cert-123"],
            deviceIds: ["device-1", "device-2"]
        )

        XCTAssertEqual(profile.id, "profile-123")
        XCTAssertEqual(profile.name, "Profile Name")
        XCTAssertEqual(profile.type, .iosAppDevelopment)
        XCTAssertEqual(profile.content, Data("base64profile".utf8))
        XCTAssertEqual(profile.expirationDate, Date(timeIntervalSince1970: 1_800_000_000))

        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/v1/profiles")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer mock_token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        let data = try XCTUnwrap(body["data"] as? [String: Any])
        XCTAssertEqual(data["type"] as? String, "profiles")
        let attributes = data["attributes"] as? [String: Any]
        XCTAssertEqual(attributes?["name"] as? String, "Profile Name")
        XCTAssertEqual(attributes?["profileType"] as? String, "IOS_APP_DEVELOPMENT")
        let relationships = try XCTUnwrap(data["relationships"] as? [String: Any])
        XCTAssertEqual(Self.relationshipIds(relationships["bundleId"]), ["bundle-123"])
        XCTAssertEqual(Self.relationshipIds(relationships["certificates"]), ["cert-123"])
        XCTAssertEqual(Self.relationshipIds(relationships["devices"]), ["device-1", "device-2"])
    }

    func testCreateProfileWithoutDevicesSendsNoDevicesRelationship() async throws {
        let recorder = RequestRecorder()
        let api = makeRawAPI(recorder: recorder, status: 201, json: """
        {"data":{"type":"profiles","id":"profile-123","attributes":{"name":"Profile Name","profileType":"IOS_APP_STORE","profileContent":"YmFzZTY0cHJvZmlsZQ=="}},"links":{"self":"http://test"}}
        """)

        _ = try await api.createProfile(name: "Profile Name", type: .iosAppStore, bundleId: "bundle-123", certificateIds: ["cert-123"])

        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(recorder.requests.first?.httpBody)) as? [String: Any]
        let relationships = (body?["data"] as? [String: Any])?["relationships"] as? [String: Any]
        XCTAssertNotNil(relationships?["bundleId"])
        XCTAssertNil(relationships?["devices"])
    }

    func testCreateProfileErrorMapping() async throws {
        let errorJSON = """
        {"errors":[{"id":"e1","status":"409","code":"ENTITY_ERROR","title":"Error","detail":"Multiple profiles found with the name 'Profile Name'."}]}
        """
        let detail = "Multiple profiles found with the name 'Profile Name'."
        let cases: [(status: Int, check: (ProvisioningAPI.Error) -> Bool)] = [
            (400, { if case .badRequest(detail) = $0 { true } else { false } }),
            (422, { if case .badRequest(detail) = $0 { true } else { false } }),
            (409, { if case .conflict(detail) = $0 { true } else { false } }),
            (403, { if case .badResponse(detail) = $0 { true } else { false } }),
            (500, { if case .badResponse(detail) = $0 { true } else { false } }),
        ]

        for testCase in cases {
            let api = makeRawAPI(recorder: RequestRecorder(), status: testCase.status, json: errorJSON)
            do {
                _ = try await api.createProfile(name: "Profile Name", type: .iosAppStore, bundleId: "bundle-123", certificateIds: ["cert-123"])
                XCTFail("Expected error for HTTP \(testCase.status)")
            } catch let error as ProvisioningAPI.Error {
                XCTAssertTrue(testCase.check(error), "Unexpected mapping for HTTP \(testCase.status): \(error)")
            }
        }
    }

    func testListProfilesDecodesUndocumentedValuesAndKeepsTheExactName() async throws {
        let recorder = RequestRecorder()
        let api = makeRawAPI(recorder: recorder, responses: [
            (200, Self.profilesWithUndocumentedType.replacingOccurrences(
                of: #""links":{"self":"http://test"}}"#,
                with: #""links":{"self":"http://test","next":"https://api.appstoreconnect.apple.com/v1/profiles?cursor=abc"}}"#
            )),
            (200, """
            {"data":[{"type":"profiles","id":"p-app","attributes":{"name":"com.example.app","platform":"IOS","profileType":"IOS_APP_STORE","profileState":"EXPIRED","profileContent":"cHJvZmlsZQ==","expirationDate":"2027-01-15T08:00:00Z"}},{"type":"profiles","id":"p-widget","attributes":{"name":"com.example.app.widget","platform":"IOS","profileType":"IOS_APP_STORE","profileState":"ACTIVE"}}],"links":{"self":"http://test"}}
            """),
        ])

        let profiles = try await api.listProfiles(name: "com.example.app")

        XCTAssertEqual(profiles.map(\.id), ["p-undocumented", "p-app"])
        XCTAssertEqual(profiles.map(\.type), [nil, .iosAppStore])
        XCTAssertEqual(profiles.last?.content, Data("profile".utf8))
        XCTAssertEqual(profiles.last?.expirationDate, Date(timeIntervalSince1970: 1_800_000_000))

        let first = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(first.httpMethod, "GET")
        XCTAssertEqual(first.url?.path, "/v1/profiles")
        XCTAssertEqual(first.value(forHTTPHeaderField: "Authorization"), "Bearer mock_token")
        let query = URLComponents(url: try XCTUnwrap(first.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(query.first { $0.name == "filter[name]" }?.value, "com.example.app")
        XCTAssertEqual(query.first { $0.name == "limit" }?.value, "200")
        XCTAssertEqual(recorder.requests.last?.url?.absoluteString, "https://api.appstoreconnect.apple.com/v1/profiles?cursor=abc")
    }

    func testListProfilesWithoutANameListsEveryProfile() async throws {
        let recorder = RequestRecorder()
        let api = makeRawAPI(recorder: recorder, status: 200, json: Self.profilesWithUndocumentedType)

        let profiles = try await api.listProfiles(name: nil)

        XCTAssertEqual(profiles.map(\.id), ["p-undocumented"])
        let query = URLComponents(url: try XCTUnwrap(recorder.requests.first?.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertNil(query.first { $0.name == "filter[name]" })
    }

    func testListProfilesForbidden() async throws {
        let api = makeRawAPI(recorder: RequestRecorder(), status: 403, json: """
        {"errors":[{"id":"e1","status":"403","code":"FORBIDDEN","title":"Forbidden","detail":"Key lacks permission."}]}
        """)

        do {
            _ = try await api.listProfiles(name: "com.example.app")
            XCTFail("Expected forbidden")
        } catch ProvisioningAPI.Error.badResponse(let message) {
            XCTAssertEqual(message, "Key lacks permission.")
        }
    }

    func testDeleteProfileNotFoundIsDistinct() async throws {
        mockClient.profilesDeleteInstanceResponse = .notFound(.init(body: .json(.init(errors: [
            .init(status: "404", code: "NOT_FOUND", title: "Not found", detail: "There is no resource of type 'profiles' with id 'p-1'")
        ]))))

        do {
            try await api.deleteProfile(id: "p-1")
            XCTFail("Expected not found")
        } catch ProvisioningAPI.Error.notFound(let message) {
            XCTAssertEqual(message, "Profile p-1")
        }
    }
}

private extension ProvisioningAPITests {
    static let bundleIdsWithServicesID = """
    {"data":[{"type":"bundleIds","id":"services-1","attributes":{"name":"Sign in with Apple","identifier":"com.example.app.signin","platform":"SERVICES","seedId":"TEAMID1234"},"links":{"self":"http://test"}},{"type":"bundleIds","id":"bundle-123","attributes":{"name":"Example","identifier":"com.example.app","platform":"IOS","seedId":"TEAMID1234"},"links":{"self":"http://test"}}],"links":{"self":"http://test"},"meta":{"paging":{"total":2,"limit":200}}}
    """

    static let profilesWithUndocumentedType = """
    {"data":[{"type":"profiles","id":"p-undocumented","attributes":{"name":"com.example.app","platform":"IOS","profileType":"VISIONOS_APP_STORE","profileState":"ACTIVE"}}],"links":{"self":"http://test"}}
    """

    static func codingPath(of error: any Error) -> String? {
        guard case .dataCorrupted(let context) = error as? DecodingError else { return nil }
        return context.codingPath.reduce("") { path, key in
            key.intValue.map { "\(path)[\($0)]" } ?? (path.isEmpty ? key.stringValue : "\(path).\(key.stringValue)")
        }
    }

    static func relationshipIds(_ relationship: Any?) -> [String] {
        let data = (relationship as? [String: Any])?["data"]
        let items = (data as? [[String: Any]]) ?? [data as? [String: Any]].compactMap { $0 }
        return items.compactMap { $0["id"] as? String }
    }
}
