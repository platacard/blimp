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

/// Detection order is declaration order: an explicit blimp output file wins
/// over what the CI vendor advertises.
public enum CIProviders: CaseIterable {
    case dotenvFile
    case gitLabCI
    case gitHubActions

    public var type: any CIProvider.Type {
        switch self {
        case .dotenvFile: DotenvFile.self
        case .gitLabCI: GitLabCI.self
        case .gitHubActions: GitHubActions.self
        }
    }

    public static func detect(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> (any CIProvider)? {
        for candidate in allCases {
            if let provider = candidate.type.init(environment: environment) { return provider }
        }
        return nil
    }
}
