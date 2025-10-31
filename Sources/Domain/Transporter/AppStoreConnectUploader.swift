import Foundation

public protocol AppStoreConnectUploader {
    /// Upload the resource with the selected transporter, typically IPA file
    func upload(config: UploadConfig, verbose: Bool) async throws
}

public enum AuthOption {
    case apiKey(String)
    case apiIssuer(String)
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
