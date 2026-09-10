import Foundation

/// A dotenv file at an explicit `$BLIMP_OUTPUT` path, for any CI or shell.
public struct DotenvFile: CIProvider {
    public static let name = "dotenv file"
    public static let outputKey = "BLIMP_OUTPUT"

    public let outputFile: URL?
    public let summaryFile: URL? = nil

    public init?(environment: [String: String]) {
        guard let output = environment[Self.outputKey], !output.isEmpty else { return nil }
        outputFile = URL(fileURLWithPath: output)
    }

    public func entry(name: String, value: String) throws -> String {
        try Dotenv.entry(name: name, value: value)
    }
}
