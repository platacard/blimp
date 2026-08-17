import Logging
import WebhookKit

/// Logs a one-line summary of every verified delivery.
struct LogSink: WebhookSink {

    let name = "log"
    let logger: Logger

    func handle(_ event: VerifiedWebhookEvent) async throws {
        logger.info("Received webhook delivery", metadata: [
            "eventType": .string(event.payload.eventType),
            "oldState": .string(event.payload.oldState ?? "-"),
            "newState": .string(event.payload.newState ?? "-"),
            "instanceId": .string(event.payload.instanceId ?? "-")
        ])
    }
}
