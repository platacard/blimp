import Foundation

/// What a blimp step receives from the previous one — the counterpart of
/// `StepOutput`. An explicit command-line option wins; otherwise the value
/// comes from the environment, so a CI step can hand it over through `env:`
/// (`BUILD_ID: ${{ steps.approach.outputs.BUILD_ID }}`) instead of an inline
/// expression in the command.
public struct StepInput: Sendable {
    /// The processed build id `blimp approach` exports and `blimp land` consumes.
    public static let buildIdKey = "BUILD_ID"

    public enum Error: Swift.Error, Equatable, CustomStringConvertible {
        /// Neither the option nor the environment variable carries a value.
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

    /// The option when given, else the environment variable `name`. Empty
    /// strings count as absent.
    public func value(_ name: String, option: String?) throws -> String {
        if let option, !option.isEmpty { return option }
        if let fromEnvironment = environment[name], !fromEnvironment.isEmpty { return fromEnvironment }
        throw Error.missing(name)
    }
}
