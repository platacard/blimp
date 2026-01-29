import ArgumentParser
import BlimpKit
import Darwin
import Foundation
import JWTProvider
import ProvisioningAPI

// MARK: - Maintenance

extension Blimp.Maintenance {
    static let `default` = Blimp.Maintenance(jwtProvider: DefaultJWTProvider())
}

// MARK: - Platform

extension ProvisioningAPI.Platform: ExpressibleByArgument {}

// MARK: - Profile Type

enum CLIProfileType: String, ExpressibleByArgument, CaseIterable {
    case development
    case appstore
    case adhoc

    func asAPI(platform: ProvisioningAPI.Platform) -> ProvisioningAPI.ProfileType {
        switch (platform, self) {
        case (.ios, .development): return .iosAppDevelopment
        case (.ios, .appstore): return .iosAppStore
        case (.ios, .adhoc): return .iosAppAdhoc

        case (.macos, .development): return .macAppDevelopment
        case (.macos, .appstore): return .macAppStore
        case (.macos, .adhoc): return .macAppDirect

        case (.tvos, .development): return .tvosAppDevelopment
        case (.tvos, .appstore): return .tvosAppStore
        case (.tvos, .adhoc): return .tvosAppAdhoc

        case (.catalyst, .development): return .macCatalystAppDevelopment
        case (.catalyst, .appstore): return .macCatalystAppStore
        case (.catalyst, .adhoc): return .macCatalystAppDirect
        }
    }
}

// MARK: - Certificate Type

extension ProvisioningAPI.CertificateType: ExpressibleByArgument {
    public init?(argument: String) {
        switch argument.lowercased() {
        case "development", "dev": self = .development
        case "distribution", "dist": self = .distribution
        default: return nil
        }
    }
}
