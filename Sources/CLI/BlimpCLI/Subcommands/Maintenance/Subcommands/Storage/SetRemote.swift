import ArgumentParser
import BlimpKit

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
        try await Blimp.Maintenance.default.setStorageRemote(path: path, remoteURL: gitUrl)
        print("Remote set to: \(gitUrl)")
        print("To push: blimp maintenance push --path \(path)")
    }
}
