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

// MARK: - Passphrase

func resolvePassphrase(_ cliValue: String?) throws -> String {
    // Environment variable first (CI-friendly)
    if let value = ProcessInfo.processInfo.environment["BLIMP_PASSPHRASE"] { return value }
    if let value = cliValue { return value }

    // Interactive fallback
    print("Enter passphrase: ", terminator: "")
    guard let pass = readSecureInput() else {
        throw ValidationError("Failed to read passphrase")
    }
    return pass
}

private func readSecureInput() -> String? {
    var oldTermios = termios()
    tcgetattr(STDIN_FILENO, &oldTermios)

    var newTermios = oldTermios
    newTermios.c_lflag &= ~UInt(ECHO)
    tcsetattr(STDIN_FILENO, TCSANOW, &newTermios)

    let result = readLine()

    tcsetattr(STDIN_FILENO, TCSANOW, &oldTermios)
    print()

    return result
}

// MARK: - Platform

extension ProvisioningAPI.Platform: ExpressibleByArgument {}

// MARK: - Profile Type

enum CLIProfileType: String, ExpressibleByArgument, CaseIterable {
    case development
    case appstore
    case adhoc
    case inhouse
    case direct

    func asAPI(platform: ProvisioningAPI.Platform) -> ProvisioningAPI.ProfileType {
        switch (platform, self) {
        case (.ios, .development): return .iosAppDevelopment
        case (.ios, .appstore): return .iosAppStore
        case (.ios, .adhoc): return .iosAppAdhoc
        case (.ios, .inhouse): return .iosAppInhouse
        case (.ios, .direct): return .iosAppAdhoc

        case (.macos, .development): return .macAppDevelopment
        case (.macos, .appstore): return .macAppStore
        case (.macos, .adhoc): return .macAppDirect
        case (.macos, .inhouse): return .macAppDirect
        case (.macos, .direct): return .macAppDirect

        case (.tvos, .development): return .tvosAppDevelopment
        case (.tvos, .appstore): return .tvosAppStore
        case (.tvos, .adhoc): return .tvosAppAdhoc
        case (.tvos, .inhouse): return .tvosAppInhouse
        case (.tvos, .direct): return .tvosAppAdhoc

        case (.catalyst, .development): return .macCatalystAppDevelopment
        case (.catalyst, .appstore): return .macCatalystAppStore
        case (.catalyst, .adhoc): return .macCatalystAppDirect
        case (.catalyst, .inhouse): return .macCatalystAppDirect
        case (.catalyst, .direct): return .macCatalystAppDirect
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
