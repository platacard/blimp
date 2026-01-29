import ArgumentParser
import BlimpKit
import Cronista

struct SetRemote: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set-remote",
        abstract: "Set or update the remote URL for local storage"
    )

    @Option(help: "Local path of the storage")
    var path: String

    @Option(help: "Git URL to set as remote")
    var gitUrl: String

    func run() async throws {
        let logger = Cronista(module: "blimp", category: "Maintenance")
        try await Blimp.Maintenance.default.setStorageRemote(path: path, remoteURL: gitUrl)
        logger.success("Remote set to: \(gitUrl)")
        logger.info("To push: blimp maintenance push --path \(path)")
    }
}
