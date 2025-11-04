import Foundation
import BlimpKit
import ArgumentParser
import Cronista
import Uploader

struct Approach: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "approach",
        abstract: "Uploads exported app to TestFlight / App Store connect"
    )
    
    @Option(help: "App's bundle identifier")
    var bundleId: String
    
    @Option(help: "Path to the ipa file. Either relative to current dir or absolute")
    var ipaPath: String
    
    @Option(help: "Current or next version in the Testflight")
    var appVersion: String
    
    @Option(help: "Next build number in TestFlight")
    var buildNumber: String
    
    @Option(help: "platform to upload to. Possible values are: `ios`, `macos`")
    var platform: Platform = .iOS

    @Flag(inversion: .prefixedNo, help: "Sometimes upload is more stable with speed limit, same technique used by fastlane.")
    var limitMaxUploadSpeed: Bool = true

    @Flag(help: "Ignore uploader failure, use only as last resort.")
    var ignoreUploaderFailure: Bool = false

    @Flag(help: "Produce more output")
    var verbose = false

    @Flag(help: "Use legacy altool uploader instead of App Store Connect API. Deprecated, requires additional setup")
    var legacyUploader = false
    
    private var logger: Cronista { Cronista(module: "blimp", category: "Approach") }
    
    func run() async throws {
        let uploader: AppStoreConnectUploader

        if legacyUploader {
            uploader = AltoolUploaderAdapter()
        } else {
            uploader = AppStoreConnectAPIUploader()
        }

        let approach = Blimp.Approach(
            uploader: uploader,
            ignoreUploaderFailure: ignoreUploaderFailure
        )

        try await run(approach: approach)
    }
}

// MARK: - Transporter wrappers

extension Approach {
    
    func run(approach: Blimp.Approach) async throws {
        logger.info("Starting upload of \(bundleId)...")
        
        let config = UploadConfig(
            bundleId: bundleId,
            appVersion: appVersion,
            buildNumber: buildNumber,
            filePath: ipaPath,
            platform: platform
        )

        try await approach.start(config: config, verbose: verbose)

        logger.info("Starting processing of \(bundleId)...")
        let processingResult = try await approach.hold(bundleId: bundleId, appVersion: appVersion, buildNumber: buildNumber)
        
        logger.info("Build with id: \(processingResult.buildId) has been successfully processed!")
        
        setEnvironment(processingResult.buildId)
        logger.info("Done!")
    }
    
    func setEnvironment(_ buildId: String) {
        ProcessInfo.processInfo.setValue(buildId, forKey: "BUILD_ID")
    }
}

// MARK: - Argument parser adapters

extension Platform: ExpressibleByArgument {
    public init?(argument: String) {
        switch argument {
        case "ios", "iOS":
            self = .iOS
        case "macos", "macOS":
            self = .macOS
        case "tvOS", "tvos":
            self = .tvOS
        case "visionOS", "visionos":
            self = .visionOS
        default:
            fatalError("Unsupported platform: \(argument). Supported platforms: ios, macos, tvos, visionos")
        }
    }
}
