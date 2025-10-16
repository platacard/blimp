import Foundation
import BlimpKit
import ArgumentParser
import Cronista
import DeployHelpers

struct TakeOff: AsyncParsableCommand {
    
    static let configuration = CommandConfiguration(
        commandName: "takeoff",
        abstract: "Archives the app for subsequent distribution"
    )
    
    @Option(help: "Scheme name to archive/export")
    var scheme: String
    
    @Option(help: "Workspace file path. Either relative to current dir or absolute")
    var workspace: String
    
    @Option(help: "Export configuration options plist path. See all values via `xcodebuild -help` under '-exportOptionsPlist' entry")
    var deployConfig: String
    
    @Option(help: "Path to save the *.xcarchive")
    var archivePath: String = "build/Archives/app.xcarchive"
    
    @Option(help: "Path to export the ipa file to")
    var ipaPath: String = "build"
    
    @Flag(help: "Produce more output")
    var verbose = false
    
    private var logger: Cronista { Cronista(module: "Blimp", category: "TakeOff") }
    private var plistHelper: PlistHelper { .default }
    
    func run() async throws {
        let takeoff = Blimp.TakeOff()
        guard 
            let rawConfiguration = plistHelper.getStringValue(key: "configuration", path: deployConfig),
            let configuration = Blimp.TakeOff.Configuration(rawValue: rawConfiguration)
        else {
            return logger.error("Can't parse the configuration variable from \(deployConfig)")
        }
        
        logger.info("Archiving the \(scheme)...")
        try takeoff.archive(
            arguments: [
                .clean,
                .workspacePath(workspace),
                .scheme(scheme),
                .archivePath(archivePath),
                .configuration(configuration),
                .destination(.anyIOSDevice),
                .cleanOutput
            ],
            verbose: verbose
        )
        logger.info("Done!")
        
        logger.info("Exporting the archive at \(archivePath)...")
        try takeoff.export(
            arguments: [
                .exportArchive(archivePath),
                .exportPath(ipaPath),
                .optionsPlistPath(deployConfig)
            ],
            verbose: verbose
        )
        logger.info("Done! Exported IPA is at \(ipaPath)/\(scheme).ipa")
    }
}
