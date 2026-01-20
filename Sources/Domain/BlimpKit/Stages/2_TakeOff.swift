import Foundation
import Corredor

public extension Blimp {
    /// Take off stage:
    /// - Archiving the app and exporting the .ipa
    struct TakeOff: FlightStage {
        package var type: FlightStage.Type { Self.self }

        public init() {}
    }
}

public extension Blimp.TakeOff {

    /// Archive the app with given settings
    func archive(arguments: [ArchiveArgument], verbose: Bool) throws {
        try Shell.command(
            "set -o pipefail && xcodebuild archive",
            arguments: arguments,
            options: verbose ? [.printOutput] : []
        )
        .run()
    }

    /// Export the archive using ExportOptions, generating the plist on-the-fly
    func export(
        archivePath: String,
        exportPath: String,
        options: ExportOptions,
        verbose: Bool
    ) throws {
        let tempPlistURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("blimp-export-options-\(UUID().uuidString).plist")

        defer {
            try? FileManager.default.removeItem(at: tempPlistURL)
        }

        try options.writePlist(to: tempPlistURL)

        try export(
            arguments: [
                .exportArchive(archivePath),
                .exportPath(exportPath),
                .optionsPlistPath(tempPlistURL.path)
            ],
            verbose: verbose
        )
    }
}

// MARK: - Helpers

private extension Blimp.TakeOff {

    func export(arguments: [ExportArgument], verbose: Bool) throws {
        try Shell.command(
            "set -o pipefail && xcodebuild",
            arguments: arguments,
            options: verbose ? [.printOutput] : []
        )
        .run()
    }
}

// MARK: - Subtypes

public extension Blimp.TakeOff {
    
    enum Destination: String {
        case anyIOSDevice
    }
    
    enum Configuration: RawRepresentable {
        case debug
        case beta
        case release
        case custom(String)
        
        public var rawValue: RawValue {
            switch self {
                case .debug: "Debug"
                case .beta: "Beta"
                case .release: "Release"
                case let .custom(customConfig): customConfig
            }
        }
        
        public init?(rawValue: String) {
            switch rawValue.lowercased() {
                case "debug": self = .debug
                case "beta": self = .beta
                case "release": self = .release
                default: self = .custom(rawValue)
            }
        }
    }
    
    enum ArchiveArgument: BashArgument {
        case clean
        case workspacePath(String)
        case projectPath(String)
        case scheme(String)
        case archivePath(String)
        case configuration(Configuration)
        case destination(Destination)
        case cleanOutput

        public var bashArgument: String {
            switch self {
            case .clean:
                "clean"
            case .workspacePath(let path):
                "-workspace \(path)"
            case .projectPath(let path):
                "-project \(path)"
            case .scheme(let schemeName):
                "-scheme \(schemeName)"
            case .archivePath(let path):
                "-archivePath \(path)"
            case .configuration(let config):
                "-configuration \(config.rawValue)"
            case .destination(let destination):
                switch destination {
                case .anyIOSDevice:
                    "-destination generic/platform=iOS"
                }
            case .cleanOutput:
                "| xcbeautify"
            }
        }
    }
    
    enum ExportArgument: BashArgument {
        case exportArchive(String)
        case exportPath(String)
        case optionsPlistPath(String)
        
        public var bashArgument: String {
            switch self {
            case .exportArchive(let path):
                "-exportArchive -archivePath \(path)"
            case .exportPath(let path):
                "-exportPath \(path)"
            case .optionsPlistPath(let path):
                "-exportOptionsPlist \(path)"
            }
        }
    }
    
}
