import XCTest
@testable import WebhookKit
import Foundation

final class DeliveryPayloadTests: XCTestCase {

    private func decode(_ json: String) throws -> WebhookDeliveryPayload {
        try JSONDecoder().decode(WebhookDeliveryPayload.self, from: Data(json.utf8))
    }

    func testDecodesPingPayload() throws {
        let payload = try decode(#"""
        {"data":{"type":"webhookPingCreated","id":"ping-id-1","version":1}}
        """#)

        XCTAssertTrue(payload.isPing)
        XCTAssertEqual(payload.eventType, "webhookPingCreated")
        XCTAssertNil(payload.newState)
        XCTAssertNil(payload.instanceId)
    }

    func testDecodesBuildUploadCompletePayload() throws {
        let payload = try decode(#"""
        {
          "data": {
            "type": "buildUploadStateUpdated",
            "id": "evt-123",
            "version": 1,
            "attributes": {"oldState": "PROCESSING", "newState": "COMPLETE"},
            "relationships": {
              "instance": {
                "data": {"type": "buildUploads", "id": "1234abcd-56ef-78aa-90bb-ccddeeff0011"},
                "links": {"self": "https://api.appstoreconnect.apple.com/v1/buildUploads/1234abcd-56ef-78aa-90bb-ccddeeff0011"}
              }
            }
          }
        }
        """#)

        XCTAssertFalse(payload.isPing)
        XCTAssertEqual(payload.eventType, "buildUploadStateUpdated")
        XCTAssertEqual(payload.oldState, "PROCESSING")
        XCTAssertEqual(payload.newState, "COMPLETE")
        XCTAssertEqual(payload.instanceId, "1234abcd-56ef-78aa-90bb-ccddeeff0011")
        XCTAssertEqual(payload.data?.version, 1)
        XCTAssertEqual(
            payload.data?.relationships?.instance?.links?.selfLink,
            "https://api.appstoreconnect.apple.com/v1/buildUploads/1234abcd-56ef-78aa-90bb-ccddeeff0011"
        )
    }

    func testDecodesBuildUploadFailedPayload() throws {
        let payload = try decode(#"""
        {
          "data": {
            "type": "buildUploadStateUpdated",
            "id": "evt-456",
            "attributes": {"oldState": "PROCESSING", "newState": "FAILED"},
            "relationships": {"instance": {"data": {"type": "buildUploads", "id": "upload-2"}}}
          }
        }
        """#)

        XCTAssertEqual(payload.newState, "FAILED")
        XCTAssertEqual(payload.instanceId, "upload-2")
    }

    func testDecodesValueSpelledStateTransitionAttributes() throws {
        let payload = try decode(#"""
        {
          "data": {
            "type": "appStoreVersionAppVersionStateUpdated",
            "id": "evt-789",
            "attributes": {"oldValue": "PROCESSING", "newValue": "COMPLETE", "timestamp": "2026-08-19T10:00:00Z"},
            "relationships": {"instance": {"data": {"type": "appStoreVersions", "id": "version-1"}}}
          }
        }
        """#)

        XCTAssertEqual(payload.oldState, "PROCESSING")
        XCTAssertEqual(payload.newState, "COMPLETE")
        XCTAssertEqual(payload.instanceId, "version-1")
    }

    func testDecodesUnknownEventTypeLeniently() throws {
        let payload = try decode(#"""
        {
          "data": {
            "type": "betaFeedbackScreenshotSubmissionCreated",
            "id": "evt-789",
            "attributes": {"somethingNew": {"nested": true}},
            "relationships": {"unexpectedRelation": {"data": {"id": "x"}}}
          }
        }
        """#)

        XCTAssertEqual(payload.eventType, "betaFeedbackScreenshotSubmissionCreated")
        XCTAssertFalse(payload.isPing)
        XCTAssertNil(payload.newState)
        XCTAssertNil(payload.instanceId)
    }

    func testIgnoresExtraUnknownFields() throws {
        let payload = try decode(#"""
        {
          "meta": {"paging": {"total": 1}},
          "data": {
            "type": "buildUploadStateUpdated",
            "id": "evt-1",
            "futureField": "ignored",
            "attributes": {"oldState": "PROCESSING", "newState": "COMPLETE", "reason": "n/a"},
            "relationships": {
              "instance": {
                "data": {"type": "buildUploads", "id": "upload-3", "extra": 42},
                "links": {"self": "https://example.com", "related": "https://example.com/related"}
              },
              "other": {"data": null}
            }
          },
          "included": []
        }
        """#)

        XCTAssertEqual(payload.newState, "COMPLETE")
        XCTAssertEqual(payload.instanceId, "upload-3")
    }

    func testDecodesEmptyObject() throws {
        let payload = try decode("{}")

        XCTAssertEqual(payload.eventType, "unknown")
        XCTAssertFalse(payload.isPing)
        XCTAssertNil(payload.newState)
        XCTAssertNil(payload.oldState)
        XCTAssertNil(payload.instanceId)
    }
}
