import Foundation

/// What a blimp step receives from the previous one: the explicit option,
/// else the environment variable of the same name.
public struct StepInput: Sendable {
    public static let buildIdKey = "BUILD_ID"

    public enum Error: Swift.Error, Equatable, CustomStringConvertible {
        case missing(String)

        public var description: String {
            switch self {
            case .missing(let variable):
                let words = variable.lowercased().split(separator: "_")
                return "No \(words.joined(separator: " ")): pass --\(words.joined(separator: "-")) "
                    + "or set \(variable) in the environment"
            }
        }
    }

    private let environment: [String: String]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    /// Empty strings count as absent.
    public func value(_ name: String, option: String?) throws -> String {
        if let option, !option.isEmpty { return option }
        if let fromEnvironment = environment[name], !fromEnvironment.isEmpty { return fromEnvironment }
        throw Error.missing(name)
    }
}
