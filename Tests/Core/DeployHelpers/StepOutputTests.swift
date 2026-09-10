@testable import DeployHelpers
import Foundation
import XCTest

/// `blimp approach` hands the processed build id to the next step. A process
/// cannot set a variable in its parent shell, so the output goes where CI
/// reads it: appended to `$GITHUB_OUTPUT` as `name=value`.
final class StepOutputTests: XCTestCase {
    private var outputFile: URL!

    override func setUpWithError() throws {
        outputFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("step-output-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: outputFile)
    }

    func testExportAppendsNameValueLinesToGitHubOutput() throws {
        // Given: GitHub Actions creates the file before the step runs.
        try "".write(to: outputFile, atomically: true, encoding: .utf8)
        let sut = StepOutput(environment: ["GITHUB_OUTPUT": outputFile.path])
        // When
        let first = try sut.export("BUILD_ID", "6bab2907-f08a-4b0d-82ed-4423d5874ed7")
        try sut.export("VERSION", "1.0")
        // Then
        XCTAssertEqual(first, outputFile)
        XCTAssertEqual(try String(contentsOf: outputFile, encoding: .utf8),
                       "BUILD_ID=6bab2907-f08a-4b0d-82ed-4423d5874ed7\nVERSION=1.0\n")
    }

    func testExportCreatesTheOutputFileWhenMissing() throws {
        let sut = StepOutput(environment: ["GITHUB_OUTPUT": outputFile.path])
        try sut.export("BUILD_ID", "abc")
        XCTAssertEqual(try String(contentsOf: outputFile, encoding: .utf8), "BUILD_ID=abc\n")
    }

    func testMultilineValuesUseTheHeredocForm() throws {
        let sut = StepOutput(environment: ["GITHUB_OUTPUT": outputFile.path])
        try sut.export("NOTES", "line one\nline two")
        XCTAssertEqual(try String(contentsOf: outputFile, encoding: .utf8),
                       "NOTES<<BLIMP_EOF\nline one\nline two\nBLIMP_EOF\n")
    }

    func testHeredocDelimiterNeverOccursInTheValue() throws {
        let sut = StepOutput(environment: ["GITHUB_OUTPUT": outputFile.path])
        try sut.export("NOTES", "has BLIMP_EOF inside\nand BLIMP_EOF_1 too")
        XCTAssertEqual(try String(contentsOf: outputFile, encoding: .utf8),
                       "NOTES<<BLIMP_EOF_2\nhas BLIMP_EOF inside\nand BLIMP_EOF_1 too\nBLIMP_EOF_2\n")
    }

    func testExportOutsideCIIsANoOp() throws {
        let sut = StepOutput(environment: [:])
        XCTAssertNil(try sut.export("BUILD_ID", "abc"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputFile.path))
    }

    func testEmptyOutputPathIsTreatedAsUnset() throws {
        let sut = StepOutput(environment: ["GITHUB_OUTPUT": ""])
        XCTAssertNil(try sut.export("BUILD_ID", "abc"))
    }

    func testSummarizeAppendsMarkdownToTheStepSummary() throws {
        try "# Earlier\n".write(to: outputFile, atomically: true, encoding: .utf8)
        let sut = StepOutput(environment: ["GITHUB_STEP_SUMMARY": outputFile.path])
        let file = try sut.summarize("Build 1.0 (42) processed")
        XCTAssertEqual(file, outputFile)
        XCTAssertEqual(try String(contentsOf: outputFile, encoding: .utf8),
                       "# Earlier\nBuild 1.0 (42) processed\n")
    }

    func testSummarizeKeepsASingleTrailingNewline() throws {
        let sut = StepOutput(environment: ["GITHUB_STEP_SUMMARY": outputFile.path])
        try sut.summarize("line\n")
        XCTAssertEqual(try String(contentsOf: outputFile, encoding: .utf8), "line\n")
    }

    func testSummarizeOutsideCIIsANoOp() throws {
        let sut = StepOutput(environment: ["GITHUB_STEP_SUMMARY": ""])
        XCTAssertNil(try sut.summarize("ignored"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputFile.path))
    }
}
