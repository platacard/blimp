import Foundation

/// The subset of the GitLab REST API used by ``GitLabPipelineTriggerSink``.
/// Abstracted so tests can stub the HTTP layer.
///
/// Pending upload state lives in the generic package registry as
/// `packages/generic/<packageName>/<uploadId>/state.json` — one package per
/// upload, so parallel deploys never touch each other and nothing leaks into
/// CI job environments the way project variables would.
protocol GitLabAPIClient: Sendable {

    /// Downloads the pending-state file for an upload.
    /// Returns `nil` when no package with that version exists (404).
    func getPendingState(version: String) async throws -> String?

    /// Deletes the pending-state package, claiming the upload for this delivery.
    /// Returns `false` when the package was already gone (claimed concurrently).
    func claimPendingState(version: String) async throws -> Bool

    /// Re-publishes a pending-state file (compensation after a failed trigger).
    func restorePendingState(version: String, content: String) async throws

    /// Triggers a pipeline on the given ref with the given trigger variables.
    func triggerPipeline(ref: String, variables: [String: String]) async throws
}
