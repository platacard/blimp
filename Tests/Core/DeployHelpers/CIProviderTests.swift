@testable import DeployHelpers
import Foundation
import XCTest

/// Each CI system reads a step's outputs from its own place, in its own
/// format. `StepOutput` only knows the `CIProvider` protocol; the concrete
/// provider is detected from the environment or injected.
final class CIProviderTests: XCTestCase {
    private var outputFile: URL!

    override func setUpWithError() throws {
        outputFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("ci-provider-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: outputFile)
    }

    // MARK: Detection

    func testNothingIsDetectedOutsideCI() {
        XCTAssertNil(CIProviders.detect(environment: [:]))
    }

    func testGitHubActionsIsDetectedFromItsOutputsFile() {
        let provider = CIProviders.detect(environment: ["GITHUB_OUTPUT": outputFile.path])
        XCTAssertTrue(provider is GitHubActions)
    }

    func testDotenvFileIsDetectedFromBlimpOutput() {
        let provider = CIProviders.detect(environment: ["BLIMP_OUTPUT": outputFile.path])
        XCTAssertTrue(provider is DotenvFile)
    }

    func testAnExplicitBlimpOutputWinsOverGitHubActions() {
        let provider = CIProviders.detect(environment: [
            "BLIMP_OUTPUT": outputFile.path,
            "GITHUB_OUTPUT": "/somewhere/else",
        ])
        XCTAssertTrue(provider is DotenvFile)
        XCTAssertEqual(provider?.outputFile, outputFile)
    }

    func testEmptyPathsCountAsUnset() {
        XCTAssertNil(CIProviders.detect(environment: ["GITHUB_OUTPUT": "", "BLIMP_OUTPUT": ""]))
    }

    // MARK: GitHub Actions

    func testGitHubActionsWritesSingleLineValuesAsNameEqualsValue() throws {
        let sut = try XCTUnwrap(GitHubActions(environment: ["GITHUB_OUTPUT": outputFile.path]))
        XCTAssertEqual(try sut.entry(name: "BUILD_ID", value: "abc"), "BUILD_ID=abc\n")
    }

    func testGitHubActionsWritesMultilineValuesAsHeredoc() throws {
        let sut = try XCTUnwrap(GitHubActions(environment: ["GITHUB_OUTPUT": outputFile.path]))
        XCTAssertEqual(try sut.entry(name: "NOTES", value: "one\ntwo"),
                       "NOTES<<BLIMP_EOF\none\ntwo\nBLIMP_EOF\n")
    }

    func testGitHubActionsHeredocPreservesATrailingNewline() throws {
        let sut = try XCTUnwrap(GitHubActions(environment: ["GITHUB_OUTPUT": outputFile.path]))
        XCTAssertEqual(try sut.entry(name: "NOTES", value: "one\ntwo\n"),
                       "NOTES<<BLIMP_EOF\none\ntwo\nBLIMP_EOF\n")
    }

    func testGitHubActionsHeredocDelimiterNeverOccursInTheValue() throws {
        let sut = try XCTUnwrap(GitHubActions(environment: ["GITHUB_OUTPUT": outputFile.path]))
        XCTAssertEqual(try sut.entry(name: "NOTES", value: "has BLIMP_EOF inside\nand BLIMP_EOF_1 too"),
                       "NOTES<<BLIMP_EOF_2\nhas BLIMP_EOF inside\nand BLIMP_EOF_1 too\nBLIMP_EOF_2\n")
    }

    func testGitHubActionsExposesTheStepSummaryFile() throws {
        let sut = try XCTUnwrap(GitHubActions(environment: [
            "GITHUB_OUTPUT": outputFile.path,
            "GITHUB_STEP_SUMMARY": "/summary.md",
        ]))
        XCTAssertEqual(sut.summaryFile, URL(fileURLWithPath: "/summary.md"))
    }

    // MARK: Dotenv file (GitLab CI dotenv artifacts, plain shells)

    func testDotenvFileWritesNameEqualsValue() throws {
        let sut = try XCTUnwrap(DotenvFile(environment: ["BLIMP_OUTPUT": outputFile.path]))
        XCTAssertEqual(try sut.entry(name: "BUILD_ID", value: "abc"), "BUILD_ID=abc\n")
    }

    func testDotenvFileRejectsMultilineValues() throws {
        let sut = try XCTUnwrap(DotenvFile(environment: ["BLIMP_OUTPUT": outputFile.path]))
        XCTAssertThrowsError(try sut.entry(name: "NOTES", value: "one\ntwo")) { error in
            XCTAssertEqual(error as? DotenvFile.Error, .multilineValue("NOTES"))
        }
    }

    func testDotenvFileHasNoSummary() throws {
        let sut = try XCTUnwrap(DotenvFile(environment: ["BLIMP_OUTPUT": outputFile.path]))
        XCTAssertNil(sut.summaryFile)
    }
}
