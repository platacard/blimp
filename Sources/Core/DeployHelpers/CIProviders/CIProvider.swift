import Foundation

/// Where a CI system reads step outputs, and in which format.
public protocol CIProvider: Sendable {
    static var name: String { get }

    /// nil when the environment does not belong to this provider.
    init?(environment: [String: String])

    var outputFile: URL? { get }
    /// Markdown shown on the run page, for providers that have one.
    var summaryFile: URL? { get }

    /// One newline-terminated entry in the provider's format.
    func entry(name: String, value: String) throws -> String
}

public enum CIProviders {
    /// An explicit blimp output file wins over what the CI vendor advertises.
    public static let all: [any CIProvider.Type] = [DotenvFile.self, GitLabCI.self, GitHubActions.self]

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
