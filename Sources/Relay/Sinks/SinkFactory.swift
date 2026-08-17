import AsyncHTTPClient
import Foundation
import Logging
import NIOCore
import WebhookKit

enum SinkFactory {

    static func makeSinks(
        configuration: RelayConfiguration,
        httpClient: HTTPClient,
        logger: Logger
    ) -> [any WebhookSink] {
        configuration.sinks.map { sink in
            switch sink {
            case .log:
                return LogSink(logger: logger)
            case .forward(let url):
                return ForwardSink(url: url, httpClient: httpClient)
            case .gitlabPipelineTrigger(let gitLab):
                let client = HTTPGitLabAPIClient(httpClient: httpClient, configuration: gitLab)
                return PipelineTriggerSink(
                    name: "gitlab-pipeline-trigger",
                    store: client,
                    trigger: client,
                    extraTriggerVariables: gitLab.extraTriggerVariables,
                    sendAlert: makeAlertSender(url: gitLab.alertWebhookURL, httpClient: httpClient, logger: logger),
                    logger: logger
                )
            }
        }
    }

    private static func makeAlertSender(
        url: String?,
        httpClient: HTTPClient,
        logger: Logger
    ) -> (@Sendable (String) async -> Void)? {
        guard let url, !url.isEmpty else {
            return nil
        }
        return { message in
            do {
                var request = HTTPClientRequest(url: url)
                request.method = .POST
                request.headers.add(name: "content-type", value: "application/json")
                let payload = try JSONEncoder().encode(["text": message])
                request.body = .bytes(ByteBuffer(bytes: payload))
                _ = try await httpClient.execute(request, timeout: .seconds(15))
            } catch {
                logger.error("Failed to deliver alert", metadata: [
                    "error": .string(String(describing: error))
                ])
            }
        }
    }
}
