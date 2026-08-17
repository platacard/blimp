import Foundation

/// Keyed storage for pending-upload state with an atomic claim.
///
/// One entry per upload id. `claimPendingState` must be atomic across
/// concurrent callers: exactly one claimer wins, every other one sees `false`.
/// Implementations back this with whatever their CI provider offers -
/// GitLab uses the generic package registry with delete-as-claim; a GitHub
/// port could use one git ref per upload (ref deletion is atomic); any
/// object store with conditional delete works too.
protocol PendingStateStore: Sendable {

    /// Returns the stored state for an upload, or `nil` when the upload is
    /// unknown or already claimed.
    func getPendingState(uploadId: String) async throws -> String?

    /// Claims the upload for this caller by removing the entry.
    /// Returns `false` when a concurrent caller claimed it first.
    func claimPendingState(uploadId: String) async throws -> Bool

    /// Puts a claimed entry back (compensation after a failed trigger).
    func restorePendingState(uploadId: String, content: String) async throws
}
