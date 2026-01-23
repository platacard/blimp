import XCTest
@testable import BlimpKit
import Foundation
import Uploader
import JWTProvider

final class BlimpTests: XCTestCase {
    
    // MARK: - Blimp Tests
    
    func testBlimpInitialization() {
        // Given/When
        let blimp = Blimp()
        
        // Then
        XCTAssertNotNil(blimp)
    }
    
    // MARK: - Maintenance Tests
    
    func testMaintenanceInitialization() {
        // Given/When
        let maintenance = Blimp.Maintenance()
        
        // Then
        XCTAssertNotNil(maintenance)
    }
    
    func testMaintenanceRun() throws {
        // Given
        let maintenance = Blimp.Maintenance()
        
        // When/Then
        // Note: run() is currently empty, but we verify it can be called
        XCTAssertNoThrow(try maintenance.run())
    }
    
    // MARK: - TakeOff Tests
    
    func testTakeOffInitialization() {
        // Given/When
        let takeOff = Blimp.TakeOff()
        
        // Then
        XCTAssertNotNil(takeOff)
        // Verify type is correct by checking the type property exists
        let _: FlightStage.Type = takeOff.type
    }
    
    func testTakeOffConfiguration() {
        // Given/When/Then
        XCTAssertEqual(Blimp.TakeOff.Configuration.debug.rawValue, "Debug")
        XCTAssertEqual(Blimp.TakeOff.Configuration.beta.rawValue, "Beta")
        XCTAssertEqual(Blimp.TakeOff.Configuration.release.rawValue, "Release")
        
        let custom = Blimp.TakeOff.Configuration.custom("Custom")
        XCTAssertEqual(custom.rawValue, "Custom")
    }
    
    func testTakeOffConfigurationFromRawValue() {
        // Given/When/Then
        let debugConfig = Blimp.TakeOff.Configuration(rawValue: "Debug")
        XCTAssertNotNil(debugConfig)
        XCTAssertEqual(debugConfig?.rawValue, "Debug")
        
        let debugLowercase = Blimp.TakeOff.Configuration(rawValue: "debug") // Case insensitive
        XCTAssertNotNil(debugLowercase)
        XCTAssertEqual(debugLowercase?.rawValue, "Debug")
        
        let betaConfig = Blimp.TakeOff.Configuration(rawValue: "Beta")
        XCTAssertNotNil(betaConfig)
        XCTAssertEqual(betaConfig?.rawValue, "Beta")
        
        let betaLowercase = Blimp.TakeOff.Configuration(rawValue: "beta")
        XCTAssertNotNil(betaLowercase)
        XCTAssertEqual(betaLowercase?.rawValue, "Beta")
        
        let releaseConfig = Blimp.TakeOff.Configuration(rawValue: "Release")
        XCTAssertNotNil(releaseConfig)
        XCTAssertEqual(releaseConfig?.rawValue, "Release")
        
        let releaseLowercase = Blimp.TakeOff.Configuration(rawValue: "release")
        XCTAssertNotNil(releaseLowercase)
        XCTAssertEqual(releaseLowercase?.rawValue, "Release")
        
        let custom = Blimp.TakeOff.Configuration(rawValue: "Custom")
        XCTAssertNotNil(custom)
        XCTAssertEqual(custom?.rawValue, "Custom")
    }
    
    func testTakeOffDestination() {
        // Given/When/Then
        XCTAssertEqual(Blimp.TakeOff.Destination.anyIOSDevice.rawValue, "anyIOSDevice")
    }
    
    func testTakeOffArchiveArguments() {
        let clean = Blimp.TakeOff.ArchiveArgument.clean
        XCTAssertEqual(clean.bashArgument, "clean")

        let workspacePath = Blimp.TakeOff.ArchiveArgument.workspacePath("/path/to/workspace.xcworkspace")
        XCTAssertEqual(workspacePath.bashArgument, "-workspace /path/to/workspace.xcworkspace")

        let projectPath = Blimp.TakeOff.ArchiveArgument.projectPath("/path/to/project.xcodeproj")
        XCTAssertEqual(projectPath.bashArgument, "-project /path/to/project.xcodeproj")

        let scheme = Blimp.TakeOff.ArchiveArgument.scheme("MyScheme")
        XCTAssertEqual(scheme.bashArgument, "-scheme MyScheme")

        let archivePath = Blimp.TakeOff.ArchiveArgument.archivePath("/path/to/archive.xcarchive")
        XCTAssertEqual(archivePath.bashArgument, "-archivePath /path/to/archive.xcarchive")

        let configuration = Blimp.TakeOff.ArchiveArgument.configuration(.release)
        XCTAssertEqual(configuration.bashArgument, "-configuration Release")

        let destination = Blimp.TakeOff.ArchiveArgument.destination(.anyIOSDevice)
        XCTAssertEqual(destination.bashArgument, "-destination generic/platform=iOS")

        let cleanOutput = Blimp.TakeOff.ArchiveArgument.cleanOutput
        XCTAssertEqual(cleanOutput.bashArgument, "| xcbeautify")
    }
    
    func testTakeOffExportArguments() {
        // Given/When/Then
        let exportArchive = Blimp.TakeOff.ExportArgument.exportArchive("/path/to/archive.xcarchive")
        XCTAssertEqual(exportArchive.bashArgument, "-exportArchive -archivePath /path/to/archive.xcarchive")
        
        let exportPath = Blimp.TakeOff.ExportArgument.exportPath("/path/to/export")
        XCTAssertEqual(exportPath.bashArgument, "-exportPath /path/to/export")
        
        let optionsPlistPath = Blimp.TakeOff.ExportArgument.optionsPlistPath("/path/to/options.plist")
        XCTAssertEqual(optionsPlistPath.bashArgument, "-exportOptionsPlist /path/to/options.plist")
    }
    
    // MARK: - Approach Tests
    
    func testApproachInitialization() {
        // Given
        let uploader = MockAppStoreConnectUploader()
        let jwtProvider = DefaultJWTProvider()
        
        // When
        let approach = Blimp.Approach(
            uploader: uploader,
            jwtProvider: jwtProvider,
            ignoreUploaderFailure: false
        )
        
        // Then
        XCTAssertNotNil(approach)
        // Verify type is correct by checking the type property exists
        let _: FlightStage.Type = approach.type
    }
    
    func testApproachInitializationWithDefaults() {
        // Given
        let uploader = MockAppStoreConnectUploader()
        
        // When
        let approach = Blimp.Approach(uploader: uploader)
        
        // Then
        XCTAssertNotNil(approach)
    }
    
    func testApproachProcessResult() {
        // Given
        let buildId = "build-123"
        let buildBundleId = "bundle-456"
        let buildLocalizationIds = ["loc-1", "loc-2"]
        
        // When
        let result = Blimp.Approach.ProcessResult(
            buildId: buildId,
            buildBundleId: buildBundleId,
            buildLocalizationIds: buildLocalizationIds
        )
        
        // Then
        XCTAssertEqual(result.buildId, buildId)
        XCTAssertEqual(result.buildBundleId, buildBundleId)
        XCTAssertEqual(result.buildLocalizationIds, buildLocalizationIds)
    }
    
    func testApproachAppSize() {
        // Given
        let deviceName = "iPhone 15 Pro"
        let downloadSize = 1024 * 1024 * 50 // 50 MB
        let installSize = 1024 * 1024 * 100 // 100 MB
        
        // When
        let appSize = Blimp.Approach.AppSize(
            deviceName: deviceName,
            downloadSize: downloadSize,
            installSize: installSize
        )
        
        // Then
        XCTAssertEqual(appSize.deviceName, deviceName)
        XCTAssertEqual(appSize.downloadSize, downloadSize)
        XCTAssertEqual(appSize.installSize, installSize)
    }
    
    func testApproachErrorCases() {
        // Given/When/Then
        // Verify error enum cases exist
        let error1 = Blimp.Approach.Error.noBuildId
        let error2 = Blimp.Approach.Error.failedProcessing
        let error3 = Blimp.Approach.Error.invalidBinary
        let error4 = Blimp.Approach.Error.failedToGetAppSizes
        
        XCTAssertNotNil(error1)
        XCTAssertNotNil(error2)
        XCTAssertNotNil(error3)
        XCTAssertNotNil(error4)
    }
    
    func testApproachDeviceModelMappings() {
        // Given/When/Then
        // Verify some device mappings exist
        XCTAssertEqual(Blimp.Approach.deviceModelToNameMappings["iPhone15,2"], "iPhone 14 Pro")
        XCTAssertEqual(Blimp.Approach.deviceModelToNameMappings["iPhone16,1"], "iPhone 15 Pro")
        XCTAssertEqual(Blimp.Approach.deviceModelToNameMappings["iPhone14,5"], "iPhone 13")
        XCTAssertEqual(Blimp.Approach.deviceModelToNameMappings["iPhone12,8"], "iPhone SE 2nd Gen")
    }
    
    func testApproachDeviceModelMappingsForUnknownDevice() {
        // Given
        let unknownModel = "UnknownDevice,1"
        
        // When
        let mapping = Blimp.Approach.deviceModelToNameMappings[unknownModel]
        
        // Then
        XCTAssertNil(mapping, "Unknown device model should not have a mapping")
    }
    
    // MARK: - Land Tests
    
    func testLandInitialization() {
        // Given
        let jwtProvider = DefaultJWTProvider()
        
        // When
        let land = Blimp.Land(jwtProvider: jwtProvider)
        
        // Then
        XCTAssertNotNil(land)
        // Verify type is correct by checking the type property exists
        let _: FlightStage.Type = land.type
    }
    
    func testLandInitializationWithDefaults() {
        // Given/When
        let land = Blimp.Land()
        
        // Then
        XCTAssertNotNil(land)
    }
}

// MARK: - Mock Helpers

private struct MockAppStoreConnectUploader: AppStoreConnectUploader {
    func upload(config: UploadConfig, verbose: Bool) async throws {
        // Mock implementation - does nothing
    }
}
