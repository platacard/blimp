import XCTest
import TestflightAPI
import Uploader
@testable import BlimpKit

final class ApproachStageTests: XCTestCase {

    // MARK: - start() Tests

    func testStartSuccessfulUpload() async throws {
        let mockUploader = MockUploader()
        let mockBuildQuery = MockBuildQueryService()
        let mockAppQuery = MockAppQueryService()

        let approach = Blimp.Approach(
            uploader: mockUploader,
            buildQueryService: mockBuildQuery,
            appQueryService: mockAppQuery
        )

        let config = UploadConfig(
            bundleId: "com.example.app",
            appVersion: "1.0",
            buildNumber: "1",
            filePath: "/path/to/app.ipa",
            platform: .iOS
        )

        try await approach.start(config: config, verbose: false)

        XCTAssertEqual(mockUploader.uploadCalls.count, 1)
    }

    func testStartWithIgnoreUploaderFailureTrue() async throws {
        let mockUploader = MockUploader()
        mockUploader.errorToThrow = TransporterError.toolError(NSError(domain: "test", code: 1))

        let mockBuildQuery = MockBuildQueryService()
        let mockAppQuery = MockAppQueryService()

        let approach = Blimp.Approach(
            uploader: mockUploader,
            buildQueryService: mockBuildQuery,
            appQueryService: mockAppQuery,
            ignoreUploaderFailure: true
        )

        let config = UploadConfig(
            bundleId: "com.example.app",
            appVersion: "1.0",
            buildNumber: "1",
            filePath: "/path/to/app.ipa",
            platform: .iOS
        )

        // Should not throw when ignoreUploaderFailure is true
        try await approach.start(config: config, verbose: false)
    }

    func testStartPropagatesErrorWhenIgnoreUploaderFailureFalse() async throws {
        let mockUploader = MockUploader()
        let expectedError = NSError(domain: "test", code: 42)
        mockUploader.errorToThrow = TransporterError.toolError(expectedError)

        let mockBuildQuery = MockBuildQueryService()
        let mockAppQuery = MockAppQueryService()

        let approach = Blimp.Approach(
            uploader: mockUploader,
            buildQueryService: mockBuildQuery,
            appQueryService: mockAppQuery,
            ignoreUploaderFailure: false
        )

        let config = UploadConfig(
            bundleId: "com.example.app",
            appVersion: "1.0",
            buildNumber: "1",
            filePath: "/path/to/app.ipa",
            platform: .iOS
        )

        do {
            try await approach.start(config: config, verbose: false)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertEqual((error as NSError).code, 42)
        }
    }

    // MARK: - getBundleBuildSizes Tests

    func testGetBundleBuildSizesWithKnownDevice() async throws {
        let mockUploader = MockUploader()
        let mockBuildQuery = MockBuildQueryService()
        mockBuildQuery.bundleSizes = [
            BundleBuildFileSize(deviceModel: "iPhone16,2", downloadBytes: 50_000_000, instalBytes: 100_000_000)
        ]
        let mockAppQuery = MockAppQueryService()

        let approach = Blimp.Approach(
            uploader: mockUploader,
            buildQueryService: mockBuildQuery,
            appQueryService: mockAppQuery
        )

        let sizes = try await approach.mass(of: "bundle-123", devices: ["iPhone16,2"])

        XCTAssertEqual(sizes.count, 1)
        XCTAssertEqual(sizes.first?.deviceName, "iPhone 15 Pro Max")
        XCTAssertEqual(sizes.first?.downloadSize, 50_000_000)
        XCTAssertEqual(sizes.first?.installSize, 100_000_000)
    }

    func testGetBundleBuildSizesWithUnknownDevice() async throws {
        let mockUploader = MockUploader()
        let mockBuildQuery = MockBuildQueryService()
        mockBuildQuery.bundleSizes = [
            BundleBuildFileSize(deviceModel: "iPhone99,1", downloadBytes: 50_000_000, instalBytes: 100_000_000)
        ]
        let mockAppQuery = MockAppQueryService()

        let approach = Blimp.Approach(
            uploader: mockUploader,
            buildQueryService: mockBuildQuery,
            appQueryService: mockAppQuery
        )

        let sizes = try await approach.mass(of: "bundle-123", devices: ["iPhone99,1"])

        XCTAssertEqual(sizes.count, 1)
        // Unknown device should return raw model string
        XCTAssertEqual(sizes.first?.deviceName, "iPhone99,1")
    }

    func testGetBundleBuildSizesThrowsOnFailure() async throws {
        let mockUploader = MockUploader()
        let mockBuildQuery = MockBuildQueryService()
        mockBuildQuery.errorToThrow = NSError(domain: "API", code: 500)
        let mockAppQuery = MockAppQueryService()

        let approach = Blimp.Approach(
            uploader: mockUploader,
            buildQueryService: mockBuildQuery,
            appQueryService: mockAppQuery
        )

        do {
            _ = try await approach.mass(of: "bundle-123", devices: ["iPhone16,2"])
            XCTFail("Expected error to be thrown")
        } catch let error as Blimp.Approach.Error {
            XCTAssertEqual(error, .failedToGetAppSizes)
        }
    }

    // MARK: - process() State Transition Tests

    func testProcessBuildTransitionsToValid() async throws {
        let mockUploader = MockUploader()
        let mockBuildQuery = MockBuildQueryService()
        mockBuildQuery.buildIdResponses = ["build-123"]
        mockBuildQuery.processingResults = [
            TestflightAPI.BuildProcessingResult(
                processingState: .valid,
                buildBundleID: "bundle-456",
                buildLocalizationIDs: ["loc-1", "loc-2"]
            )
        ]
        let mockAppQuery = MockAppQueryService()
        mockAppQuery.appIds = ["com.example.app": "app-789"]

        let approach = Blimp.Approach(
            uploader: mockUploader,
            buildQueryService: mockBuildQuery,
            appQueryService: mockAppQuery
        )

        let result = try await approach.hold(bundleId: "com.example.app", appVersion: "1.0", buildNumber: "1")

        XCTAssertEqual(result.buildId, "build-123")
        XCTAssertEqual(result.buildBundleId, "bundle-456")
        XCTAssertEqual(result.buildLocalizationIds, ["loc-1", "loc-2"])
    }

    func testProcessBuildTransitionsToFailed() async throws {
        let mockUploader = MockUploader()
        let mockBuildQuery = MockBuildQueryService()
        mockBuildQuery.buildIdResponses = ["build-123"]
        mockBuildQuery.processingResults = [
            TestflightAPI.BuildProcessingResult(
                processingState: .failed,
                buildBundleID: "bundle-456",
                buildLocalizationIDs: []
            )
        ]
        let mockAppQuery = MockAppQueryService()
        mockAppQuery.appIds = ["com.example.app": "app-789"]

        let approach = Blimp.Approach(
            uploader: mockUploader,
            buildQueryService: mockBuildQuery,
            appQueryService: mockAppQuery
        )

        do {
            _ = try await approach.hold(bundleId: "com.example.app", appVersion: "1.0", buildNumber: "1")
            XCTFail("Expected failedProcessing error")
        } catch let error as Blimp.Approach.Error {
            XCTAssertEqual(error, .failedProcessing)
        }
    }

    func testProcessBuildTransitionsToInvalid() async throws {
        let mockUploader = MockUploader()
        let mockBuildQuery = MockBuildQueryService()
        mockBuildQuery.buildIdResponses = ["build-123"]
        mockBuildQuery.processingResults = [
            TestflightAPI.BuildProcessingResult(
                processingState: .invalid,
                buildBundleID: "bundle-456",
                buildLocalizationIDs: []
            )
        ]
        let mockAppQuery = MockAppQueryService()
        mockAppQuery.appIds = ["com.example.app": "app-789"]

        let approach = Blimp.Approach(
            uploader: mockUploader,
            buildQueryService: mockBuildQuery,
            appQueryService: mockAppQuery
        )

        do {
            _ = try await approach.hold(bundleId: "com.example.app", appVersion: "1.0", buildNumber: "1")
            XCTFail("Expected invalidBinary error")
        } catch let error as Blimp.Approach.Error {
            XCTAssertEqual(error, .invalidBinary)
        }
    }
}

// MARK: - Error Equatable

extension Blimp.Approach.Error: Equatable {
    public static func == (lhs: Blimp.Approach.Error, rhs: Blimp.Approach.Error) -> Bool {
        switch (lhs, rhs) {
        case (.noBuildId, .noBuildId): return true
        case (.failedProcessing, .failedProcessing): return true
        case (.invalidBinary, .invalidBinary): return true
        case (.failedToGetAppSizes, .failedToGetAppSizes): return true
        default: return false
        }
    }
}
