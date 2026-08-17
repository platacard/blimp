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
            extraTriggerVariables: extraTriggerVariables,
            sendAlert: sendAlert,
            logger: Logger(label: "test")
        )
    }

    private func pendingValue(branch: String) -> String {
        Data(#"{"branch":"\#(branch)","buildNumber":"456"}"#.utf8).base64EncodedString()
    }

    // The package version is the raw buildUploads id - no sanitization.
    private let expectedVersion = "1234abcd-56ef-78aa-90bb-ccddeeff0011"

    // MARK: - Happy path

    func testTriggersPipelineOnCompleteUpload() async throws {
        let value = pendingValue(branch: "release/1.2.3")
        let client = StubGitLabAPIClient()
        await client.setPendingState(value)
        let sink = makeSink(apiClient: client, extraTriggerVariables: ["TEAM": "ios"])

        try await sink.handle(makeEvent())

        let getCalls = await client.getCalls
        let claimCalls = await client.claimCalls
        let triggerCalls = await client.triggerCalls
        XCTAssertEqual(getCalls, [expectedVersion])
        XCTAssertEqual(claimCalls, [expectedVersion])
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
        await client.setPendingState(pendingValue(branch: "main"))
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
        let claimCalls = await client.claimCalls
        let triggerCalls = await client.triggerCalls
        XCTAssertEqual(getCalls, [expectedVersion])
        XCTAssertTrue(claimCalls.isEmpty)
        XCTAssertTrue(triggerCalls.isEmpty)
    }

    func testSkipsWhenClaimLostToConcurrentDelivery() async throws {
        let client = StubGitLabAPIClient()
        await client.setPendingState(pendingValue(branch: "main"))
        await client.setClaimResult(false)
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

    func testUndecodablePendingValueThrowsWithoutClaiming() async throws {
        let client = StubGitLabAPIClient()
        await client.setPendingState("not-base64!!!")
        let sink = makeSink(apiClient: client)

        do {
            try await sink.handle(makeEvent())
            XCTFail("Expected invalidPendingState error")
        } catch let error as GitLabPipelineTriggerError {
            XCTAssertEqual(error, .invalidPendingState(version: expectedVersion))
        }

        let claimCalls = await client.claimCalls
        let triggerCalls = await client.triggerCalls
        XCTAssertTrue(claimCalls.isEmpty)
        XCTAssertTrue(triggerCalls.isEmpty)
    }

    func testMissingBranchFieldThrows() async throws {
        let client = StubGitLabAPIClient()
        let value = Data(#"{"buildNumber":"456"}"#.utf8).base64EncodedString()
        await client.setPendingState(value)
        let sink = makeSink(apiClient: client)

        do {
            try await sink.handle(makeEvent())
            XCTFail("Expected invalidPendingState error")
        } catch let error as GitLabPipelineTriggerError {
            XCTAssertEqual(error, .invalidPendingState(version: expectedVersion))
        }
    }

    func testTriggerFailureRestoresStateAlertsAndThrows() async throws {
        let value = pendingValue(branch: "main")
        let client = StubGitLabAPIClient()
        await client.setPendingState(value)
        await client.setTriggerError(TriggerFailure())

        let alerts = AlertRecorder()
        let sink = makeSink(apiClient: client, sendAlert: { await alerts.record($0) })

        do {
            try await sink.handle(makeEvent())
            XCTFail("Expected trigger error to be rethrown")
        } catch is TriggerFailure {
            // expected
        }

        let restoreCalls = await client.restoreCalls
        XCTAssertEqual(restoreCalls.count, 1)
        XCTAssertEqual(restoreCalls.first?.version, expectedVersion)
        XCTAssertEqual(restoreCalls.first?.content, value)

        let messages = await alerts.messages
        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0].contains("main"))
        XCTAssertTrue(messages[0].contains("pending state restored"))
    }

    func testTriggerAndRestoreDoubleFailureEscalatesAlert() async throws {
        let client = StubGitLabAPIClient()
        await client.setPendingState(pendingValue(branch: "main"))
        await client.setTriggerError(TriggerFailure())
        await client.setRestoreError(TriggerFailure())

        let alerts = AlertRecorder()
        let sink = makeSink(apiClient: client, sendAlert: { await alerts.record($0) })

        do {
            try await sink.handle(makeEvent())
            XCTFail("Expected trigger error to be rethrown")
        } catch is TriggerFailure {
            // expected
        }

        let messages = await alerts.messages
        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0].contains("RESTORE ALSO FAILED"))
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

    private var pendingState: String?
    private var claimResult = true
    private var triggerError: Error?
    private var restoreError: Error?

    private(set) var getCalls: [String] = []
    private(set) var claimCalls: [String] = []
    private(set) var restoreCalls: [(version: String, content: String)] = []
    private(set) var triggerCalls: [(ref: String, variables: [String: String])] = []

    func setPendingState(_ state: String?) {
        pendingState = state
    }

    func setClaimResult(_ result: Bool) {
        claimResult = result
    }

    func setTriggerError(_ error: Error?) {
        triggerError = error
    }

    func setRestoreError(_ error: Error?) {
        restoreError = error
    }

    func getPendingState(version: String) async throws -> String? {
        getCalls.append(version)
        return pendingState
    }

    func claimPendingState(version: String) async throws -> Bool {
        claimCalls.append(version)
        return claimResult
    }

    func restorePendingState(version: String, content: String) async throws {
        restoreCalls.append((version: version, content: content))
        if let restoreError {
            throw restoreError
        }
    }

    func triggerPipeline(ref: String, variables: [String: String]) async throws {
        triggerCalls.append((ref: ref, variables: variables))
        if let triggerError {
            throw triggerError
        }
    }
}
