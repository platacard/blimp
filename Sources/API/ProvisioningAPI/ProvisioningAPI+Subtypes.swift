import Foundation

public extension ProvisioningAPI {
    enum Platform: String, Sendable, CaseIterable {
        case iOS = "iOS"
        case macOS = "macOS"
        case tvOS = "tvOS"
        case catalyst = "catalyst"

        public var displayName: String {
            switch self {
            case .iOS: return "iOS"
            case .macOS: return "macOS"
            case .tvOS: return "tvOS"
            case .catalyst: return "Mac Catalyst"
            }
        }

        var asApiPlatform: Components.Schemas.BundleIdPlatform {
            switch self {
            case .iOS: .ios
            case .macOS: .macOs
            case .tvOS, .catalyst: .universal
            }
        }

        var asDeviceFilterPlatform: Operations.DevicesGetCollection.Input.Query.FilterLbrackPlatformRbrackPayloadPayload {
            switch self {
            case .iOS: .ios
            case .macOS: .macOs
            case .tvOS, .catalyst: .universal
            }
        }
    }

    enum ProfileType: String, Sendable, CaseIterable {
        case iosAppDevelopment = "IOS_APP_DEVELOPMENT"
        case iosAppStore = "IOS_APP_STORE"
        case iosAppAdhoc = "IOS_APP_ADHOC"
        case iosAppInhouse = "IOS_APP_INHOUSE"
        case macAppDevelopment = "MAC_APP_DEVELOPMENT"
        case macAppStore = "MAC_APP_STORE"
        case macAppDirect = "MAC_APP_DIRECT"
        case tvosAppDevelopment = "TVOS_APP_DEVELOPMENT"
        case tvosAppStore = "TVOS_APP_STORE"
        case tvosAppAdhoc = "TVOS_APP_ADHOC"
        case tvosAppInhouse = "TVOS_APP_INHOUSE"
        case macCatalystAppDevelopment = "MAC_CATALYST_APP_DEVELOPMENT"
        case macCatalystAppStore = "MAC_CATALYST_APP_STORE"
        case macCatalystAppDirect = "MAC_CATALYST_APP_DIRECT"
        
        var asApiType: Components.Schemas.ProfileCreateRequest.DataPayload.AttributesPayload.ProfileTypePayload {
            return .init(rawValue: self.rawValue)!
        }
    }
    
    enum CertificateType: String, Sendable, CaseIterable {
        case iosDevelopment = "IOS_DEVELOPMENT"
        case iosDistribution = "IOS_DISTRIBUTION"
        case macAppDevelopment = "MAC_APP_DEVELOPMENT"
        case macAppDistribution = "MAC_APP_DISTRIBUTION"
        case distribution = "DISTRIBUTION"
        case development = "DEVELOPMENT"
        
        var asApiType: Components.Schemas.CertificateType {
            return .init(rawValue: self.rawValue)!
        }
        
        var asFilterType: Operations.CertificatesGetCollection.Input.Query.FilterLbrackCertificateTypeRbrackPayloadPayload {
            return .init(rawValue: self.rawValue)!
        }
    }
    
    struct Device: Sendable {
        public let id: String
        public let name: String
        public let udid: String
        public let platform: Platform?
        public let status: Status

        public enum Status: String, Sendable {
            case enabled = "ENABLED"
            case disabled = "DISABLED"
        }

        public init(id: String, name: String, udid: String, platform: Platform?, status: Status) {
            self.id = id
            self.name = name
            self.udid = udid
            self.platform = platform
            self.status = status
        }
    }

    struct Certificate: Sendable {
        public let id: String
        public let name: String
        public let type: CertificateType?
        public let content: Data?
        public let serialNumber: String?

        public init(id: String, name: String, type: CertificateType?, content: Data?, serialNumber: String?) {
            self.id = id
            self.name = name
            self.type = type
            self.content = content
            self.serialNumber = serialNumber
        }
    }

    struct Profile: Sendable {
        public let id: String
        public let name: String
        public let type: ProfileType?
        public let content: Data?
        public let expirationDate: Date?

        public init(id: String, name: String, type: ProfileType?, content: Data?, expirationDate: Date?) {
            self.id = id
            self.name = name
            self.type = type
            self.content = content
            self.expirationDate = expirationDate
        }
    }
}
