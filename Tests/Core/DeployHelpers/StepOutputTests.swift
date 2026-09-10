@testable import DeployHelpers
import Foundation
import XCTest

final class StepOutputTests: XCTestCase {
    private var outputFile: URL!

    override func setUpWithError() throws {
        outputFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("step-output-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: outputFile)
    }

    func testExportAppendsProviderEntriesToItsOutputFile() throws {
        try "".write(to: outputFile, atomically: true, encoding: .utf8)
        let sut = StepOutput(environment: ["GITHUB_OUTPUT": outputFile.path])
        let first = try sut.export("BUILD_ID", "6bab2907-f08a-4b0d-82ed-4423d5874ed7")
        try sut.export("VERSION", "1.0")
        XCTAssertEqual(first, outputFile)
        XCTAssertEqual(try String(contentsOf: outputFile, encoding: .utf8),
                       "BUILD_ID=6bab2907-f08a-4b0d-82ed-4423d5874ed7\nVERSION=1.0\n")
    }

    func testExportCreatesTheOutputFileWhenMissing() throws {
        let sut = StepOutput(environment: ["BLIMP_OUTPUT": outputFile.path])
        try sut.export("BUILD_ID", "abc")
        XCTAssertEqual(try String(contentsOf: outputFile, encoding: .utf8), "BUILD_ID=abc\n")
    }

    func testExportUsesTheProviderFormat() throws {
        let sut = StepOutput(environment: ["GITHUB_OUTPUT": outputFile.path])
        try sut.export("NOTES", "line one\nline two")
        XCTAssertEqual(try String(contentsOf: outputFile, encoding: .utf8),
                       "NOTES<<BLIMP_EOF\nline one\nline two\nBLIMP_EOF\n")
    }

    func testExportOutsideCIIsANoOp() throws {
        let sut = StepOutput(environment: [:])
        XCTAssertNil(try sut.export("BUILD_ID", "abc"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputFile.path))
    }

    func testSummarizeAppendsMarkdownToTheProviderSummary() throws {
        try "# Earlier\n".write(to: outputFile, atomically: true, encoding: .utf8)
        let sut = StepOutput(environment: ["GITHUB_OUTPUT": "/unused", "GITHUB_STEP_SUMMARY": outputFile.path])
        let file = try sut.summarize("Build 1.0 (42) processed")
        XCTAssertEqual(file, outputFile)
        XCTAssertEqual(try String(contentsOf: outputFile, encoding: .utf8),
                       "# Earlier\nBuild 1.0 (42) processed\n")
    }

    func testSummarizeKeepsASingleTrailingNewline() throws {
        let sut = StepOutput(environment: ["GITHUB_OUTPUT": "/unused", "GITHUB_STEP_SUMMARY": outputFile.path])
        try sut.summarize("line\n")
        XCTAssertEqual(try String(contentsOf: outputFile, encoding: .utf8), "line\n")
    }

    func testSummarizeIsANoOpWhenTheProviderHasNoSummary() throws {
        let sut = StepOutput(environment: ["BLIMP_OUTPUT": outputFile.path])
        XCTAssertNil(try sut.summarize("ignored"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputFile.path))
    }

    func testAnInjectedProviderReplacesDetection() throws {
        let sut = StepOutput(provider: RecordingProvider(outputFile: outputFile))
        try sut.export("BUILD_ID", "abc")
        XCTAssertEqual(try String(contentsOf: outputFile, encoding: .utf8), "recorded BUILD_ID:abc\n")
    }
}

private struct RecordingProvider: CIProvider {
    static let name = "Recording"
    let outputFile: URL?
    let summaryFile: URL? = nil

    init(outputFile: URL) { self.outputFile = outputFile }
    init?(environment: [String: String]) { nil }

    func entry(name: String, value: String) throws -> String { "recorded \(name):\(value)\n" }
}

extension StepOutputTests {
    func testExportFailsLoudlyWhenTheOutputFileCannotBeOpened() {
        let sut = StepOutput(environment: ["BLIMP_OUTPUT": "/nonexistent-dir/out.env"])
        XCTAssertThrowsError(try sut.export("BUILD_ID", "abc")) { error in
            XCTAssertTrue("\(error)".contains("/nonexistent-dir/out.env"), "\(error)")
        }
    }
}

extension StepOutputTests {
    func testACreatedOutputFileIsPrivateToTheUser() throws {
        let sut = StepOutput(environment: ["BLIMP_OUTPUT": outputFile.path])
        try sut.export("BUILD_ID", "abc")
        let mode = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: outputFile.path)[.posixPermissions] as? Int)
        XCTAssertEqual(mode, 0o600)
    }
}
