import XCTest
@testable import Uploader
import Foundation
import JWTProvider

final class UploaderTests: XCTestCase {
    
    // MARK: - UploadConfig Tests
    
    func testUploadConfigInitialization() {
        // Given
        let bundleId = "com.example.app"
        let appVersion = "1.0.0"
        let buildNumber = "123"
        let filePath = "/path/to/app.ipa"
        let platform = Platform.iOS
        
        // When
        let config = UploadConfig(
            bundleId: bundleId,
            appVersion: appVersion,
            buildNumber: buildNumber,
            filePath: filePath,
            platform: platform
        )
        
        // Then
        XCTAssertEqual(config.bundleId, bundleId)
        XCTAssertEqual(config.appVersion, appVersion)
        XCTAssertEqual(config.buildNumber, buildNumber)
        XCTAssertEqual(config.filePath, filePath)
        XCTAssertEqual(config.platform, platform)
    }
    
    func testUploadConfigWithAllPlatforms() {
        // Given/When/Then
        let iosConfig = UploadConfig(
            bundleId: "com.test.ios",
            appVersion: "1.0",
            buildNumber: "1",
            filePath: "/path.ipa",
            platform: .iOS
        )
        XCTAssertEqual(iosConfig.platform, .iOS)
        
        let macosConfig = UploadConfig(
            bundleId: "com.test.macos",
            appVersion: "1.0",
            buildNumber: "1",
            filePath: "/path.ipa",
            platform: .macOS
        )
        XCTAssertEqual(macosConfig.platform, .macOS)
        
        let visionosConfig = UploadConfig(
            bundleId: "com.test.visionos",
            appVersion: "1.0",
            buildNumber: "1",
            filePath: "/path.ipa",
            platform: .visionOS
        )
        XCTAssertEqual(visionosConfig.platform, .visionOS)
        
        let tvosConfig = UploadConfig(
            bundleId: "com.test.tvos",
            appVersion: "1.0",
            buildNumber: "1",
            filePath: "/path.ipa",
            platform: .tvOS
        )
        XCTAssertEqual(tvosConfig.platform, .tvOS)
    }
    
    // MARK: - Platform Tests
    
    func testPlatformRawValues() {
        // Given/When/Then
        XCTAssertEqual(Platform.iOS.rawValue, "ios")
        XCTAssertEqual(Platform.macOS.rawValue, "macos")
        XCTAssertEqual(Platform.visionOS.rawValue, "visionos")
        XCTAssertEqual(Platform.tvOS.rawValue, "tvos")
    }
    
    func testPlatformInitFromRawValue() {
        // Given/When/Then
        XCTAssertEqual(Platform(rawValue: "ios"), .iOS)
        XCTAssertEqual(Platform(rawValue: "macos"), .macOS)
        XCTAssertEqual(Platform(rawValue: "visionos"), .visionOS)
        XCTAssertEqual(Platform(rawValue: "tvos"), .tvOS)
        XCTAssertNil(Platform(rawValue: "invalid"))
    }
    
    // MARK: - TransporterError Tests
    
    func testTransporterErrorAuthRequiredDescription() {
        // Given
        let error = TransporterError.authRequired
        
        // When
        let description = error.description
        
        // Then
        XCTAssertEqual(description, "Auth failed")
    }
    
    func testTransporterErrorToolErrorDescription() {
        // Given
        let underlyingError = NSError(domain: "TestDomain", code: 123, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        let error = TransporterError.toolError(underlyingError)
        
        // When
        let description = error.description
        
        // Then
        XCTAssertTrue(description.contains("Internal tool error"))
        XCTAssertTrue(description.contains("Test error"))
    }
    
    // MARK: - AppStoreConnectAPIUploader Tests
    
    func testAppStoreConnectAPIUploaderInitialization() {
        // Given/When
        let uploader = AppStoreConnectAPIUploader()
        
        // Then
        XCTAssertNotNil(uploader)
    }
    
    func testAppStoreConnectAPIUploaderWithCustomParameters() {
        // Given
        let jwtProvider = DefaultJWTProvider()
        let urlSession = URLSession.shared
        let maxRetries = 5
        let pollInterval: TimeInterval = 60
        
        // When
        let uploader = AppStoreConnectAPIUploader(
            jwtProvider: jwtProvider,
            urlSession: urlSession,
            maxUploadRetries: maxRetries,
            uploadStatusPollInterval: pollInterval,
            uploadStatusMaxAttempts: 120,
            pollInterval: 45
        )
        
        // Then
        XCTAssertNotNil(uploader)
    }
    
    func testAppStoreConnectAPIUploaderMinRetries() {
        // Given/When
        // Setting maxUploadRetries to 0 should be clamped to 1
        let uploader = AppStoreConnectAPIUploader(maxUploadRetries: 0)
        
        // Then
        XCTAssertNotNil(uploader)
    }
    
    // MARK: - AltoolUploader Tests
    
    func testAltoolUploaderInitialization() {
        // Given/When
        let uploader = AltoolUploader()
        
        // Then
        XCTAssertNotNil(uploader)
    }
    
    func testAltoolUploaderAdapterInitialization() {
        // Given
        let altoolUploader = AltoolUploader()
        
        // When
        let adapter = AltoolUploaderAdapter(altoolUploader: altoolUploader)
        
        // Then
        XCTAssertNotNil(adapter)
    }
    
    func testAltoolUploaderAdapterWithDefaultInit() {
        // Given/When
        let adapter = AltoolUploaderAdapter()
        
        // Then
        XCTAssertNotNil(adapter)
    }
    
    // MARK: - AltoolUploader TransporterSetting Tests
    
    func testAltoolUploaderTransporterSettings() {
        // Given/When/Then
        let upload = AltoolUploader.TransporterSetting.upload
        XCTAssertEqual(upload.bashArgument, "--upload-app")
        
        let file = AltoolUploader.TransporterSetting.file("/path/to/file.ipa")
        XCTAssertEqual(file.bashArgument, "-f /path/to/file.ipa")
        
        let appVersion = AltoolUploader.TransporterSetting.appVersion("1.0.0")
        XCTAssertEqual(appVersion.bashArgument, "--bundle-short-version-string 1.0.0")
        
        let buildNumber = AltoolUploader.TransporterSetting.buildNumber("123")
        XCTAssertEqual(buildNumber.bashArgument, "--bundle-version 123")
        
        let platform = AltoolUploader.TransporterSetting.platform(.iOS)
        XCTAssertEqual(platform.bashArgument, "-t ios")
        
        let maxUploadSpeed = AltoolUploader.TransporterSetting.maxUploadSpeed
        XCTAssertEqual(maxUploadSpeed.bashArgument, "-k 100000")
        
        let showProgress = AltoolUploader.TransporterSetting.showProgress
        XCTAssertEqual(showProgress.bashArgument, "--show-progress")
        
        let oldAltool = AltoolUploader.TransporterSetting.oldAltool
        XCTAssertEqual(oldAltool.bashArgument, "--use-old-altool")
        
        let verbose = AltoolUploader.TransporterSetting.verbose
        XCTAssertEqual(verbose.bashArgument, "--verbose")
    }
    
    // MARK: - AltoolUploader AuthOption Tests
    
    func testAltoolUploaderAuthOptions() {
        // Given/When/Then
        let apiKey = AltoolUploader.AuthOption.apiKey("TEST_KEY")
        XCTAssertEqual(apiKey.bashArgument, "--apiKey TEST_KEY")
        
        let apiIssuer = AltoolUploader.AuthOption.apiIssuer("TEST_ISSUER")
        XCTAssertEqual(apiIssuer.bashArgument, "--apiIssuer \"TEST_ISSUER\"")
        
        let apiPrivateKey = AltoolUploader.AuthOption.apiPrivateKey("TEST_PRIVATE_KEY")
        XCTAssertEqual(apiPrivateKey.bashArgument, "--auth-string \"TEST_PRIVATE_KEY\"")
    }
}
