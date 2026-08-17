import Foundation

struct GitLabVariable: Sendable, Equatable {
    let key: String
    let value: String
}

/// The subset of the GitLab REST API used by ``GitLabPipelineTriggerSink``.
/// Abstracted so tests can stub the HTTP layer.
protocol GitLabAPIClient: Sendable {

    /// Fetches a project CI/CD variable. Returns `nil` when the variable does not exist (404).
    func getVariable(key: String) async throws -> GitLabVariable?

    /// Deletes a project CI/CD variable. Returns `false` when the variable was already gone (404).
    func deleteVariable(key: String) async throws -> Bool

    /// Creates a project CI/CD variable (unmasked, unprotected).
    func createVariable(key: String, value: String) async throws

    /// Triggers a pipeline on the given ref with the given trigger variables.
    func triggerPipeline(ref: String, variables: [String: String]) async throws
}
