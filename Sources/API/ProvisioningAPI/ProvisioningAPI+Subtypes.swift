import Foundation

public extension ProvisioningAPI {
    enum Platform: String, Sendable, CaseIterable {
        case ios = "ios"
        case macos = "macos"
        case tvos = "tvos"
        case catalyst = "catalyst"

        var asApiPlatform: Components.Schemas.BundleIdPlatform {
            switch self {
            case .ios, .tvos: .ios
            case .macos, .catalyst: .macOs
            }
        }

        var asDeviceFilterValue: String {
            switch self {
            case .ios: "IOS"
            case .macos: "MAC_OS"
            case .tvos, .catalyst: "UNIVERSAL"
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

        /// Universal certificates (Apple Distribution / Apple Development) work across all platforms.
        public var isUniversal: Bool {
            switch self {
            case .distribution, .development: true
            case .iosDevelopment, .iosDistribution, .macAppDevelopment, .macAppDistribution: false
            }
        }

        /// Returns the storage directory for this certificate type.
        /// Universal types omit the platform directory; platform-specific types include it.
        public func storageDirectory(for platform: Platform) -> String {
            if isUniversal {
                return "certificates/\(rawValue)"
            } else {
                return "certificates/\(platform.rawValue)/\(rawValue)"
            }
        }

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

        public enum Status: Sendable, Equatable {
            case enabled
            case disabled
            case processing
            case unknown(String)

            init(apiValue: String?) {
                switch apiValue {
                case "ENABLED": self = .enabled
                case "DISABLED": self = .disabled
                case "PROCESSING": self = .processing
                default: self = .unknown(apiValue ?? "")
                }
            }
        }

        public init(id: String, name: String, udid: String, platform: Platform?, status: Status) {
            self.id = id
            self.name = name
            self.udid = udid
            self.platform = platform
            self.status = status
        }
    }

    /// Outcome of `registerDevice`: a device registered by this call, or the
    /// device already registered under that UDID.
    enum DeviceRegistration: Sendable {
        case registered(Device)
        case alreadyRegistered(Device)

        public var device: Device {
            switch self {
            case .registered(let device), .alreadyRegistered(let device): device
            }
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
