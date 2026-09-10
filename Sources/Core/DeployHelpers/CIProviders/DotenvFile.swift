import Foundation

/// `name=value` lines at `$BLIMP_OUTPUT`: a GitLab CI dotenv artifact, or a
/// file any shell can `source`. Dotenv has no multi-line form.
public struct DotenvFile: CIProvider {
    public enum Error: Swift.Error, Equatable, CustomStringConvertible {
        case multilineValue(String)

        public var description: String {
            switch self {
            case .multilineValue(let name):
                return "\(name) spans several lines; a dotenv file (\(DotenvFile.outputKey)) holds single-line values only"
            }
        }
    }

    public static let name = "dotenv file"
    public static let outputKey = "BLIMP_OUTPUT"

    public let outputFile: URL?
    public let summaryFile: URL? = nil

    public init?(environment: [String: String]) {
        guard let output = environment[Self.outputKey], !output.isEmpty else { return nil }
        outputFile = URL(fileURLWithPath: output)
    }

    public func entry(name: String, value: String) throws -> String {
        guard !value.contains("\n") else { throw Error.multilineValue(name) }
        return "\(name)=\(value)\n"
    }
}
