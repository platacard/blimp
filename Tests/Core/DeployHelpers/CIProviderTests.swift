@testable import DeployHelpers
import Foundation
import XCTest

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

    func testGitLabCIIsDetectedFromItsRunnerVariables() {
        let provider = CIProviders.detect(environment: ["GITLAB_CI": "true", "CI_PROJECT_DIR": "/builds/app"])
        XCTAssertTrue(provider is GitLabCI)
    }

    func testAnExplicitBlimpOutputWinsOverGitLabCI() {
        let provider = CIProviders.detect(environment: [
            "GITLAB_CI": "true",
            "CI_PROJECT_DIR": "/builds/app",
            "BLIMP_OUTPUT": outputFile.path,
        ])
        XCTAssertTrue(provider is DotenvFile)
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
            XCTAssertEqual(error as? Dotenv.Error, .multilineValue("NOTES"))
        }
    }

    func testDotenvFileHasNoSummary() throws {
        let sut = try XCTUnwrap(DotenvFile(environment: ["BLIMP_OUTPUT": outputFile.path]))
        XCTAssertNil(sut.summaryFile)
    }
}

// MARK: GitLab CI

extension CIProviderTests {
    func testGitLabCIWritesADotenvFileInTheProjectDir() throws {
        let sut = try XCTUnwrap(GitLabCI(environment: ["GITLAB_CI": "true", "CI_PROJECT_DIR": "/builds/app"]))
        XCTAssertEqual(sut.outputFile, URL(fileURLWithPath: "/builds/app/blimp.env"))
        XCTAssertEqual(try sut.entry(name: "BUILD_ID", value: "abc"), "BUILD_ID=abc\n")
        XCTAssertNil(sut.summaryFile)
    }

    func testGitLabCIRejectsMultilineValues() throws {
        let sut = try XCTUnwrap(GitLabCI(environment: ["GITLAB_CI": "true", "CI_PROJECT_DIR": "/builds/app"]))
        XCTAssertThrowsError(try sut.entry(name: "NOTES", value: "one\ntwo")) { error in
            XCTAssertEqual(error as? Dotenv.Error, .multilineValue("NOTES"))
        }
    }

    func testGitLabCINeedsTheProjectDir() {
        XCTAssertNil(GitLabCI(environment: ["GITLAB_CI": "true"]))
        XCTAssertNil(GitLabCI(environment: ["CI_PROJECT_DIR": "/builds/app"]))
    }
}
