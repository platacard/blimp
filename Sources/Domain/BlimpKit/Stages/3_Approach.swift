import Foundation
import Cronista
import Uploader
import JWTProvider
import AppsAPI
import TestflightAPI

public extension Blimp {
    /// Approach stage:
    /// - TestFlight / App Store delivery operations
    struct Approach: FlightStage, Sendable {
        package var type: FlightStage.Type { Self.self }
        private let uploader: AppStoreConnectUploader
        private let buildQueryService: BuildQueryService
        private let appQueryService: AppQueryService
        private let ignoreUploaderFailure: Bool

        nonisolated(unsafe) private let logger: Cronista

        /// Initialize with protocol dependencies for testability
        public init(
            uploader: AppStoreConnectUploader,
            buildQueryService: BuildQueryService,
            appQueryService: AppQueryService,
            ignoreUploaderFailure: Bool = false
        ) {
            self.logger = Cronista(module: "blimp", category: "Approach")
            self.uploader = uploader
            self.buildQueryService = buildQueryService
            self.appQueryService = appQueryService
            self.ignoreUploaderFailure = ignoreUploaderFailure
        }

        /// Convenience initializer for production use
        public init(
            uploader: AppStoreConnectUploader,
            jwtProvider: JWTProviding = DefaultJWTProvider(),
            ignoreUploaderFailure: Bool = false
        ) {
            self.init(
                uploader: uploader,
                buildQueryService: TestflightAPI(jwtProvider: jwtProvider),
                appQueryService: AppsAPI(jwtProvider: jwtProvider),
                ignoreUploaderFailure: ignoreUploaderFailure
            )
        }
    }
}

public extension Blimp.Approach {
    /// Upload the build with App Store Connect API
    func start(config: UploadConfig, verbose: Bool) async throws {
        do {
            try await uploader.upload(config: config, verbose: verbose)
        } catch let TransporterError.toolError(error) {
            logger.warning("Transporter error: [\(error.localizedDescription)]!")
            if ignoreUploaderFailure { return }

            throw error
        } catch {
            logger.warning("Some transporter error: [\(error.localizedDescription)]!")

            throw error
        }
    }

    /// Wait for build processing
    /// - Parameter bundleId: bundle id of the app to process
    /// - Returns: processing result meta info
    func hold(bundleId: String, appVersion: String, buildNumber: String) async throws -> ProcessResult {
        try await process(bundleId: bundleId, appVersion: appVersion, buildNumber: buildNumber)
    }
    
    /// Get build app sizes
    /// - Parameters:
    ///   - buildBundleId: resource id from the `ProcessResult` response
    ///   - devices: sizes only for devices listed in this array
    /// - Returns: array of app sizes
    func mass(of buildBundleId: String, devices: [String]) async throws -> [AppSize] {
        try await getBundleBuildSizes(buildBundleId: buildBundleId, devices: devices)
    }
}

// MARK: - Build processing

extension Blimp.Approach {
    
    func process(bundleId: String, appVersion: String, buildNumber: String) async throws -> ProcessResult {
        var didAppearInList = false
        var isProcessed = false

        let appId = try await appQueryService.getAppId(bundleId: bundleId)
        logger.info("App id for \(bundleId): \(appId)")

        var matchedBuildId: String?
        var buildBundleId: String?
        var buildLocalizationIds: [String] = []

        while !didAppearInList {
            let buildId = try await buildQueryService.getBuildID(
                appId: appId,
                appVersion: appVersion,
                buildNumber: buildNumber
            )

            if let buildId {
                didAppearInList = true
                matchedBuildId = buildId
            } else {
                logger.info("Waiting for the build to appear in the App Store Connect...")
                try await Task.sleep(for: .seconds(30))
            }
        }

        while !isProcessed {
            guard let matchedBuildId else { throw Error.noBuildId }

            let processingResult = try await buildQueryService.getBuildProcessingResult(id: matchedBuildId)

            switch processingResult.processingState {
            case .processing:
                logger.info("Waiting for the build to finish processing...")
                try await Task.sleep(for: .seconds(30))
            case .failed:
                logger.error("Processing failed, something odd happened, who knows")
                throw Error.failedProcessing
            case .invalid:
                logger.error("Processing failed, invalid binary")
                throw Error.invalidBinary
            case .valid:
                logger.info("Build has been successfully processed! BuildId: \(matchedBuildId)")
                buildBundleId = processingResult.buildBundleID
                buildLocalizationIds = processingResult.buildLocalizationIDs
                isProcessed = true
            }
        }

        guard let matchedBuildId, let buildBundleId else { throw Error.failedProcessing }

        return .init(buildId: matchedBuildId, buildBundleId: buildBundleId, buildLocalizationIds: buildLocalizationIds)
    }
    
    func getBundleBuildSizes(buildBundleId: String, devices: [String]) async throws -> [AppSize] {
        guard
            let result = try? await buildQueryService.getBundleBuildSizes(buildBundleID: buildBundleId, devices: devices)
        else {
            logger.error("Could not get build sizes for buildBundleId: \(buildBundleId)")
            throw Error.failedToGetAppSizes
        }

        return result.compactMap { sizeInfo in
            let deviceName = Self.deviceModelToNameMappings[sizeInfo.deviceModel] ?? sizeInfo.deviceModel

            return .init(
                deviceName: deviceName,
                downloadSize: sizeInfo.downloadBytes,
                installSize: sizeInfo.instalBytes
            )
        }
    }
}

// MARK: - Subtypes

public extension Blimp.Approach {

    struct ProcessResult: Sendable {
        public let buildId: String
        public let buildBundleId: String
        public let buildLocalizationIds: [String]
    }

    struct AppSize: Sendable {
        public let deviceName: String
        public let downloadSize: Int
        public let installSize: Int
    }

    enum Error: Swift.Error, Sendable {
        case noBuildId
        case failedProcessing
        case invalidBinary
        case failedToGetAppSizes
    }
}

// MARK: - Device mappings

extension Blimp.Approach {
    
    // List of device models
    // https://gist.github.com/adamawolf/3048717#file-apple_mobile_device_types-txt
    static let deviceModelToNameMappings = [
        "iPhone1,1" : "iPhone",
        "iPhone1,2" : "iPhone 3G",
        "iPhone2,1" : "iPhone 3GS",
        "iPhone3,1" : "iPhone 4",
        "iPhone3,2" : "iPhone 4 GSM Rev A",
        "iPhone3,3" : "iPhone 4 CDMA",
        "iPhone4,1" : "iPhone 4S",
        "iPhone5,1" : "iPhone 5 (GSM)",
        "iPhone5,2" : "iPhone 5 (GSM+CDMA)",
        "iPhone5,3" : "iPhone 5C (GSM)",
        "iPhone5,4" : "iPhone 5C (Global)",
        "iPhone6,1" : "iPhone 5S (GSM)",
        "iPhone6,2" : "iPhone 5S (Global)",
        "iPhone7,1" : "iPhone 6 Plus",
        "iPhone7,2" : "iPhone 6",
        "iPhone8,1" : "iPhone 6s",
        "iPhone8,2" : "iPhone 6s Plus",
        "iPhone8,4" : "iPhone SE (GSM)",
        "iPhone9,1" : "iPhone 7",
        "iPhone9,2" : "iPhone 7 Plus",
        "iPhone9,3" : "iPhone 7",
        "iPhone9,4" : "iPhone 7 Plus",
        "iPhone10,1" : "iPhone 8",
        "iPhone10,2" : "iPhone 8 Plus",
        "iPhone10,3" : "iPhone X Global",
        "iPhone10,4" : "iPhone 8",
        "iPhone10,5" : "iPhone 8 Plus",
        "iPhone10,6" : "iPhone X GSM",
        "iPhone11,2" : "iPhone XS",
        "iPhone11,4" : "iPhone XS Max",
        "iPhone11,6" : "iPhone XS Max Global",
        "iPhone11,8" : "iPhone XR",
        "iPhone12,1" : "iPhone 11",
        "iPhone12,3" : "iPhone 11 Pro",
        "iPhone12,5" : "iPhone 11 Pro Max",
        "iPhone12,8" : "iPhone SE 2nd Gen",
        "iPhone13,1" : "iPhone 12 Mini",
        "iPhone13,2" : "iPhone 12",
        "iPhone13,3" : "iPhone 12 Pro",
        "iPhone13,4" : "iPhone 12 Pro Max",
        "iPhone14,2" : "iPhone 13 Pro",
        "iPhone14,3" : "iPhone 13 Pro Max",
        "iPhone14,4" : "iPhone 13 Mini",
        "iPhone14,5" : "iPhone 13",
        "iPhone14,6" : "iPhone SE 3rd Gen",
        "iPhone14,7" : "iPhone 14",
        "iPhone14,8" : "iPhone 14 Plus",
        "iPhone15,2" : "iPhone 14 Pro",
        "iPhone15,3" : "iPhone 14 Pro Max",
        "iPhone15,4" : "iPhone 15",
        "iPhone15,5" : "iPhone 15 Plus",
        "iPhone16,1" : "iPhone 15 Pro",
        "iPhone16,2" : "iPhone 15 Pro Max",
        "iPod1,1" : "1st Gen iPod",
        "iPod2,1" : "2nd Gen iPod",
        "iPod3,1" : "3rd Gen iPod",
        "iPod4,1" : "4th Gen iPod",
        "iPod5,1" : "5th Gen iPod",
        "iPod7,1" : "6th Gen iPod",
        "iPod9,1" : "7th Gen iPod",
    ]
}
