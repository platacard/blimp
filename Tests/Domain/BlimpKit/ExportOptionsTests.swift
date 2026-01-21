import XCTest
@testable import BlimpKit
import Foundation

final class ExportOptionsTests: XCTestCase {

    // MARK: - ExportMethod Tests

    func testExportMethodRawValues() {
        XCTAssertEqual(ExportOptions.Method.appStoreConnect.rawValue, "app-store-connect")
        XCTAssertEqual(ExportOptions.Method.releaseTesting.rawValue, "release-testing")
        XCTAssertEqual(ExportOptions.Method.debugging.rawValue, "debugging")
        XCTAssertEqual(ExportOptions.Method.enterprise.rawValue, "enterprise")
        XCTAssertEqual(ExportOptions.Method.developerID.rawValue, "developer-id")
    }

    // MARK: - SigningStyle Tests

    func testSigningStyleRawValues() {
        XCTAssertEqual(ExportOptions.SigningStyle.manual.rawValue, "manual")
        XCTAssertEqual(ExportOptions.SigningStyle.automatic.rawValue, "automatic")
    }

    // MARK: - SigningCertificate Tests

    func testSigningCertificateRawValues() {
        XCTAssertEqual(ExportOptions.SigningCertificate.appleDistribution.rawValue, "Apple Distribution")
        XCTAssertEqual(ExportOptions.SigningCertificate.appleDevelopment.rawValue, "Apple Development")
        XCTAssertEqual(ExportOptions.SigningCertificate.developerIDApplication.rawValue, "Developer ID Application")
        XCTAssertEqual(ExportOptions.SigningCertificate.custom("My Custom Cert").rawValue, "My Custom Cert")
    }

    // MARK: - Destination Tests

    func testDestinationRawValues() {
        XCTAssertEqual(ExportOptions.Destination.export.rawValue, "export")
        XCTAssertEqual(ExportOptions.Destination.upload.rawValue, "upload")
    }

    // MARK: - ExportOptions Initialization Tests

    func testExportOptionsMinimalInit() {
        let options = ExportOptions(
            method: .appStoreConnect,
            signingStyle: .manual,
            signingCertificate: .appleDistribution,
            teamID: "123"
        )

        XCTAssertEqual(options.method, .appStoreConnect)
        XCTAssertEqual(options.provisioningProfiles, [:])
        XCTAssertEqual(options.manageAppVersionAndBuildNumber, false)
        XCTAssertEqual(options.testFlightInternalTestingOnly, false)
        XCTAssertEqual(options.uploadSymbols, true)
        XCTAssertEqual(options.destination, .export)
        XCTAssertEqual(options.teamID, "123")
    }

    func testExportOptionsFullInit() {
        let profiles: [String: String] = [
            "com.example.app": "App Profile",
            "com.example.app.widget": "Widget Profile"
        ]

        let options = ExportOptions(
            method: .appStoreConnect,
            signingStyle: .manual,
            signingCertificate: .appleDistribution,
            provisioningProfiles: profiles,
            teamID: "TEAM123",
            manageAppVersionAndBuildNumber: false,
            testFlightInternalTestingOnly: true,
            uploadSymbols: true,
            destination: .upload
        )

        XCTAssertEqual(options.method, .appStoreConnect)
        XCTAssertEqual(options.signingStyle, .manual)
        XCTAssertEqual(options.signingCertificate, .appleDistribution)
        XCTAssertEqual(options.provisioningProfiles, profiles)
        XCTAssertEqual(options.teamID, "TEAM123")
        XCTAssertEqual(options.manageAppVersionAndBuildNumber, false)
        XCTAssertEqual(options.testFlightInternalTestingOnly, true)
        XCTAssertEqual(options.uploadSymbols, true)
        XCTAssertEqual(options.destination, .upload)
    }

    // MARK: - Plist Generation Tests

    func testPlistGenerationMinimal() throws {
        let options = ExportOptions(
            method: .appStoreConnect,
            signingStyle: .manual,
            signingCertificate: .appleDistribution,
            teamID: "123"
        )
        let plistData = try options.plistData()

        let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]

        XCTAssertNotNil(plist)
        XCTAssertEqual(plist?["method"] as? String, "app-store-connect")
        XCTAssertEqual(plist?["signingStyle"] as? String, "manual")
        XCTAssertEqual(plist?["signingCertificate"] as? String, "Apple Distribution")
        XCTAssertEqual(plist?["teamID"] as? String, "123")
    }

    func testPlistGenerationWithProvisioningProfiles() throws {
        let profiles: [String: String] = [
            "com.example.app": "App Profile",
            "com.example.app.widget": "Widget Profile"
        ]

        let options = ExportOptions(
            method: .appStoreConnect,
            signingStyle: .manual,
            signingCertificate: .appleDistribution,
            provisioningProfiles: profiles,
            teamID: "123"
        )

        let plistData = try options.plistData()
        let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]

        XCTAssertNotNil(plist)
        XCTAssertEqual(plist?["method"] as? String, "app-store-connect")
        XCTAssertEqual(plist?["signingStyle"] as? String, "manual")
        XCTAssertEqual(plist?["signingCertificate"] as? String, "Apple Distribution")
        XCTAssertEqual(plist?["teamID"] as? String, "123")

        let plistProfiles = plist?["provisioningProfiles"] as? [String: String]
        XCTAssertEqual(plistProfiles?["com.example.app"], "App Profile")
        XCTAssertEqual(plistProfiles?["com.example.app.widget"], "Widget Profile")
    }

    func testPlistGenerationWithAllOptions() throws {
        let options = ExportOptions(
            method: .releaseTesting,
            signingStyle: .automatic,
            signingCertificate: .appleDevelopment,
            provisioningProfiles: ["com.test": "Test Profile"],
            teamID: "ABC123",
            manageAppVersionAndBuildNumber: true,
            testFlightInternalTestingOnly: false,
            uploadSymbols: false,
            destination: .export,
            stripSwiftSymbols: true,
            thinning: "<thin-for-all-variants>",
            iCloudContainerEnvironment: "Production"
        )

        let plistData = try options.plistData()
        let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]

        XCTAssertNotNil(plist)
        XCTAssertEqual(plist?["method"] as? String, "release-testing")
        XCTAssertEqual(plist?["signingStyle"] as? String, "automatic")
        XCTAssertEqual(plist?["signingCertificate"] as? String, "Apple Development")
        XCTAssertEqual(plist?["teamID"] as? String, "ABC123")
        XCTAssertEqual(plist?["manageAppVersionAndBuildNumber"] as? Bool, true)
        XCTAssertEqual(plist?["testFlightInternalTestingOnly"] as? Bool, false)
        XCTAssertEqual(plist?["uploadSymbols"] as? Bool, false)
        XCTAssertEqual(plist?["destination"] as? String, "export")
        XCTAssertEqual(plist?["stripSwiftSymbols"] as? Bool, true)
        XCTAssertEqual(plist?["thinning"] as? String, "<thin-for-all-variants>")
        XCTAssertEqual(plist?["iCloudContainerEnvironment"] as? String, "Production")
    }

    func testWritePlistToFile() throws {
        let profiles: [String: String] = [
            "dif.tech.bank.beta": "dif.tech.bank.beta"
        ]

        let options = ExportOptions(
            method: .appStoreConnect,
            signingStyle: .manual,
            signingCertificate: .appleDistribution,
            provisioningProfiles: profiles,
            teamID: "123",
            manageAppVersionAndBuildNumber: false,
            testFlightInternalTestingOnly: false
        )

        let tempDir = FileManager.default.temporaryDirectory
        let plistPath = tempDir.appendingPathComponent("test-export-options.plist")

        try options.writePlist(to: plistPath)

        XCTAssertTrue(FileManager.default.fileExists(atPath: plistPath.path))

        let data = try Data(contentsOf: plistPath)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]

        XCTAssertEqual(plist?["method"] as? String, "app-store-connect")
        XCTAssertEqual(plist?["signingStyle"] as? String, "manual")
        XCTAssertEqual(plist?["teamID"] as? String, "123")

        try FileManager.default.removeItem(at: plistPath)
    }
}
