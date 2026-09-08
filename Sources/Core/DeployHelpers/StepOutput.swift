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
public struct StepOutput: Sendable {
    /// GitHub Actions' per-step outputs file.
    public static let gitHubOutputKey = "GITHUB_OUTPUT"
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
        let line = value.contains("\n")
            ? "\(name)<<\(Self.heredocDelimiter)\n\(value)\n\(Self.heredocDelimiter)\n"
            : "\(name)=\(value)\n"
        try append(line, to: file)
        return file
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
