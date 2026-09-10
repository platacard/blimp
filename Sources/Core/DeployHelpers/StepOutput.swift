import Foundation

/// What a blimp step hands to the next one (`blimp approach` → the processed
/// build id for `blimp land`).
///
/// A process cannot set a variable in its parent shell — the former
/// `ProcessInfo.processInfo.setValue(_:forKey: "BUILD_ID")` was Key-Value
/// Coding on a class without that key and threw `NSUnknownKeyException` after
/// every successful upload. Outputs go where CI actually reads them: appended
/// to the file named by `GITHUB_OUTPUT` in the `name=value` form GitHub Actions
/// exposes as `steps.<id>.outputs.<name>`. Outside CI the step logs the value
/// and shell callers capture it from the output.
///
/// A step can also leave a note on the run page: markdown appended to the file
/// named by `GITHUB_STEP_SUMMARY`.
public struct StepOutput: Sendable {
    /// GitHub Actions' per-step outputs file.
    public static let gitHubOutputKey = "GITHUB_OUTPUT"
    /// GitHub Actions' per-step markdown summary file.
    public static let gitHubStepSummaryKey = "GITHUB_STEP_SUMMARY"
    private static let heredocDelimiter = "BLIMP_EOF"

    private let environment: [String: String]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    /// Appends `name=value` (or the heredoc form for multi-line values) to the
    /// CI outputs file. Returns that file, or nil when no CI outputs file is
    /// configured — then there is nothing to export and nothing is written.
    @discardableResult
    public func export(_ name: String, _ value: String) throws -> URL? {
        guard let path = environment[Self.gitHubOutputKey], !path.isEmpty else { return nil }
        let file = URL(fileURLWithPath: path)
        let eof = delimiter(absentFrom: value)
        let line = value.contains("\n") ? "\(name)<<\(eof)\n\(value)\n\(eof)\n" : "\(name)=\(value)\n"
        try append(line, to: file)
        return file
    }

    /// Appends a markdown line to the step summary shown on the run page.
    /// Returns that file, or nil when no summary file is configured.
    @discardableResult
    public func summarize(_ markdown: String) throws -> URL? {
        guard let path = environment[Self.gitHubStepSummaryKey], !path.isEmpty else { return nil }
        let file = URL(fileURLWithPath: path)
        try append(markdown.hasSuffix("\n") ? markdown : markdown + "\n", to: file)
        return file
    }

    /// A heredoc delimiter the value cannot terminate early: the base one, or
    /// the base plus a counter when the value happens to contain it.
    private func delimiter(absentFrom value: String) -> String {
        var candidate = Self.heredocDelimiter
        var n = 1
        while value.contains(candidate) {
            candidate = "\(Self.heredocDelimiter)_\(n)"
            n += 1
        }
        return candidate
    }

    private func append(_ text: String, to file: URL) throws {
        let data = Data(text.utf8)
        guard FileManager.default.fileExists(atPath: file.path) else {
            try data.write(to: file)
            return
        }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }
}
