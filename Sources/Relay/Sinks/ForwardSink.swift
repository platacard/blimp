import AsyncHTTPClient
import Foundation
import NIOCore
import WebhookKit

struct ForwardError: Error, CustomStringConvertible {
    let status: UInt

    var description: String {
        "Forward target answered with status \(status)"
    }
}

/// Forwards the raw delivery body to a configured URL.
struct ForwardSink: WebhookSink {

    let name = "forward"
    let url: String
    let httpClient: HTTPClient

    func handle(_ event: VerifiedWebhookEvent) async throws {
        var request = HTTPClientRequest(url: url)
        request.method = .POST
        request.headers.add(
            name: "content-type",
            value: event.headers["content-type"] ?? "application/json"
        )
        let safeEventType = String(event.payload.eventType.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        })
        request.headers.add(name: "x-relay-event-type", value: safeEventType)
        request.body = .bytes(ByteBuffer(bytes: event.rawBody))

        let response = try await httpClient.execute(request, timeout: .seconds(30))
        guard (200..<300).contains(response.status.code) else {
            throw ForwardError(status: response.status.code)
        }
    }
}
