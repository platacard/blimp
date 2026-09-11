import Foundation

/// `name=value` lines. Dotenv has no multi-line form.
public enum Dotenv {
    public enum Error: Swift.Error, Equatable, CustomStringConvertible {
        case multilineValue(String)

        public var description: String {
            switch self {
            case .multilineValue(let name):
                return "\(name) spans several lines; a dotenv file holds single-line values only"
            }
        }
    }

    public static func entry(name: String, value: String) throws -> String {
        guard !value.contains("\n") else { throw Error.multilineValue(name) }
        return "\(name)=\(value)\n"
    }
}
