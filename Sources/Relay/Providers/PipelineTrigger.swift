/// Starts a CI pipeline/workflow on a ref with key-value parameters.
///
/// GitLab maps this to the pipeline trigger API; a GitHub port would map it
/// to `repository_dispatch` (the parameters fit in `client_payload`), other
/// CI systems to their parameterized run APIs.
protocol PipelineTrigger: Sendable {

    func triggerPipeline(ref: String, variables: [String: String]) async throws
}
