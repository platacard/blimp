import Foundation

/// Where a CI system reads what a step hands to the next one, and in which
/// format. `StepOutput` depends only on this protocol; the concrete provider
/// is detected from the environment (`CIProviders.detect`) or injected.
public protocol CIProvider: Sendable {
    /// Human-readable name for logs.
    static var name: String { get }

    /// The provider when the environment says the process runs under it,
    /// nil otherwise.
    init?(environment: [String: String])

    /// The file that receives step outputs.
    var outputFile: URL? { get }

    /// The file that receives a markdown note for the run page, when the
    /// provider has one.
    var summaryFile: URL? { get }

    /// One output entry in the provider's file format, newline-terminated.
    func entry(name: String, value: String) throws -> String
}

public enum CIProviders {
    /// Detection order: an explicit blimp output file wins over what the CI
    /// vendor advertises, so a user can always redirect outputs.
    public static let all: [any CIProvider.Type] = [DotenvFile.self, GitHubActions.self]

    public static func detect(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        from candidates: [any CIProvider.Type] = all
    ) -> (any CIProvider)? {
        for candidate in candidates {
            if let provider = candidate.init(environment: environment) { return provider }
        }
        return nil
    }
}
