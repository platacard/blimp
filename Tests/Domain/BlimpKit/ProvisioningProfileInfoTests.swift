import XCTest
import Foundation
@testable import BlimpKit

final class ProvisioningProfileInfoTests: XCTestCase {

    private func makePlist(
        getTaskAllow: Bool? = nil,
        provisionedDevices: [String]? = nil,
        provisionsAllDevices: Bool? = nil,
        applicationIdentifier: String = "6NV3U8F9SN.com.example.app"
    ) -> [String: Any] {
        var entitlements: [String: Any] = ["application-identifier": applicationIdentifier]
        if let getTaskAllow {
            entitlements["get-task-allow"] = getTaskAllow
        }

        var plist: [String: Any] = [
            "UUID": "12345678-1234-1234-1234-123456789abc",
            "Name": "com.example.app",
            "TeamIdentifier": ["6NV3U8F9SN"],
            "CreationDate": Date(timeIntervalSince1970: 1_700_000_000),
            "ExpirationDate": Date(timeIntervalSince1970: 1_730_000_000),
            "Entitlements": entitlements
        ]
        if let provisionedDevices {
            plist["ProvisionedDevices"] = provisionedDevices
        }
        if let provisionsAllDevices {
            plist["ProvisionsAllDevices"] = provisionsAllDevices
        }
        return plist
    }

    // MARK: - Classification

    func testClassifiesDevelopmentProfile() throws {
        let info = try ProvisioningProfileInfo(plist: makePlist(getTaskAllow: true, provisionedDevices: ["udid1"]))
        XCTAssertEqual(info.profileClass, .development)
    }

    func testClassifiesAdhocProfile() throws {
        let info = try ProvisioningProfileInfo(plist: makePlist(getTaskAllow: false, provisionedDevices: ["udid1"]))
        XCTAssertEqual(info.profileClass, .adhoc)
    }

    func testClassifiesAdhocProfileWithoutGetTaskAllow() throws {
        let info = try ProvisioningProfileInfo(plist: makePlist(provisionedDevices: ["udid1"]))
        XCTAssertEqual(info.profileClass, .adhoc)
    }

    func testClassifiesAppStoreProfile() throws {
        let info = try ProvisioningProfileInfo(plist: makePlist())
        XCTAssertEqual(info.profileClass, .appstore)
    }

    func testClassifiesEnterpriseProfile() throws {
        let info = try ProvisioningProfileInfo(plist: makePlist(provisionsAllDevices: true))
        XCTAssertEqual(info.profileClass, .enterprise)
    }

    // MARK: - Fields

    func testExtractsBundleIdWithoutTeamPrefix() throws {
        let info = try ProvisioningProfileInfo(plist: makePlist())
        XCTAssertEqual(info.teamId, "6NV3U8F9SN")
        XCTAssertEqual(info.bundleId, "com.example.app")
    }

    func testKeepsWildcardBundleId() throws {
        let info = try ProvisioningProfileInfo(plist: makePlist(applicationIdentifier: "6NV3U8F9SN.*"))
        XCTAssertEqual(info.bundleId, "*")
    }

    func testParsesDates() throws {
        let info = try ProvisioningProfileInfo(plist: makePlist())
        XCTAssertEqual(info.creationDate, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(info.expirationDate, Date(timeIntervalSince1970: 1_730_000_000))
    }

    // MARK: - Errors

    func testThrowsOnMissingUUID() {
        var plist = makePlist()
        plist["UUID"] = nil

        XCTAssertThrowsError(try ProvisioningProfileInfo(plist: plist)) { error in
            XCTAssertTrue(error.localizedDescription.contains("UUID"))
        }
    }

    func testThrowsOnMissingApplicationIdentifier() {
        var plist = makePlist()
        plist["Entitlements"] = [String: Any]()

        XCTAssertThrowsError(try ProvisioningProfileInfo(plist: plist)) { error in
            XCTAssertTrue(error.localizedDescription.contains("application-identifier"))
        }
    }

    func testThrowsOnMissingCreationDate() {
        var plist = makePlist()
        plist["CreationDate"] = nil

        XCTAssertThrowsError(try ProvisioningProfileInfo(plist: plist)) { error in
            XCTAssertTrue(error.localizedDescription.contains("CreationDate"))
        }
    }

    // MARK: - CMS decoding

    func testDecodesPlistViaShell() throws {
        let mockShell = MockShellExecutor()
        mockShell.outputForCommand = { _ in
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0">
            <dict>
                <key>UUID</key>
                <string>test-uuid</string>
            </dict>
            </plist>
            """
        }

        let plist = try ProvisioningProfileInfo.decodePlist(
            profileData: Data("fake".utf8),
            shell: mockShell
        )

        XCTAssertEqual(plist["UUID"] as? String, "test-uuid")
        XCTAssertTrue(mockShell.executedCommands.first?.contains("security cms -D") == true)
    }
}
