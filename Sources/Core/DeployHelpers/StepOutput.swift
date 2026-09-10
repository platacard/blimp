import Foundation

/// What a blimp step hands to the next one (`blimp approach` → the processed
/// build id for `blimp land`).
///
/// A process cannot set a variable in its parent shell — the former
/// `ProcessInfo.processInfo.setValue(_:forKey: "BUILD_ID")` was Key-Value
/// Coding on a class without that key and threw `NSUnknownKeyException` after
/// every successful upload. Outputs go where the CI system actually reads
/// them; which file and which format is the `CIProvider`'s business. Outside
/// CI the step logs the value and shell callers capture it from the output.
public struct StepOutput: Sendable {
    private let provider: (any CIProvider)?

    /// Uses the given provider, or none — then every call is a no-op.
    public init(provider: (any CIProvider)?) {
        self.provider = provider
    }

    /// Detects the provider from the environment.
    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.init(provider: CIProviders.detect(environment: environment))
    }

    /// The detected provider's name, for logs.
    public var providerName: String? {
        provider.map { type(of: $0).name }
    }

    /// Appends one output entry in the provider's format. Returns the file
    /// written, or nil when there is no provider or it has no outputs file.
    @discardableResult
    public func export(_ name: String, _ value: String) throws -> URL? {
        guard let provider, let file = provider.outputFile else { return nil }
        try append(provider.entry(name: name, value: value), to: file)
        return file
    }

    /// Appends a markdown line to the run-page summary. Returns the file
    /// written, or nil when the provider has no summary.
    @discardableResult
    public func summarize(_ markdown: String) throws -> URL? {
        guard let file = provider?.summaryFile else { return nil }
        try append(markdown.hasSuffix("\n") ? markdown : markdown + "\n", to: file)
        return file
    }
}

private extension StepOutput {
    /// One `O_APPEND` open: creates the file when missing and appends
    /// atomically, so concurrent writers (other steps sharing the file) never
    /// clobber each other.
    func append(_ text: String, to file: URL) throws {
        let descriptor = open(file.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard descriptor >= 0 else {
            throw CocoaError(.fileWriteUnknown, userInfo: [
                NSFilePathErrorKey: file.path,
                NSLocalizedDescriptionKey: "Cannot open \(file.path) for appending: \(String(cString: strerror(errno)))",
            ])
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        try handle.write(contentsOf: Data(text.utf8))
    }
}
