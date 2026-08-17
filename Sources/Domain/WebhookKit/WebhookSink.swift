import Foundation

/// A webhook delivery that passed signature verification, ready to be handed to sinks.
public struct VerifiedWebhookEvent: Sendable {

    /// The decoded delivery payload.
    public let payload: WebhookDeliveryPayload

    /// The raw request body, byte-for-byte as received.
    public let rawBody: Data

    /// The request headers with lowercased keys.
    public let headers: [String: String]

    public init(payload: WebhookDeliveryPayload, rawBody: Data, headers: [String: String]) {
        self.payload = payload
        self.rawBody = rawBody
        self.headers = headers
    }
}

/// A destination for verified webhook events.
///
/// A sink may throw to signal a delivery failure — the receiver is expected to answer
/// with a 5xx so the sender redelivers. Events a sink is not interested in should be
/// skipped silently without throwing.
public protocol WebhookSink: Sendable {

    /// A short identifier used in logs.
    var name: String { get }

    func handle(_ event: VerifiedWebhookEvent) async throws
}
