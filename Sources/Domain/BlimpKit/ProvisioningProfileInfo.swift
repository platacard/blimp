import Foundation
import ProvisioningAPI

/// Parsed metadata of a `.mobileprovision` file.
public struct ProvisioningProfileInfo: Sendable {
    public let uuid: String
    public let name: String
    public let teamId: String
    /// Application identifier without the team ID prefix. May be `*` for wildcard profiles.
    public let bundleId: String
    public let creationDate: Date
    public let expirationDate: Date
    public let profileClass: ProfileClass

    public enum ProfileClass: String, Sendable {
        case development
        case adhoc
        case appstore
        case enterprise
    }

    /// Decodes the CMS envelope via `security cms -D` and parses the embedded plist.
    public init(profileData: Data, shell: any ShellExecuting = DefaultShellExecutor()) throws {
        try self.init(plist: Self.decodePlist(profileData: profileData, shell: shell))
    }

    /// Decodes a profile's CMS envelope via `security cms -D` into its plist dictionary.
    public static func decodePlist(profileData: Data, shell: any ShellExecuting = DefaultShellExecutor()) throws -> [String: Any] {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).mobileprovision")

        defer {
            try? FileManager.default.removeItem(at: tempFile)
        }

        let created = FileManager.default.createFile(
            atPath: tempFile.path,
            contents: profileData,
            attributes: [.posixPermissions: 0o600]
        )
        guard created else {
            throw Error.invalidProfile("Could not write temporary profile file")
        }

        let output = try shell.run(arguments: ["security", "cms", "-D", "-i", tempFile.path])

        guard let plistData = output.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            throw Error.invalidProfile("Could not decode profile plist")
        }

        return plist
    }

    public init(plist: [String: Any]) throws {
        guard let uuid = plist["UUID"] as? String else {
            throw Error.missingKey("UUID")
        }
        guard let name = plist["Name"] as? String else {
            throw Error.missingKey("Name")
        }
        guard let creationDate = plist["CreationDate"] as? Date else {
            throw Error.missingKey("CreationDate")
        }
        guard let expirationDate = plist["ExpirationDate"] as? Date else {
            throw Error.missingKey("ExpirationDate")
        }

        let entitlements = plist["Entitlements"] as? [String: Any] ?? [:]

        guard let teamId = (plist["TeamIdentifier"] as? [String])?.first
                ?? entitlements["com.apple.developer.team-identifier"] as? String else {
            throw Error.missingKey("TeamIdentifier")
        }
        guard let applicationIdentifier = entitlements["application-identifier"] as? String else {
            throw Error.missingKey("Entitlements.application-identifier")
        }

        self.uuid = uuid
        self.name = name
        self.teamId = teamId
        self.bundleId = applicationIdentifier.hasPrefix("\(teamId).")
            ? String(applicationIdentifier.dropFirst(teamId.count + 1))
            : applicationIdentifier
        self.creationDate = creationDate
        self.expirationDate = expirationDate

        if plist["ProvisionsAllDevices"] as? Bool == true {
            self.profileClass = .enterprise
        } else if plist["ProvisionedDevices"] != nil {
            self.profileClass = entitlements["get-task-allow"] as? Bool == true ? .development : .adhoc
        } else {
            self.profileClass = .appstore
        }
    }

    public enum Error: Swift.Error, LocalizedError {
        case invalidProfile(String)
        case missingKey(String)

        public var errorDescription: String? {
            switch self {
            case .invalidProfile(let msg): return msg
            case .missingKey(let key): return "Profile plist is missing required key: \(key)"
            }
        }
    }
}
