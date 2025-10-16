import Foundation

public protocol Transporter {
    /// Upload the resource with the selected transporter, typically IPA file
    func upload(arguments: [TransporterSetting], verbose: Bool) throws
}

public enum AuthOption {
    case apiKey(String)
    case apiIssuer(String)
}

public enum TransporterSetting {
    
    public enum Platform: String {
        case iOS = "ios"
        case macOS = "macos"
    }
    
    case validate
    case upload
    case appVersion(String)
    case buildNumber(String)
    case file(String)
    case platform(Platform)
    case maxUploadSpeed
    case showProgress
    case oldAltool
    case verbose
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
