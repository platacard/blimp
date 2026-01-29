import ArgumentParser
import BlimpKit
import Foundation

struct Init: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Initialize the storage repository"
    )

    @Option(help: "Storage path (defaults to current directory)")
    var storagePath: String = "."

    @Option(help: "Git branch")
    var gitBranch: String = "main"

    func run() async throws {
        let resolvedPath = storagePath == "." ? FileManager.default.currentDirectoryPath : storagePath
        try await Blimp.Maintenance.default.initializeLocalStorage(path: resolvedPath, branch: gitBranch)
        print("Storage initialized at: \(resolvedPath)")
    }
}
