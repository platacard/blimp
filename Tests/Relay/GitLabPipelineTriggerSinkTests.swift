import XCTest
@testable import BlimpRelay
import Foundation
import Logging
import WebhookKit

final class GitLabPipelineTriggerSinkTests: XCTestCase {

    private struct TriggerFailure: Error {}

    // MARK: - Helpers

    private func makeEvent(
        eventType: String = "buildUploadStateUpdated",
        newState: String? = "COMPLETE",
        instanceId: String? = "1234abcd-56ef-78aa-90bb-ccddeeff0011"
    ) -> VerifiedWebhookEvent {
        let payload = WebhookDeliveryPayload(
            data: .init(
                type: eventType,
                id: "evt-1",
                version: 1,
                attributes: .init(oldState: "PROCESSING", newState: newState),
                relationships: instanceId.map {
                    .init(instance: .init(data: .init(type: "buildUploads", id: $0)))
                }
            )
        )
        return VerifiedWebhookEvent(payload: payload, rawBody: Data(), headers: [:])
    }

    private func makeSink(
        apiClient: StubGitLabAPIClient,
        extraTriggerVariables: [String: String] = [:],
        sendAlert: (@Sendable (String) async -> Void)? = nil
    ) -> GitLabPipelineTriggerSink {
        GitLabPipelineTriggerSink(
            apiClient: apiClient,
            pendingVariablePrefix: "TF_PENDING_",
            extraTriggerVariables: extraTriggerVariables,
            sendAlert: sendAlert,
            logger: Logger(label: "test")
        )
    }

    private func pendingValue(branch: String) -> String {
        Data(#"{"branch":"\#(branch)","buildNumber":"456"}"#.utf8).base64EncodedString()
    }

    private let expectedKey = "TF_PENDING_1234abcd_56ef_78aa_90bb_ccddeeff0011"

    // MARK: - Happy path

    func testTriggersPipelineOnCompleteUpload() async throws {
        let value = pendingValue(branch: "release/1.2.3")
        let client = StubGitLabAPIClient()
        await client.setVariable(GitLabVariable(key: expectedKey, value: value))
        let sink = makeSink(apiClient: client, extraTriggerVariables: ["TEAM": "ios"])

        try await sink.handle(makeEvent())

        let getCalls = await client.getCalls
        let deleteCalls = await client.deleteCalls
        let triggerCalls = await client.triggerCalls
        XCTAssertEqual(getCalls, [expectedKey])
        XCTAssertEqual(deleteCalls, [expectedKey])
        XCTAssertEqual(triggerCalls.count, 1)
        XCTAssertEqual(triggerCalls.first?.ref, "release/1.2.3")
        XCTAssertEqual(triggerCalls.first?.variables, [
            "TESTFLIGHT_FINALIZE": "true",
            "TF_STATE": value,
            "TF_UPLOAD_STATE": "COMPLETE",
            "TEAM": "ios"
        ])
    }

    func testFailedStatePassesFailedUploadState() async throws {
        let client = StubGitLabAPIClient()
        await client.setVariable(GitLabVariable(key: expectedKey, value: pendingValue(branch: "main")))
        let sink = makeSink(apiClient: client)

        try await sink.handle(makeEvent(newState: "FAILED"))

        let triggerCalls = await client.triggerCalls
        XCTAssertEqual(triggerCalls.first?.variables["TF_UPLOAD_STATE"], "FAILED")
        XCTAssertEqual(triggerCalls.first?.ref, "main")
    }

    // MARK: - Benign skips

    func testSkipsUnknownOrAlreadyClaimedUpload() async throws {
        let client = StubGitLabAPIClient()
        let sink = makeSink(apiClient: client)

        try await sink.handle(makeEvent())

        let getCalls = await client.getCalls
        let deleteCalls = await client.deleteCalls
        let triggerCalls = await client.triggerCalls
        XCTAssertEqual(getCalls, [expectedKey])
        XCTAssertTrue(deleteCalls.isEmpty)
        XCTAssertTrue(triggerCalls.isEmpty)
    }

    func testSkipsWhenClaimLostToConcurrentDelivery() async throws {
        let client = StubGitLabAPIClient()
        await client.setVariable(GitLabVariable(key: expectedKey, value: pendingValue(branch: "main")))
        await client.setDeleteResult(false)
        let sink = makeSink(apiClient: client)

        try await sink.handle(makeEvent())

        let triggerCalls = await client.triggerCalls
        XCTAssertTrue(triggerCalls.isEmpty)
    }

    func testIgnoresOtherEventTypes() async throws {
        let client = StubGitLabAPIClient()
        let sink = makeSink(apiClient: client)

        try await sink.handle(makeEvent(eventType: "betaFeedbackScreenshotSubmissionCreated"))
        try await sink.handle(makeEvent(eventType: "webhookPingCreated", newState: nil, instanceId: nil))

        let getCalls = await client.getCalls
        XCTAssertTrue(getCalls.isEmpty)
    }

    func testIgnoresNonTerminalStates() async throws {
        let client = StubGitLabAPIClient()
        let sink = makeSink(apiClient: client)

        try await sink.handle(makeEvent(newState: "PROCESSING"))
        try await sink.handle(makeEvent(newState: nil))

        let getCalls = await client.getCalls
        XCTAssertTrue(getCalls.isEmpty)
    }

    // MARK: - Failures

    func testUndecodablePendingValueThrowsWithoutDeleting() async throws {
        let client = StubGitLabAPIClient()
        await client.setVariable(GitLabVariable(key: expectedKey, value: "not-base64!!!"))
        let sink = makeSink(apiClient: client)

        do {
            try await sink.handle(makeEvent())
            XCTFail("Expected invalidPendingState error")
        } catch let error as GitLabPipelineTriggerError {
            XCTAssertEqual(error, .invalidPendingState(key: expectedKey))
        }

        let deleteCalls = await client.deleteCalls
        let triggerCalls = await client.triggerCalls
        XCTAssertTrue(deleteCalls.isEmpty)
        XCTAssertTrue(triggerCalls.isEmpty)
    }

    func testMissingBranchFieldThrows() async throws {
        let client = StubGitLabAPIClient()
        let value = Data(#"{"buildNumber":"456"}"#.utf8).base64EncodedString()
        await client.setVariable(GitLabVariable(key: expectedKey, value: value))
        let sink = makeSink(apiClient: client)

        do {
            try await sink.handle(makeEvent())
            XCTFail("Expected invalidPendingState error")
        } catch let error as GitLabPipelineTriggerError {
            XCTAssertEqual(error, .invalidPendingState(key: expectedKey))
        }
    }

    func testTriggerFailureRestoresVariableAlertsAndThrows() async throws {
        let value = pendingValue(branch: "main")
        let client = StubGitLabAPIClient()
        await client.setVariable(GitLabVariable(key: expectedKey, value: value))
        await client.setTriggerError(TriggerFailure())

        let alerts = AlertRecorder()
        let sink = makeSink(apiClient: client, sendAlert: { await alerts.record($0) })

        do {
            try await sink.handle(makeEvent())
            XCTFail("Expected trigger error to be rethrown")
        } catch is TriggerFailure {
            // expected
        }

        let createCalls = await client.createCalls
        XCTAssertEqual(createCalls.count, 1)
        XCTAssertEqual(createCalls.first?.key, expectedKey)
        XCTAssertEqual(createCalls.first?.value, value)

        let messages = await alerts.messages
        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0].contains("main"))
    }
}

// MARK: - Test doubles

private actor AlertRecorder {

    private(set) var messages: [String] = []

    func record(_ message: String) {
        messages.append(message)
    }
}

actor StubGitLabAPIClient: GitLabAPIClient {

    private var variable: GitLabVariable?
    private var deleteResult = true
    private var triggerError: Error?

    private(set) var getCalls: [String] = []
    private(set) var deleteCalls: [String] = []
    private(set) var createCalls: [(key: String, value: String)] = []
    private(set) var triggerCalls: [(ref: String, variables: [String: String])] = []

    func setVariable(_ variable: GitLabVariable?) {
        self.variable = variable
    }

    func setDeleteResult(_ result: Bool) {
        deleteResult = result
    }

    func setTriggerError(_ error: Error?) {
        triggerError = error
    }

    func getVariable(key: String) async throws -> GitLabVariable? {
        getCalls.append(key)
        return variable
    }

    func deleteVariable(key: String) async throws -> Bool {
        deleteCalls.append(key)
        return deleteResult
    }

    func createVariable(key: String, value: String) async throws {
        createCalls.append((key: key, value: value))
    }

    func triggerPipeline(ref: String, variables: [String: String]) async throws {
        triggerCalls.append((ref: ref, variables: variables))
        if let triggerError {
            throw triggerError
        }
    }
}
