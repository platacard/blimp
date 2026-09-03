import XCTest
@testable import BlimpRelay
import Crypto
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import Logging
import WebhookKit

final class RelayRouterTests: XCTestCase {

    private typealias App = Application<RouterResponder<BasicRequestContext>>

    private let primarySecret = "whsec_primary"
    private let secondarySecret = "whsec_secondary"
    private let signatureHeader = "x-apple-signature"

    private let pingBody = Data(#"{"data":{"type":"webhookPingCreated","id":"ping-1","version":1}}"#.utf8)
    private let buildBody = Data(#"""
    {"data":{"type":"buildUploadStateUpdated","id":"evt-1","version":1,"attributes":{"oldState":"PROCESSING","newState":"COMPLETE"},"relationships":{"instance":{"data":{"type":"buildUploads","id":"upload-1"}}}}}
    """#.utf8)

    // MARK: - Helpers

    private func signature(for body: Data, secret: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: body, using: key)
        return "hmacsha256=" + mac.map { String(format: "%02x", $0) }.joined()
    }

    private func makeApp(secrets: [String]? = nil, sinks: [any WebhookSink] = []) -> App {
        let router = RelayRouter.build(
            verifier: SignatureVerifier(secrets: secrets ?? [primarySecret, secondarySecret]),
            sinks: sinks,
            logger: Logger(label: "relay-router-tests")
        )
        return Application(router: router)
    }

    private func makeFields(_ headers: [String: String]) throws -> HTTPFields {
        var fields = HTTPFields()
        for (name, value) in headers {
            fields[try XCTUnwrap(HTTPField.Name(name))] = value
        }
        return fields
    }

    private func post(_ app: App, body: Data, headers: [String: String]) async throws -> TestResponse {
        let fields = try makeFields(headers)
        return try await app.test(.router) { client in
            try await client.execute(
                uri: RelayRouter.webhookPath,
                method: .post,
                headers: fields,
                body: ByteBuffer(bytes: body)
            )
        }
    }

    private func postSigned(
        _ app: App,
        body: Data,
        secret: String? = nil,
        headerName: String? = nil
    ) async throws -> TestResponse {
        try await post(app, body: body, headers: [
            headerName ?? signatureHeader: signature(for: body, secret: secret ?? primarySecret)
        ])
    }

    private func assertJSON(_ response: TestResponse, status: HTTPResponse.Status, body: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(response.status, status, file: file, line: line)
        XCTAssertEqual(response.headers[.contentType], "application/json", file: file, line: line)
        XCTAssertEqual(String(buffer: response.body), body, file: file, line: line)
    }

    // MARK: - Accepted deliveries

    func testAcknowledgesSignedPingWithoutInvokingSinks() async throws {
        let recorder = EventRecorder()
        let app = makeApp(sinks: [RecordingSink(recorder: recorder)])

        let response = try await postSigned(app, body: pingBody)

        assertJSON(response, status: .ok, body: #"{"status":"ok"}"#)
        let events = await recorder.events
        XCTAssertTrue(events.isEmpty)
    }

    func testDeliversVerifiedEventWithRawBodyAndLowercasedHeaders() async throws {
        let recorder = EventRecorder()
        let app = makeApp(sinks: [RecordingSink(recorder: recorder)])
        let signature = signature(for: buildBody, secret: primarySecret)

        let response = try await post(app, body: buildBody, headers: [
            "X-Apple-Signature": signature,
            "X-Apple-Delivery-Id": "delivery-42"
        ])

        assertJSON(response, status: .ok, body: #"{"status":"ok"}"#)
        let events = await recorder.events
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.rawBody, buildBody)
        XCTAssertEqual(events.first?.headers[signatureHeader], signature)
        XCTAssertEqual(events.first?.headers["x-apple-delivery-id"], "delivery-42")
        XCTAssertEqual(events.first?.payload.instanceId, "upload-1")
        XCTAssertEqual(events.first?.payload.newState, "COMPLETE")
    }

    func testAcceptsSignatureFromSecondarySecretDuringRotation() async throws {
        let recorder = EventRecorder()
        let app = makeApp(sinks: [RecordingSink(recorder: recorder)])

        let response = try await postSigned(app, body: buildBody, secret: secondarySecret)

        XCTAssertEqual(response.status, .ok)
        let events = await recorder.events
        XCTAssertEqual(events.count, 1)
    }

    func testAcknowledgesVerifiedButUndecodableBody() async throws {
        let recorder = EventRecorder()
        let app = makeApp(sinks: [RecordingSink(recorder: recorder)])

        let response = try await postSigned(app, body: Data("not json at all".utf8))

        assertJSON(response, status: .ok, body: #"{"status":"ok"}"#)
        let events = await recorder.events
        XCTAssertTrue(events.isEmpty)
    }

    // MARK: - Rejected deliveries

    func testRejectsMissingSignature() async throws {
        let recorder = EventRecorder()
        let app = makeApp(sinks: [RecordingSink(recorder: recorder)])

        let response = try await post(app, body: buildBody, headers: [:])

        assertJSON(response, status: .unauthorized, body: #"{"status":"unauthorized"}"#)
        let events = await recorder.events
        XCTAssertTrue(events.isEmpty)
    }

    func testRejectsSignatureFromUnknownSecret() async throws {
        let recorder = EventRecorder()
        let app = makeApp(sinks: [RecordingSink(recorder: recorder)])

        let response = try await postSigned(app, body: buildBody, secret: "not-configured")

        XCTAssertEqual(response.status, .unauthorized)
        let events = await recorder.events
        XCTAssertTrue(events.isEmpty)
    }

    func testRejectsSignatureFromRetiredSecret() async throws {
        let app = makeApp(secrets: [primarySecret])

        let response = try await postSigned(app, body: buildBody, secret: secondarySecret)

        XCTAssertEqual(response.status, .unauthorized)
    }

    func testRejectsBodyTamperedAfterSigning() async throws {
        let app = makeApp()
        let signedForPing = signature(for: pingBody, secret: primarySecret)

        let response = try await post(app, body: buildBody, headers: [signatureHeader: signedForPing])

        XCTAssertEqual(response.status, .unauthorized)
    }

    func testRejectsMalformedSignatureHeader() async throws {
        let app = makeApp()
        let digest = signature(for: buildBody, secret: primarySecret).dropFirst("hmacsha256=".count)

        for header in ["sha256=\(digest)", String(digest), "hmacsha256=", "hmacsha256=zz"] {
            let response = try await post(app, body: buildBody, headers: [signatureHeader: header])
            XCTAssertEqual(response.status, .unauthorized, "header: \(header)")
        }
    }

    func testRejectsOversizedBodyBeforeVerifying() async throws {
        let recorder = EventRecorder()
        let app = makeApp(sinks: [RecordingSink(recorder: recorder)])
        let oversized = Data(repeating: UInt8(ascii: " "), count: (1 << 20) + 1)

        let response = try await postSigned(app, body: oversized)

        assertJSON(response, status: .contentTooLarge, body: #"{"status":"too_large"}"#)
        let events = await recorder.events
        XCTAssertTrue(events.isEmpty)
    }

    func testAcceptsBodyAtExactSizeLimit() async throws {
        let app = makeApp()
        let padding = String(repeating: " ", count: (1 << 20) - pingBody.count)
        let body = pingBody + Data(padding.utf8)

        let response = try await postSigned(app, body: body)

        XCTAssertEqual(response.status, .ok)
    }

    // MARK: - Sink outcomes

    func testReturnsServerErrorWhenAnySinkFailsButStillRunsRemainingSinks() async throws {
        let recorder = EventRecorder()
        let app = makeApp(sinks: [FailingSink(), RecordingSink(recorder: recorder)])

        let response = try await postSigned(app, body: buildBody)

        assertJSON(response, status: .internalServerError, body: #"{"status":"error"}"#)
        let events = await recorder.events
        XCTAssertEqual(events.count, 1)
    }

    // MARK: - Health

    func testHealthProbesDoNotRequireSignature() async throws {
        let app = makeApp()

        try await app.test(.router) { client in
            for path in ["/sys/health/liveness", "/sys/health/readiness"] {
                let response = try await client.execute(uri: path, method: .get)
                XCTAssertEqual(response.status, .ok, path)
                XCTAssertEqual(String(buffer: response.body), "OK", path)
            }
        }
    }
}

// MARK: - Test doubles

private actor EventRecorder {
    private(set) var events = [VerifiedWebhookEvent]()

    func record(_ event: VerifiedWebhookEvent) {
        events.append(event)
    }
}

private struct RecordingSink: WebhookSink {
    let name = "recording"
    let recorder: EventRecorder

    func handle(_ event: VerifiedWebhookEvent) async throws {
        await recorder.record(event)
    }
}

private struct FailingSink: WebhookSink {
    struct Failure: Error {}

    let name = "failing"

    func handle(_ event: VerifiedWebhookEvent) async throws {
        throw Failure()
    }
}
