import Foundation
import Logging
import WebhookKit

enum GitLabPipelineTriggerError: Error, CustomStringConvertible, Equatable {
    case invalidPendingState(key: String)

    var description: String {
        switch self {
        case .invalidPendingState(let key):
            return "Pending variable '\(key)' does not contain base64-encoded JSON with a 'branch' field"
        }
    }
}

/// Resumes a waiting CI pipeline when a build upload reaches a terminal state.
///
/// The upload side of the pipeline stores its state in a GitLab project variable named
/// `<prefix><instanceId>` (dashes replaced with underscores) whose value is a base64-encoded
/// JSON blob containing at least a `branch` field. This sink claims that variable
/// (get + delete, so concurrent redeliveries race safely) and triggers a pipeline on the
/// stored branch, passing the blob back through as a trigger variable.
struct GitLabPipelineTriggerSink: WebhookSink {

    static let handledEventType = "buildUploadStateUpdated"
    static let terminalStates: Set<String> = ["COMPLETE", "FAILED"]

    let name = "gitlab-pipeline-trigger"
    let apiClient: any GitLabAPIClient
    let pendingVariablePrefix: String
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

        let key = pendingVariablePrefix + instanceId.replacingOccurrences(of: "-", with: "_")

        guard let variable = try await apiClient.getVariable(key: key) else {
            logger.info("Pending variable not found, upload is unknown or already claimed", metadata: [
                "key": .string(key)
            ])
            return
        }

        let branch = try parseBranch(fromPendingValue: variable.value, key: key)

        guard try await apiClient.deleteVariable(key: key) else {
            logger.info("Lost claim to a concurrent delivery, skipping", metadata: ["key": .string(key)])
            return
        }

        var variables = extraTriggerVariables
        variables["TESTFLIGHT_FINALIZE"] = "true"
        variables["TF_STATE"] = variable.value
        variables["TF_UPLOAD_STATE"] = newState

        do {
            try await apiClient.triggerPipeline(ref: branch, variables: variables)
            logger.info("Triggered pipeline", metadata: [
                "ref": .string(branch),
                "uploadState": .string(newState),
                "key": .string(key)
            ])
        } catch {
            let restored = await restorePendingVariable(variable)
            let stateNote = restored
                ? "pending state restored, Apple redelivery will retry"
                : "RESTORE ALSO FAILED - pending state is lost, finalize manually"
            await sendAlert?(
                "blimp-relay failed to trigger a pipeline on ref '\(branch)' for upload '\(instanceId)' (\(newState)): \(error). \(stateNote)"
            )
            throw error
        }
    }

    private func parseBranch(fromPendingValue value: String, key: String) throws -> String {
        struct PendingState: Decodable {
            let branch: String?
        }

        guard
            let data = Data(base64Encoded: value.trimmingCharacters(in: .whitespacesAndNewlines)),
            let state = try? JSONDecoder().decode(PendingState.self, from: data),
            let branch = state.branch,
            !branch.isEmpty
        else {
            throw GitLabPipelineTriggerError.invalidPendingState(key: key)
        }
        return branch
    }

    private func restorePendingVariable(_ variable: GitLabVariable) async -> Bool {
        do {
            try await apiClient.createVariable(key: variable.key, value: variable.value)
            return true
        } catch {
            logger.error("Failed to restore pending variable after trigger failure", metadata: [
                "key": .string(variable.key),
                "error": .string(String(describing: error))
            ])
            return false
        }
    }
}
