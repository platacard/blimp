import Foundation

/// GitHub Actions: `name=value` lines appended to the file named by
/// `GITHUB_OUTPUT` become `steps.<id>.outputs.<name>`; multi-line values use
/// the heredoc form. Markdown appended to `GITHUB_STEP_SUMMARY` shows on the
/// run page.
public struct GitHubActions: CIProvider {
    public static let name = "GitHub Actions"
    public static let outputKey = "GITHUB_OUTPUT"
    public static let stepSummaryKey = "GITHUB_STEP_SUMMARY"
    private static let heredocDelimiter = "BLIMP_EOF"

    public let outputFile: URL?
    public let summaryFile: URL?

    public init?(environment: [String: String]) {
        guard let output = environment[Self.outputKey], !output.isEmpty else { return nil }
        outputFile = URL(fileURLWithPath: output)
        summaryFile = environment[Self.stepSummaryKey].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
    }

    public func entry(name: String, value: String) throws -> String {
        guard value.contains("\n") else { return "\(name)=\(value)\n" }
        let eof = delimiter(absentFrom: value)
        let body = value.hasSuffix("\n") ? value : value + "\n"
        return "\(name)<<\(eof)\n\(body)\(eof)\n"
    }
}

private extension GitHubActions {
    /// A heredoc delimiter the value cannot terminate early: the base one, or
    /// the base plus a counter when the value happens to contain it.
    func delimiter(absentFrom value: String) -> String {
        var candidate = Self.heredocDelimiter
        var n = 1
        while value.contains(candidate) {
            candidate = "\(Self.heredocDelimiter)_\(n)"
            n += 1
        }
        return candidate
    }
}
