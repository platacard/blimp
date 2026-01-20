import Foundation

/// Configuration for xcodebuild export options plist
/// See `xcodebuild -help` for full documentation of available options
public struct ExportOptions: Sendable, Encodable {

    /// Export method describing how Xcode should export the archive
    public enum Method: String, Sendable, Encodable {
        case appStoreConnect = "app-store-connect"
        case releaseTesting = "release-testing"
        case debugging = "debugging"
        case enterprise = "enterprise"
        case developerID = "developer-id"
        case macApplication = "mac-application"
        case validation = "validation"
    }

    /// Signing style for re-signing the app for distribution
    public enum SigningStyle: String, Sendable, Encodable {
        case manual
        case automatic
    }

    /// Signing certificate selector
    public enum SigningCertificate: RawRepresentable, Sendable, Equatable, Encodable {
        case appleDistribution
        case appleDevelopment
        case developerIDApplication
        case iOSDeveloper
        case iOSDistribution
        case macAppDistribution
        case macDeveloper
        case custom(String)

        public var rawValue: String {
            switch self {
            case .appleDistribution: "Apple Distribution"
            case .appleDevelopment: "Apple Development"
            case .developerIDApplication: "Developer ID Application"
            case .iOSDeveloper: "iOS Developer"
            case .iOSDistribution: "iOS Distribution"
            case .macAppDistribution: "Mac App Distribution"
            case .macDeveloper: "Mac Developer"
            case .custom(let value): value
            }
        }

        public init?(rawValue: String) {
            switch rawValue {
            case "Apple Distribution": self = .appleDistribution
            case "Apple Development": self = .appleDevelopment
            case "Developer ID Application": self = .developerIDApplication
            case "iOS Developer": self = .iOSDeveloper
            case "iOS Distribution": self = .iOSDistribution
            case "Mac App Distribution": self = .macAppDistribution
            case "Mac Developer": self = .macDeveloper
            default: self = .custom(rawValue)
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    /// Destination for export (local or upload)
    public enum Destination: String, Sendable, Encodable {
        case export
        case upload
    }

    // MARK: - Required Properties

    /// Describes how Xcode should export the archive
    public let method: Method

    // MARK: - Signing Properties

    /// The signing style to use when re-signing the app for distribution
    public let signingStyle: SigningStyle?

    /// Certificate name, SHA-1 hash, or automatic selector for signing
    public let signingCertificate: SigningCertificate?

    /// Provisioning profile mapping: bundle identifier -> profile name or UUID
    public let provisioningProfiles: [String: String]?

    /// The Developer team ID to use for this export
    public let teamID: String?

    // MARK: - App Store Connect Properties

    /// Should Xcode manage the app's build number when uploading to App Store Connect?
    public let manageAppVersionAndBuildNumber: Bool?

    /// When enabled, this build cannot be distributed via external TestFlight or the App Store
    public let testFlightInternalTestingOnly: Bool?

    /// For App Store exports, should the package include symbols?
    public let uploadSymbols: Bool?

    // MARK: - Export Behavior Properties

    /// Determines whether the app is exported locally or uploaded to Apple
    public let destination: Destination?

    /// Should symbols be stripped from Swift libraries in your IPA?
    public let stripSwiftSymbols: Bool?

    /// For non-App Store exports, thinning configuration
    public let thinning: String?

    /// iCloud container environment configuration
    public let iCloudContainerEnvironment: String?

    /// For non-App Store exports, embed on-demand resources asset packs in bundle
    public let embedOnDemandResourcesAssetPacksInBundle: Bool?

    /// For App Store exports, should Xcode generate App Store Information?
    public let generateAppStoreInformation: Bool?

    // MARK: - Initialization

    public init(
        method: Method,
        signingStyle: SigningStyle? = nil,
        signingCertificate: SigningCertificate? = nil,
        provisioningProfiles: [String: String]? = nil,
        teamID: String? = nil,
        manageAppVersionAndBuildNumber: Bool? = nil,
        testFlightInternalTestingOnly: Bool? = nil,
        uploadSymbols: Bool? = nil,
        destination: Destination? = nil,
        stripSwiftSymbols: Bool? = nil,
        thinning: String? = nil,
        iCloudContainerEnvironment: String? = nil,
        embedOnDemandResourcesAssetPacksInBundle: Bool? = nil,
        generateAppStoreInformation: Bool? = nil
    ) {
        self.method = method
        self.signingStyle = signingStyle
        self.signingCertificate = signingCertificate
        self.provisioningProfiles = provisioningProfiles
        self.teamID = teamID
        self.manageAppVersionAndBuildNumber = manageAppVersionAndBuildNumber
        self.testFlightInternalTestingOnly = testFlightInternalTestingOnly
        self.uploadSymbols = uploadSymbols
        self.destination = destination
        self.stripSwiftSymbols = stripSwiftSymbols
        self.thinning = thinning
        self.iCloudContainerEnvironment = iCloudContainerEnvironment
        self.embedOnDemandResourcesAssetPacksInBundle = embedOnDemandResourcesAssetPacksInBundle
        self.generateAppStoreInformation = generateAppStoreInformation
    }

    // MARK: - Plist Generation

    /// Generates plist data for the export options
    public func plistData() throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        return try encoder.encode(self)
    }

    /// Writes the export options plist to a file
    public func writePlist(to url: URL) throws {
        let data = try plistData()
        try data.write(to: url)
    }

}
