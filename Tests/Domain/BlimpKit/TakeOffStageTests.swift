import XCTest
@testable import BlimpKit

final class TakeOffStageTests: XCTestCase {

    // MARK: - ArchiveArgument Tests

    func testArchiveArgumentClean() {
        let arg = Blimp.TakeOff.ArchiveArgument.clean
        XCTAssertEqual(arg.bashArgument, "clean")
    }

    func testArchiveArgumentWorkspacePath() {
        let arg = Blimp.TakeOff.ArchiveArgument.workspacePath("/path/to/App.xcworkspace")
        XCTAssertEqual(arg.bashArgument, "-workspace /path/to/App.xcworkspace")
    }

    func testArchiveArgumentProjectPath() {
        let arg = Blimp.TakeOff.ArchiveArgument.projectPath("/path/to/App.xcodeproj")
        XCTAssertEqual(arg.bashArgument, "-project /path/to/App.xcodeproj")
    }

    func testArchiveArgumentScheme() {
        let arg = Blimp.TakeOff.ArchiveArgument.scheme("MyApp")
        XCTAssertEqual(arg.bashArgument, "-scheme MyApp")
    }

    func testArchiveArgumentArchivePath() {
        let arg = Blimp.TakeOff.ArchiveArgument.archivePath("/path/to/build/App.xcarchive")
        XCTAssertEqual(arg.bashArgument, "-archivePath /path/to/build/App.xcarchive")
    }

    func testArchiveArgumentConfigurationDebug() {
        let arg = Blimp.TakeOff.ArchiveArgument.configuration(.debug)
        XCTAssertEqual(arg.bashArgument, "-configuration Debug")
    }

    func testArchiveArgumentConfigurationBeta() {
        let arg = Blimp.TakeOff.ArchiveArgument.configuration(.beta)
        XCTAssertEqual(arg.bashArgument, "-configuration Beta")
    }

    func testArchiveArgumentConfigurationRelease() {
        let arg = Blimp.TakeOff.ArchiveArgument.configuration(.release)
        XCTAssertEqual(arg.bashArgument, "-configuration Release")
    }

    func testArchiveArgumentConfigurationCustom() {
        let arg = Blimp.TakeOff.ArchiveArgument.configuration(.custom("Enterprise"))
        XCTAssertEqual(arg.bashArgument, "-configuration Enterprise")
    }

    func testArchiveArgumentDestination() {
        let arg = Blimp.TakeOff.ArchiveArgument.destination(.anyIOSDevice)
        XCTAssertEqual(arg.bashArgument, "-destination generic/platform=iOS")
    }

    func testArchiveArgumentCleanOutput() {
        let arg = Blimp.TakeOff.ArchiveArgument.cleanOutput
        XCTAssertEqual(arg.bashArgument, "| xcbeautify")
    }

    // MARK: - ExportArgument Tests

    func testExportArgumentExportArchive() {
        let arg = Blimp.TakeOff.ExportArgument.exportArchive("/path/to/App.xcarchive")
        XCTAssertEqual(arg.bashArgument, "-exportArchive -archivePath /path/to/App.xcarchive")
    }

    func testExportArgumentExportPath() {
        let arg = Blimp.TakeOff.ExportArgument.exportPath("/path/to/export")
        XCTAssertEqual(arg.bashArgument, "-exportPath /path/to/export")
    }

    func testExportArgumentOptionsPlistPath() {
        let arg = Blimp.TakeOff.ExportArgument.optionsPlistPath("/path/to/ExportOptions.plist")
        XCTAssertEqual(arg.bashArgument, "-exportOptionsPlist /path/to/ExportOptions.plist")
    }

    // MARK: - Configuration Tests

    func testConfigurationRawValues() {
        XCTAssertEqual(Blimp.TakeOff.Configuration.debug.rawValue, "Debug")
        XCTAssertEqual(Blimp.TakeOff.Configuration.beta.rawValue, "Beta")
        XCTAssertEqual(Blimp.TakeOff.Configuration.release.rawValue, "Release")
        XCTAssertEqual(Blimp.TakeOff.Configuration.custom("Staging").rawValue, "Staging")
    }

    func testConfigurationFromRawValue() {
        XCTAssertEqual(Blimp.TakeOff.Configuration(rawValue: "debug")?.rawValue, "Debug")
        XCTAssertEqual(Blimp.TakeOff.Configuration(rawValue: "DEBUG")?.rawValue, "Debug")
        XCTAssertEqual(Blimp.TakeOff.Configuration(rawValue: "beta")?.rawValue, "Beta")
        XCTAssertEqual(Blimp.TakeOff.Configuration(rawValue: "BETA")?.rawValue, "Beta")
        XCTAssertEqual(Blimp.TakeOff.Configuration(rawValue: "release")?.rawValue, "Release")
        XCTAssertEqual(Blimp.TakeOff.Configuration(rawValue: "RELEASE")?.rawValue, "Release")
        XCTAssertEqual(Blimp.TakeOff.Configuration(rawValue: "Enterprise")?.rawValue, "Enterprise")
    }

    // MARK: - Destination Tests

    func testDestinationRawValue() {
        XCTAssertEqual(Blimp.TakeOff.Destination.anyIOSDevice.rawValue, "anyIOSDevice")
    }

    // MARK: - Full Archive Command Construction

    func testFullArchiveCommandConstruction() {
        let args: [Blimp.TakeOff.ArchiveArgument] = [
            .clean,
            .workspacePath("/path/to/App.xcworkspace"),
            .scheme("MyApp"),
            .configuration(.release),
            .destination(.anyIOSDevice),
            .archivePath("/path/to/build/App.xcarchive")
        ]

        let bashArgs = args.map { $0.bashArgument }

        XCTAssertEqual(bashArgs.count, 6)
        XCTAssertTrue(bashArgs.contains("clean"))
        XCTAssertTrue(bashArgs.contains("-workspace /path/to/App.xcworkspace"))
        XCTAssertTrue(bashArgs.contains("-scheme MyApp"))
        XCTAssertTrue(bashArgs.contains("-configuration Release"))
        XCTAssertTrue(bashArgs.contains("-destination generic/platform=iOS"))
        XCTAssertTrue(bashArgs.contains("-archivePath /path/to/build/App.xcarchive"))
    }
}
