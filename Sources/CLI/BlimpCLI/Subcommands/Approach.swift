import Foundation
import BlimpKit
import ArgumentParser
import Cronista
import Transporter

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
    var platform: Blimp.Approach.Platform = .iOS
    
    @Flag(inversion: .prefixedNo, help: "Validate the build before uploading")
    var validate: Bool = false

    @Flag(inversion: .prefixedNo, help: "Sometimes upload is more stable with speed limit, same technique used by fastlane.")
    var limitMaxUploadSpeed: Bool = true

    @Flag(help: "Ignore uploader failure, use only as last resort.")
    var ignoreUploaderFailure: Bool = false

    @Flag(help: "Produce more output")
    var verbose = false
    
    private var logger: Cronista { Cronista(module: "blimp", category: "Approach") }
    
    func run() async throws {
        let altool = AltoolTransporter()
        let approach = Blimp.Approach(transporter: altool)

        if validate {
           try await run(approach: approach, mode: .validate)
        }
        
        try await run(approach: approach, mode: .upload)
    }
}

// MARK: - Transporter wrappers

extension Approach {
    
    enum TransporterMode {
        case validate
        case upload
    }
    
    func run(approach: Blimp.Approach, mode: TransporterMode) async throws {
        let message: String
        var arguments: [Blimp.Approach.Setting] = [
            .appVersion(appVersion),
            .buildNumber(buildNumber),
            .file(ipaPath),
            .platform(platform),
            .showProgress
        ] + (limitMaxUploadSpeed ? [.maxUploadSpeed] : [])

        switch mode {
        case .validate:
            message = "Validating \(ipaPath)..."
            arguments.insert(.validate, at: 0)
        case .upload:
            message = "Uploading \(ipaPath)..."
            arguments.insert(.upload, at: 0)
        }
        
        logger.info(message)
        
        logger.info("Starting upload of \(bundleId)...")
        try approach.start(bundleId: bundleId, arguments: arguments, verbose: verbose)
        
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

extension Blimp.Approach.Platform: ExpressibleByArgument {
    public init?(argument: String) {
        switch argument {
        case "ios", "iOS":
            self = .iOS
        case "macos", "macOS":
            self = .macOS
        default:
            fatalError("unsupported platform in \(Self.self)")
        }
    }
}
