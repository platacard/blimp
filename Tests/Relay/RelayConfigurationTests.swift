import XCTest
@testable import BlimpRelay
import Logging

final class RelayConfigurationTests: XCTestCase {

    private let baseEnvironment = ["ASC_WEBHOOK_SECRET": "whsec_test"]

    private func gitLabEnvironment(extra: [String: String] = [:]) -> [String: String] {
        baseEnvironment.merging([
            "SINKS": "gitlab-pipeline-trigger",
            "GITLAB_BASE_URL": "https://gitlab.example.com/api/v4",
            "GITLAB_PROJECT_ID": "42",
            "GITLAB_API_TOKEN": "glpat-token",
            "GITLAB_TRIGGER_TOKEN": "glptt-token"
        ]) { $1 }.merging(extra) { $1 }
    }

    func testRefusesToStartWithoutSecret() {
        XCTAssertThrowsError(try RelayConfiguration.load(from: [:])) { error in
            XCTAssertEqual(error as? RelayConfigurationError, .missingSecret)
        }
    }

    func testDefaults() throws {
        let configuration = try RelayConfiguration.load(from: baseEnvironment)

        XCTAssertEqual(configuration.host, "0.0.0.0")
        XCTAssertEqual(configuration.port, 13100)
        XCTAssertEqual(configuration.logLevel, .info)
        XCTAssertEqual(configuration.secrets, ["whsec_test"])
        XCTAssertEqual(configuration.sinks.count, 1)
        guard case .log = configuration.sinks[0] else {
            return XCTFail("Expected default log sink")
        }
    }

    func testSecondarySecretForRotation() throws {
        var environment = baseEnvironment
        environment["ASC_WEBHOOK_SECRET_SECONDARY"] = "whsec_old"

        let configuration = try RelayConfiguration.load(from: environment)

        XCTAssertEqual(configuration.secrets, ["whsec_test", "whsec_old"])
    }

    func testCustomPortAndLogLevel() throws {
        var environment = baseEnvironment
        environment["PORT"] = "8080"
        environment["LOG_LEVEL"] = "DEBUG"

        let configuration = try RelayConfiguration.load(from: environment)

        XCTAssertEqual(configuration.port, 8080)
        XCTAssertEqual(configuration.logLevel, .debug)
    }

    func testInvalidPortThrows() {
        var environment = baseEnvironment
        environment["PORT"] = "not-a-port"

        XCTAssertThrowsError(try RelayConfiguration.load(from: environment)) { error in
            XCTAssertEqual(error as? RelayConfigurationError, .invalidPort("not-a-port"))
        }
    }

    func testUnknownSinkThrows() {
        var environment = baseEnvironment
        environment["SINKS"] = "log,teleport"

        XCTAssertThrowsError(try RelayConfiguration.load(from: environment)) { error in
            XCTAssertEqual(error as? RelayConfigurationError, .unknownSink("teleport"))
        }
    }

    func testForwardSinkRequiresURL() throws {
        var environment = baseEnvironment
        environment["SINKS"] = "forward"

        XCTAssertThrowsError(try RelayConfiguration.load(from: environment))

        environment["FORWARD_URL"] = "https://ci.example.com/hooks/asc"
        let configuration = try RelayConfiguration.load(from: environment)
        guard case .forward(let url) = configuration.sinks[0] else {
            return XCTFail("Expected forward sink")
        }
        XCTAssertEqual(url, "https://ci.example.com/hooks/asc")
    }

    func testGitLabSinkConfiguration() throws {
        let environment = gitLabEnvironment(extra: [
            "EXTRA_TRIGGER_VARIABLES": "TEAM=ios,SOURCE=asc-webhook"
        ])

        let configuration = try RelayConfiguration.load(from: environment)

        guard case .gitlabPipelineTrigger(let gitLab) = configuration.sinks[0] else {
            return XCTFail("Expected gitlab-pipeline-trigger sink")
        }
        XCTAssertEqual(gitLab.baseURL, "https://gitlab.example.com/api/v4")
        XCTAssertEqual(gitLab.projectId, "42")
        XCTAssertEqual(gitLab.apiToken, "glpat-token")
        XCTAssertEqual(gitLab.triggerToken, "glptt-token")
        XCTAssertEqual(gitLab.pendingPackageName, "tf-pending")
        XCTAssertNil(gitLab.alertWebhookURL)
        XCTAssertEqual(gitLab.extraTriggerVariables, ["TEAM": "ios", "SOURCE": "asc-webhook"])
    }

    func testGitLabSinkRequiresAllMandatoryVariables() {
        for missing in ["GITLAB_BASE_URL", "GITLAB_PROJECT_ID", "GITLAB_API_TOKEN", "GITLAB_TRIGGER_TOKEN"] {
            var environment = gitLabEnvironment()
            environment.removeValue(forKey: missing)

            XCTAssertThrowsError(try RelayConfiguration.load(from: environment), "expected \(missing) to be required")
        }
    }

    func testMalformedExtraTriggerVariablesThrow() {
        let environment = gitLabEnvironment(extra: ["EXTRA_TRIGGER_VARIABLES": "TEAM-ios"])

        XCTAssertThrowsError(try RelayConfiguration.load(from: environment)) { error in
            XCTAssertEqual(error as? RelayConfigurationError, .malformedExtraTriggerVariables("TEAM-ios"))
        }
    }

    func testMultipleSinksPreserveOrder() throws {
        var environment = gitLabEnvironment(extra: ["SINKS": "log, forward, gitlab-pipeline-trigger"])
        environment["FORWARD_URL"] = "https://ci.example.com/hooks/asc"

        let configuration = try RelayConfiguration.load(from: environment)

        XCTAssertEqual(configuration.sinks.count, 3)
        guard case .log = configuration.sinks[0],
              case .forward = configuration.sinks[1],
              case .gitlabPipelineTrigger = configuration.sinks[2] else {
            return XCTFail("Expected log, forward, gitlab-pipeline-trigger in order")
        }
    }
}
