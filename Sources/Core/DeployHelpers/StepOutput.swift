import Darwin
import Foundation

/// What a blimp step hands to the next one, written where the detected
/// `CIProvider` reads it. Without a provider every call is a no-op.
public struct StepOutput: Sendable {
    private let provider: (any CIProvider)?

    public init(provider: (any CIProvider)?) {
        self.provider = provider
    }

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.init(provider: CIProviders.detect(environment: environment))
    }

    public var providerName: String? {
        provider.map { type(of: $0).name }
    }

    /// Returns the file written, nil when the provider has no outputs file.
    @discardableResult
    public func export(_ name: String, _ value: String) throws -> URL? {
        guard let provider, let file = provider.outputFile else { return nil }
        try append(provider.entry(name: name, value: value), to: file)
        return file
    }

    /// Returns the file written, nil when the provider has no summary.
    @discardableResult
    public func summarize(_ markdown: String) throws -> URL? {
        guard let file = provider?.summaryFile else { return nil }
        try append(markdown.hasSuffix("\n") ? markdown : markdown + "\n", to: file)
        return file
    }
}

private extension StepOutput {
    /// `O_APPEND`: creates when missing, atomic for shared files.
    func append(_ text: String, to file: URL) throws {
        let descriptor = open(file.path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
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
