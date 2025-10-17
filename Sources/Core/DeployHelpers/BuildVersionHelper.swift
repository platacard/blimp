import Foundation
import Corredor
import Cronista

public struct BuildVersionHelper {
    private static var logger: Cronista { Cronista(module: "blimp", category: "BuildVersionHelper") }

    public static func set(buildNumber: String, projectPath: String?) throws {
        let folder = projectPath != nil ? URL(fileURLWithPath: projectPath!).deletingLastPathComponent().path : "."
        let commandPrefix = "cd \(URL(fileURLWithPath: folder).standardizedFileURL.path) &&"
        let commandSuffix = "&& cd -"
        
        let command = "\(commandPrefix) agvtool new-version -all \(buildNumber) \(commandSuffix)"
        let output = try Shell.command(command, options: [.printOutput]).run()

        if output.contains("$(SRCROOT)") {
            logger.error("Cannot set build number with plist path containing $(SRCROOT)")
            logger.error("Please remove $(SRCROOT) in your Xcode target build settings")
        }
    }
}
