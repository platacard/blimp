import Foundation
import OpenAPIRuntime
import OpenAPIURLSession
import JWTProvider
import Cronista
import Auth
import ClientTransport

/// Client for App Store Connect webhook management:
/// create/list/update/delete webhooks, send test pings, inspect and redeliver deliveries.
public struct WebhooksAPI: Sendable {

    private let jwtProvider: any JWTProviding
    private let client: any APIProtocol

    nonisolated(unsafe) private let logger: Cronista

    public init(jwtProvider: any JWTProviding) {
        self.jwtProvider = jwtProvider
        self.logger = Cronista(module: "Blimp", category: "WebhooksAPI")

        self.client = Client(
            serverURL: try! Servers.Server1.url(),
            configuration: .init(dateTranscoder: .iso8601WithFractionalSeconds),
            transport: RetryingURLSessionTransport(),
            middlewares: [
                AuthMiddleware { try jwtProvider.token() }
            ]
        )
    }

    /// Register a webhook for an app.
    /// - Returns: the created webhook, including its App Store Connect id
    public func createWebhook(
        appId: String,
        name: String,
        url: String,
        secret: String,
        eventTypes: [Event],
        enabled: Bool = true
    ) async throws -> Webhook {
        let response = try await client.webhooksCreateInstance(
            body: .json(.init(data: .init(
                _type: .webhooks,
                attributes: .init(
                    enabled: enabled,
                    eventTypes: try eventTypes.map { try $0.generated() },
                    name: name,
                    secret: secret,
                    url: url
                ),
                relationships: .init(app: .init(data: .init(_type: .apps, id: appId)))
            )))
        )

        let webhook = Webhook(schema: try response.created.body.json.data)
        logger.info("Created webhook \(webhook.id) for app \(appId)")
        return webhook
    }

    /// List webhooks registered for an app.
    public func listWebhooks(appId: String) async throws -> [Webhook] {
        let response = try await client.appsWebhooksGetToManyRelated(
            path: .init(id: appId),
            query: .init(limit: 200)
        )

        return try response.ok.body.json.data.map(Webhook.init(schema:))
    }

    /// Fetch a single webhook by id.
    public func getWebhook(id: String) async throws -> Webhook {
        let response = try await client.webhooksGetInstance(path: .init(id: id))
        return Webhook(schema: try response.ok.body.json.data)
    }

    /// Update a webhook. Only non-nil fields are changed.
    public func updateWebhook(
        id: String,
        name: String? = nil,
        url: String? = nil,
        secret: String? = nil,
        eventTypes: [Event]? = nil,
        enabled: Bool? = nil
    ) async throws -> Webhook {
        let response = try await client.webhooksUpdateInstance(
            path: .init(id: id),
            body: .json(.init(data: .init(
                _type: .webhooks,
                id: id,
                attributes: .init(
                    enabled: enabled,
                    eventTypes: try eventTypes.map { try $0.map { try $0.generated() } },
                    name: name,
                    secret: secret,
                    url: url
                )
            )))
        )

        let webhook = Webhook(schema: try response.ok.body.json.data)
        logger.info("Updated webhook \(webhook.id)")
        return webhook
    }

    /// Delete a webhook.
    public func deleteWebhook(id: String) async throws {
        let response = try await client.webhooksDeleteInstance(path: .init(id: id))
        _ = try response.noContent
        logger.info("Deleted webhook \(id)")
    }

    /// Send a test ping to the webhook's URL.
    /// The receiver gets a `webhookPingCreated` payload signed with the webhook secret.
    public func ping(webhookId: String) async throws {
        let response = try await client.webhookPingsCreateInstance(
            body: .json(.init(data: .init(
                _type: .webhookPings,
                relationships: .init(webhook: .init(data: .init(_type: .webhooks, id: webhookId)))
            )))
        )

        _ = try response.created
        logger.info("Sent ping to webhook \(webhookId)")
    }

    /// List recent deliveries of a webhook (for debugging and redelivery).
    public func listDeliveries(webhookId: String) async throws -> [Delivery] {
        let response = try await client.webhooksDeliveriesGetToManyRelated(
            path: .init(id: webhookId),
            query: .init(limit: 200)
        )

        return try response.ok.body.json.data.map(Delivery.init(schema:))
    }

    /// Ask App Store Connect to redeliver a previously failed delivery.
    public func redeliver(deliveryId: String) async throws {
        let response = try await client.webhookDeliveriesCreateInstance(
            body: .json(.init(data: .init(
                _type: .webhookDeliveries,
                relationships: .init(template: .init(data: .init(_type: .webhookDeliveries, id: deliveryId)))
            )))
        )

        _ = try response.created
        logger.info("Requested redelivery of \(deliveryId)")
    }
}

// MARK: - Public models

public extension WebhooksAPI {

    /// Webhook event types supported by App Store Connect.
    enum Event: String, CaseIterable, Sendable {
        case buildUploadStateUpdated = "BUILD_UPLOAD_STATE_UPDATED"
        case buildBetaDetailExternalBuildStateUpdated = "BUILD_BETA_DETAIL_EXTERNAL_BUILD_STATE_UPDATED"
        case betaFeedbackCrashSubmissionCreated = "BETA_FEEDBACK_CRASH_SUBMISSION_CREATED"
        case betaFeedbackScreenshotSubmissionCreated = "BETA_FEEDBACK_SCREENSHOT_SUBMISSION_CREATED"
        case appStoreVersionAppVersionStateUpdated = "APP_STORE_VERSION_APP_VERSION_STATE_UPDATED"
        case backgroundAssetVersionStateUpdated = "BACKGROUND_ASSET_VERSION_STATE_UPDATED"
        case backgroundAssetVersionAppStoreReleaseStateUpdated = "BACKGROUND_ASSET_VERSION_APP_STORE_RELEASE_STATE_UPDATED"
        case backgroundAssetVersionExternalBetaReleaseStateUpdated = "BACKGROUND_ASSET_VERSION_EXTERNAL_BETA_RELEASE_STATE_UPDATED"
        case backgroundAssetVersionInternalBetaReleaseCreated = "BACKGROUND_ASSET_VERSION_INTERNAL_BETA_RELEASE_CREATED"
        case alternativeDistributionPackageAvailableUpdated = "ALTERNATIVE_DISTRIBUTION_PACKAGE_AVAILABLE_UPDATED"
        case alternativeDistributionPackageVersionCreated = "ALTERNATIVE_DISTRIBUTION_PACKAGE_VERSION_CREATED"
        case alternativeDistributionTerritoryAvailabilityUpdated = "ALTERNATIVE_DISTRIBUTION_TERRITORY_AVAILABILITY_UPDATED"
    }

    /// A registered webhook.
    struct Webhook: Sendable {
        public let id: String
        public let name: String?
        public let url: String?
        public let enabled: Bool
        public let eventTypes: [Event]
        /// Raw event type strings as returned by App Store Connect, including
        /// values this library version does not model yet. Use this for
        /// desired-vs-actual comparisons.
        public let rawEventTypes: [String]
    }

    enum Error: Swift.Error, CustomStringConvertible {
        case unsupportedEventType(String)

        public var description: String {
            switch self {
            case let .unsupportedEventType(rawValue):
                return "Event type \(rawValue) is not supported by the generated App Store Connect spec"
            }
        }
    }

    /// A webhook delivery attempt.
    struct Delivery: Sendable {
        public enum State: String, Sendable {
            case succeeded
            case failed
            case pending
            case unknown
        }

        public let id: String
        public let state: State
        public let redelivery: Bool
        public let createdDate: Date?
        public let sentDate: Date?
        public let url: String?
        public let responseStatusCode: Int?
        public let errorMessage: String?
    }
}

// MARK: - Schema mapping

extension WebhooksAPI.Event {
    // Raw values are identical by construction; throwing here surfaces drift
    // between this enum and the generated spec instead of silently subscribing
    // to a different event.
    func generated() throws -> Components.Schemas.WebhookEventType {
        guard let mapped = Components.Schemas.WebhookEventType(rawValue: rawValue) else {
            throw WebhooksAPI.Error.unsupportedEventType(rawValue)
        }
        return mapped
    }
}

extension WebhooksAPI.Webhook {
    init(schema: Components.Schemas.Webhook) {
        let rawEventTypes = (schema.attributes?.eventTypes ?? []).map(\.rawValue)
        self.init(
            id: schema.id,
            name: schema.attributes?.name,
            url: schema.attributes?.url,
            enabled: schema.attributes?.enabled ?? false,
            eventTypes: rawEventTypes.compactMap { WebhooksAPI.Event(rawValue: $0) },
            rawEventTypes: rawEventTypes
        )
    }
}

private extension WebhooksAPI.Delivery {
    init(schema: Components.Schemas.WebhookDelivery) {
        self.init(
            id: schema.id,
            state: schema.attributes?.deliveryState.flatMap { State(rawValue: $0.rawValue.lowercased()) } ?? .unknown,
            redelivery: schema.attributes?.redelivery ?? false,
            createdDate: schema.attributes?.createdDate,
            sentDate: schema.attributes?.sentDate,
            url: schema.attributes?.request?.url,
            responseStatusCode: schema.attributes?.response?.httpStatusCode,
            errorMessage: schema.attributes?.errorMessage
        )
    }
}
