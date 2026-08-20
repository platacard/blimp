import Foundation
import Hummingbird
import Logging
import WebhookKit

enum RelayRouter {

    static let webhookPath = "/webhooks/appstoreconnect"
    private static let maxBodyBytes = 1 << 20

    static func build(
        verifier: SignatureVerifier,
        sinks: [any WebhookSink],
        logger: Logger
    ) -> Router<BasicRequestContext> {
        let router = Router()

        router.get("/sys/health/liveness") { _, _ in "OK" }
        router.get("/sys/health/readiness") { _, _ in "OK" }

        router.post(RouterPath(webhookPath)) { request, _ -> Response in
            let buffer: ByteBuffer
            do {
                buffer = try await request.body.collect(upTo: maxBodyBytes)
            } catch {
                // Oversized bodies can never verify; a 4xx keeps Apple from
                // redelivering them and from masquerading as sink failures.
                logger.warning("Rejected delivery: body exceeds \(maxBodyBytes) bytes")
                return jsonResponse(status: .contentTooLarge, body: #"{"status":"too_large"}"#)
            }
            let rawBody = Data(buffer.readableBytesView)

            var headers = [String: String]()
            for field in request.headers {
                // canonicalName is the lowercased field name (swift-http-types),
                // matching the lowercase lookups below and in VerifiedWebhookEvent.
                headers[field.name.canonicalName] = field.value
            }

            guard verifier.verify(rawBody: rawBody, signatureHeader: headers["x-apple-signature"]) else {
                logger.warning("Rejected delivery: invalid or missing signature")
                return jsonResponse(status: .unauthorized, body: #"{"status":"unauthorized"}"#)
            }

            let payload: WebhookDeliveryPayload
            do {
                payload = try JSONDecoder().decode(WebhookDeliveryPayload.self, from: rawBody)
            } catch {
                logger.info("Acknowledged verified delivery with undecodable payload", metadata: [
                    "error": .string(String(describing: error))
                ])
                return jsonResponse(status: .ok, body: #"{"status":"ok"}"#)
            }

            if payload.isPing {
                logger.info("Received webhook ping")
                return jsonResponse(status: .ok, body: #"{"status":"ok"}"#)
            }

            let event = VerifiedWebhookEvent(payload: payload, rawBody: rawBody, headers: headers)

            var outcomes = [String]()
            var failed = false
            for sink in sinks {
                do {
                    try await sink.handle(event)
                    outcomes.append("\(sink.name)=ok")
                } catch {
                    failed = true
                    outcomes.append("\(sink.name)=error")
                    logger.error("Sink failed", metadata: [
                        "sink": .string(sink.name),
                        "error": .string(String(describing: error))
                    ])
                }
            }

            logger.info("Processed delivery", metadata: [
                "eventType": .string(payload.eventType),
                "newState": .string(payload.newState ?? "-"),
                "instanceId": .string(payload.instanceId ?? "-"),
                "sinks": .string(outcomes.joined(separator: ","))
            ])

            return failed
                ? jsonResponse(status: .internalServerError, body: #"{"status":"error"}"#)
                : jsonResponse(status: .ok, body: #"{"status":"ok"}"#)
        }

        return router
    }

    private static func jsonResponse(status: HTTPResponse.Status, body: String) -> Response {
        Response(
            status: status,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(string: body))
        )
    }
}
