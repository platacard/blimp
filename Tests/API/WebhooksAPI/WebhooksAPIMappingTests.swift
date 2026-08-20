import XCTest
@testable import WebhooksAPI

final class WebhooksAPIMappingTests: XCTestCase {

    /// Every public Event case must map onto the generated spec enum.
    /// Fails when a spec regeneration removes or renames an event type.
    func testEveryEventMapsToGeneratedSpecCase() throws {
        for event in WebhooksAPI.Event.allCases {
            XCTAssertEqual(try event.generated().rawValue, event.rawValue)
        }
    }

    /// Every generated spec case must be modeled by the public Event enum.
    /// Fails when a spec regeneration adds an event type we don't expose yet.
    func testEveryGeneratedSpecCaseIsModeled() {
        for generated in Components.Schemas.WebhookEventType.allCases {
            XCTAssertNotNil(
                WebhooksAPI.Event(rawValue: generated.rawValue),
                "Spec case \(generated.rawValue) is missing from WebhooksAPI.Event - update the enum after regenerating"
            )
        }
    }

    func testWebhookSchemaMappingExposesRawEventTypes() {
        let schema = Components.Schemas.Webhook(
            _type: .webhooks,
            id: "webhook-1",
            attributes: .init(
                enabled: true,
                eventTypes: [.buildUploadStateUpdated, .betaFeedbackCrashSubmissionCreated],
                name: "ci",
                url: "https://example.com/hook"
            )
        )

        let webhook = WebhooksAPI.Webhook(schema: schema)

        XCTAssertEqual(webhook.id, "webhook-1")
        XCTAssertTrue(webhook.enabled)
        XCTAssertEqual(webhook.eventTypes, [.buildUploadStateUpdated, .betaFeedbackCrashSubmissionCreated])
        XCTAssertEqual(webhook.rawEventTypes, ["BUILD_UPLOAD_STATE_UPDATED", "BETA_FEEDBACK_CRASH_SUBMISSION_CREATED"])
    }
}
