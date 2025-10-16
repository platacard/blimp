import Foundation
import BlimpKit
import ArgumentParser
import Cronista

struct Land: AsyncParsableCommand {
    
    static let configuration = CommandConfiguration(
        commandName: "land",
        abstract: "Finishes the distribution by setting beta groups. Also sends the build to the external review"
    )
    
    @Option(help: "App's bundle identifier")
    var bundleId: String
    @Option(help: "Processed build identifier from the `approach` step")
    var buildId: String
    @Option(parsing: .remaining)
    var betaGroups: [String]
    
    @Flag(help: "Produce more output")
    var verbose = false
    
    private var logger: Cronista { Cronista(module: "Blimp", category: "Land") }
    
    func run() async throws {
        let land = Blimp.Land()
        
        logger.info("Setting beta groups...")
        try await land.engage(bundleId: bundleId, buildId: buildId, betaGroups: betaGroups)
        logger.info("Sending to a testflight review...")
        try await land.confirm(buildId: buildId)
        logger.info("Done! Build for \(bundleId) with id: \(buildId) has been successfully sent to Testflight review")
    }
}
