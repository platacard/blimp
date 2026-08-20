import Foundation

/// A lenient model of an App Store Connect webhook delivery payload.
///
/// Webhook delivery payloads are not part of the App Store Connect OpenAPI specification,
/// so this model is hand-written. Every field is optional and unknown fields are ignored,
/// which keeps decoding resilient to payload evolution on Apple's side.
public struct WebhookDeliveryPayload: Codable, Sendable {

    public struct Ref: Codable, Sendable {
        public var type: String?
        public var id: String?

        public init(type: String? = nil, id: String? = nil) {
            self.type = type
            self.id = id
        }
    }

    public struct Links: Codable, Sendable {

        enum CodingKeys: String, CodingKey {
            case selfLink = "self"
        }

        public var selfLink: String?

        public init(selfLink: String? = nil) {
            self.selfLink = selfLink
        }
    }

    public struct Instance: Codable, Sendable {
        public var data: Ref?
        public var links: Links?

        public init(data: Ref? = nil, links: Links? = nil) {
            self.data = data
            self.links = links
        }
    }

    public struct Relationships: Codable, Sendable {
        public var instance: Instance?

        public init(instance: Instance? = nil) {
            self.instance = instance
        }
    }

    public struct Attributes: Codable, Sendable {
        public var oldState: String?
        public var newState: String?

        enum CodingKeys: String, CodingKey {
            case oldState
            case newState
            case oldValue
            case newValue
        }

        public init(oldState: String? = nil, newState: String? = nil) {
            self.oldState = oldState
            self.newState = newState
        }

        // Apple's state-transition payloads are inconsistent across event types:
        // buildUploadStateUpdated carries oldState/newState, while appStoreVersion
        // events carry oldValue/newValue. Accept both spellings.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            oldState = try container.decodeIfPresent(String.self, forKey: .oldState)
                ?? container.decodeIfPresent(String.self, forKey: .oldValue)
            newState = try container.decodeIfPresent(String.self, forKey: .newState)
                ?? container.decodeIfPresent(String.self, forKey: .newValue)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(oldState, forKey: .oldState)
            try container.encodeIfPresent(newState, forKey: .newState)
        }
    }

    public struct Data: Codable, Sendable {
        public var type: String?
        public var id: String?
        public var version: Int?
        public var attributes: Attributes?
        public var relationships: Relationships?

        public init(
            type: String? = nil,
            id: String? = nil,
            version: Int? = nil,
            attributes: Attributes? = nil,
            relationships: Relationships? = nil
        ) {
            self.type = type
            self.id = id
            self.version = version
            self.attributes = attributes
            self.relationships = relationships
        }
    }

    public var data: Data?

    public init(data: Data? = nil) {
        self.data = data
    }
}

// MARK: - Convenience accessors

extension WebhookDeliveryPayload {

    /// The event type of the delivery, e.g. `buildUploadStateUpdated` or `webhookPingCreated`.
    /// Falls back to `"unknown"` when the payload carries no type.
    public var eventType: String {
        data?.type ?? "unknown"
    }

    /// The new state reported by a state-transition event, e.g. `COMPLETE` or `FAILED`.
    public var newState: String? {
        data?.attributes?.newState
    }

    /// The previous state reported by a state-transition event, e.g. `PROCESSING`.
    public var oldState: String? {
        data?.attributes?.oldState
    }

    /// The identifier of the resource instance the event relates to, e.g. a build upload ID.
    public var instanceId: String? {
        data?.relationships?.instance?.data?.id
    }

    /// Whether this delivery is a webhook ping.
    public var isPing: Bool {
        eventType == "webhookPingCreated"
    }
}
