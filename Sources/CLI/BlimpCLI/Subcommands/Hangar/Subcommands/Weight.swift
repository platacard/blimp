import ArgumentParser
import Cronista
import TestflightAPI
import JWTProvider
import Foundation

struct Weight: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "weight",
        abstract: "App size for TestFlight builds"
    )

    @Option(help: "App id")
    var id: String

    @Option
    var devices: [String]

    func run() async throws {
        let logger = Cronista(module: "blimp", category: "Weight")
        let provider = DefaultJWTProvider()
        let api = TestflightAPI(jwtProvider: provider)

        let bundleIDs = try await api.getBuildBundleIDs(appId: id, state: .approved)

        for bundleID in bundleIDs {
            let buildSizes = try await api.getBundleBuildSizes(
                buildBundleID: bundleID,
                devices: devices
            )
            for buildSize in buildSizes {
                logger.info("\(buildSize)")
            }
        }
    }
}
