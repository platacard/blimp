import Foundation

public protocol AppStoreConnectUploader: Sendable {
    /// Upload the resource with the selected transporter, typically IPA file
    @discardableResult
    func upload(config: UploadConfig, verbose: Bool) async throws -> UploadReceipt
}

/// Metadata about a completed binary upload.
public struct UploadReceipt: Sendable {
    /// The `buildUploads` resource id created for this upload, when the transporter
    /// goes through the App Store Connect API. Webhook `buildUploadStateUpdated`
    /// events reference this id in `relationships.instance.data.id`.
    public let uploadId: String?

    public init(uploadId: String?) {
        self.uploadId = uploadId
    }
}

public struct UploadConfig: Sendable {
    let bundleId: String
    let appVersion: String
    let buildNumber: String
    let filePath: String
    let platform: Platform

    public init(bundleId: String, appVersion: String, buildNumber: String, filePath: String, platform: Platform) {
        self.bundleId = bundleId
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.filePath = filePath
        self.platform = platform
    }
}

public enum Platform: String, Sendable {
    case iOS = "ios"
    case macOS = "macos"
    case visionOS = "visionos"
    case tvOS = "tvos"
}

public enum TransporterError: Error, CustomStringConvertible {
    case authRequired
    case toolError(any Error)

    public var description: String {
        switch self {
        case .authRequired:
            return "Auth failed"
        case let .toolError(error):
            return "Internal tool error: \(error.localizedDescription)"
        }
    }
}
