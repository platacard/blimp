import Foundation
import Cronista
import ProvisioningAPI
import Gito
import Corredor

/// Protocol for executing shell commands. Enables testing without actual shell execution.
public protocol ShellExecuting: Sendable {
    func run(arguments: [String]) throws -> String
}

/// Default implementation using Corredor Shell.
public struct DefaultShellExecutor: ShellExecuting {
    public init() {}

    public func run(arguments: [String]) throws -> String {
        try Shell.arguments(arguments).run()
    }
}

/// Result of installing a provisioning profile.
public struct InstalledProfile: Sendable {
    public let bundleId: String
    public let uuid: String
    public let destinationPath: String
    public let platform: ProvisioningAPI.Platform
    public let type: ProvisioningAPI.ProfileType

    public init(bundleId: String, uuid: String, destinationPath: String, platform: ProvisioningAPI.Platform, type: ProvisioningAPI.ProfileType) {
        self.bundleId = bundleId
        self.uuid = uuid
        self.destinationPath = destinationPath
        self.platform = platform
        self.type = type
    }
}

/// Installs provisioning profiles from Git storage to the system.
public struct ProfileInstaller: Sendable {
    private let git: any GitManaging
    private let shell: any ShellExecuting
    private let systemProfilesDirectory: URL

    nonisolated(unsafe) private let logger = Cronista(module: "blimp", category: "ProfileInstaller")

    public init(
        git: any GitManaging,
        shell: any ShellExecuting = DefaultShellExecutor(),
        systemProfilesDirectory: URL = Self.defaultSystemProfilesDirectory
    ) {
        self.git = git
        self.shell = shell
        self.systemProfilesDirectory = systemProfilesDirectory
    }

    public static var defaultSystemProfilesDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/MobileDevice/Provisioning Profiles")
    }

    /// Installs profiles from Git storage to the system.
    public func installProfiles(
        platform: ProvisioningAPI.Platform,
        type: ProvisioningAPI.ProfileType,
        bundleIdPattern: String? = nil
    ) async throws -> [InstalledProfile] {
        logger.info("Installing profiles for \(platform.rawValue)/\(type.rawValue)")

        try await git.cloneOrPull()

        let profileDir = "profiles/\(platform.rawValue)/\(type.rawValue)"
        let profileFiles = try listProfileFiles(in: profileDir)

        if profileFiles.isEmpty {
            logger.info("No profiles found in \(profileDir)")
            return []
        }

        logger.info("Found \(profileFiles.count) profile(s) in storage")

        var installed: [InstalledProfile] = []

        for fileName in profileFiles {
            let bundleId = extractBundleId(from: fileName)

            if let pattern = bundleIdPattern, !matchesPattern(bundleId: bundleId, pattern: pattern) {
                continue
            }

            let filePath = "\(profileDir)/\(fileName)"

            do {
                let result = try await installProfile(
                    filePath: filePath,
                    bundleId: bundleId,
                    platform: platform,
                    type: type
                )
                installed.append(result)
                logger.info("Installed: \(bundleId) -> \(result.uuid)")
            } catch {
                logger.error("Failed to install \(bundleId): \(error.localizedDescription)")
                throw error
            }
        }

        logger.info("Installed \(installed.count) profile(s)")
        return installed
    }

    // MARK: - Private

    private func installProfile(
        filePath: String,
        bundleId: String,
        platform: ProvisioningAPI.Platform,
        type: ProvisioningAPI.ProfileType
    ) async throws -> InstalledProfile {
        let profileData = try await git.readFile(path: filePath)
        let uuid = try extractUUID(from: profileData)

        let destinationPath = systemProfilesDirectory
            .appendingPathComponent("\(uuid).mobileprovision")
            .path

        try ensureDirectoryExists(systemProfilesDirectory)
        try profileData.write(to: URL(fileURLWithPath: destinationPath))

        return InstalledProfile(
            bundleId: bundleId,
            uuid: uuid,
            destinationPath: destinationPath,
            platform: platform,
            type: type
        )
    }

    /// Extracts UUID from a provisioning profile using `security cms -D`
    private func extractUUID(from profileData: Data) throws -> String {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("\(UUID().uuidString).mobileprovision")

        defer {
            try? FileManager.default.removeItem(at: tempFile)
        }

        try profileData.write(to: tempFile)

        let output = try shell.run(arguments: ["security", "cms", "-D", "-i", tempFile.path])

        guard let plistData = output.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let uuid = plist["UUID"] as? String else {
            throw Error.invalidProfile("Could not extract UUID from profile")
        }

        return uuid
    }

    private func listProfileFiles(in directory: String) throws -> [String] {
        let dirURL = git.localURL.appendingPathComponent(directory)
        guard FileManager.default.fileExists(atPath: dirURL.path) else {
            return []
        }

        let contents = try FileManager.default.contentsOfDirectory(atPath: dirURL.path)
        return contents.filter { $0.hasSuffix(".mobileprovision") }
    }

    private func extractBundleId(from fileName: String) -> String {
        fileName.replacingOccurrences(of: ".mobileprovision", with: "")
    }

    private func matchesPattern(bundleId: String, pattern: String) -> Bool {
        if pattern.contains("*") {
            let regexPattern = "^" + pattern
                .replacingOccurrences(of: ".", with: "\\.")
                .replacingOccurrences(of: "*", with: ".*") + "$"
            return (try? bundleId.range(of: regexPattern, options: .regularExpression)) != nil
        }
        return bundleId == pattern
    }

    private func ensureDirectoryExists(_ url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    public enum Error: Swift.Error, LocalizedError {
        case invalidProfile(String)
        case profileNotFound(String)
        case installationFailed(String)

        public var errorDescription: String? {
            switch self {
            case .invalidProfile(let msg): return msg
            case .profileNotFound(let msg): return msg
            case .installationFailed(let msg): return msg
            }
        }
    }
}
