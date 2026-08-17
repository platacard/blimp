import Foundation
import Logging
import WebhookKit

enum GitLabPipelineTriggerError: Error, CustomStringConvertible, Equatable {
    case invalidPendingState(version: String)

    var description: String {
        switch self {
        case .invalidPendingState(let version):
            return "Pending state '\(version)' does not contain base64-encoded JSON with a 'branch' field"
        }
    }
}

/// Resumes a waiting CI pipeline when a build upload reaches a terminal state.
///
/// The upload side of the pipeline publishes its state to the GitLab generic
/// package registry as `packages/generic/<name>/<uploadId>/state.json` — a
/// base64-encoded JSON blob containing at least a `branch` field. This sink
/// claims that package (download + delete, so concurrent redeliveries race
/// safely) and triggers a pipeline on the stored branch, passing the blob back
/// through as a trigger variable.
struct GitLabPipelineTriggerSink: WebhookSink {

    static let handledEventType = "buildUploadStateUpdated"
    static let terminalStates: Set<String> = ["COMPLETE", "FAILED"]

    let name = "gitlab-pipeline-trigger"
    let apiClient: any GitLabAPIClient
    let extraTriggerVariables: [String: String]
    let sendAlert: (@Sendable (String) async -> Void)?
    let logger: Logger

    func handle(_ event: VerifiedWebhookEvent) async throws {
        guard event.payload.eventType == Self.handledEventType else {
            logger.debug("Ignoring event type", metadata: ["eventType": .string(event.payload.eventType)])
            return
        }
        guard let newState = event.payload.newState, Self.terminalStates.contains(newState) else {
            logger.debug("Ignoring non-terminal state", metadata: [
                "newState": .string(event.payload.newState ?? "-")
            ])
            return
        }
        guard let instanceId = event.payload.instanceId else {
            logger.warning("Delivery has no instance id, skipping")
            return
        }

        guard let pendingState = try await apiClient.getPendingState(version: instanceId) else {
            logger.info("Pending state not found, upload is unknown or already claimed", metadata: [
                "uploadId": .string(instanceId)
            ])
            return
        }

        let branch = try parseBranch(fromPendingValue: pendingState, version: instanceId)

        guard try await apiClient.claimPendingState(version: instanceId) else {
            logger.info("Lost claim to a concurrent delivery, skipping", metadata: [
                "uploadId": .string(instanceId)
            ])
            return
        }

        var variables = extraTriggerVariables
        variables["TESTFLIGHT_FINALIZE"] = "true"
        variables["TF_STATE"] = pendingState
        variables["TF_UPLOAD_STATE"] = newState

        do {
            try await apiClient.triggerPipeline(ref: branch, variables: variables)
            logger.info("Triggered pipeline", metadata: [
                "ref": .string(branch),
                "uploadState": .string(newState),
                "uploadId": .string(instanceId)
            ])
        } catch {
            let restored = await restorePendingState(version: instanceId, content: pendingState)
            let stateNote = restored
                ? "pending state restored, Apple redelivery will retry"
                : "RESTORE ALSO FAILED - pending state is lost, finalize manually"
            await sendAlert?(
                "blimp-relay failed to trigger a pipeline on ref '\(branch)' for upload '\(instanceId)' (\(newState)): \(error). \(stateNote)"
            )
            throw error
        }
    }

    private func parseBranch(fromPendingValue value: String, version: String) throws -> String {
        struct PendingState: Decodable {
            let branch: String?
        }

        guard
            let data = Data(base64Encoded: value.trimmingCharacters(in: .whitespacesAndNewlines)),
            let state = try? JSONDecoder().decode(PendingState.self, from: data),
            let branch = state.branch,
            !branch.isEmpty
        else {
            throw GitLabPipelineTriggerError.invalidPendingState(version: version)
        }
        return branch
    }

    private func restorePendingState(version: String, content: String) async -> Bool {
        do {
            try await apiClient.restorePendingState(version: version, content: content)
            return true
        } catch {
            logger.error("Failed to restore pending state after trigger failure", metadata: [
                "uploadId": .string(version),
                "error": .string(String(describing: error))
            ])
            return false
        }
    }
}
