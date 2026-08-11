import Foundation
import Cronista
import ProvisioningAPI
import Gito

/// Provides the Apple WWDR intermediate certificate. Enables testing without network access.
public protocol WWDRCertificateProviding: Sendable {
    func fetch() async throws -> Data
}

/// Downloads the WWDR G3 intermediate certificate from Apple.
public struct URLWWDRCertificateProvider: WWDRCertificateProviding {
    public static let certificateURL = URL(string: "https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer")!

    public init() {}

    public func fetch() async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: Self.certificateURL)

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return data
    }
}

/// Result of installing a certificate into a keychain.
public struct InstalledCertificate: Sendable {
    public let certificateId: String
    public let type: ProvisioningAPI.CertificateType
    public let keychainPath: String

    public init(certificateId: String, type: ProvisioningAPI.CertificateType, keychainPath: String) {
        self.certificateId = certificateId
        self.type = type
        self.keychainPath = keychainPath
    }
}

/// Installs signing certificates from Git storage into a macOS keychain.
///
/// Reads password-protected `.p12` files from the certificate storage directory
/// (`certificates/<TYPE>/` for universal types, `certificates/<platform>/<TYPE>/` otherwise)
/// and imports them via `security import` with codesign access. Files additionally
/// encrypted at rest (OpenSSL `Salted__` header) are decrypted with the same passphrase first.
public struct CertificateInstaller: Sendable {

    public enum Keychain: Sendable {
        case login
        case path(String)

        var resolvedPath: String {
            switch self {
            case .login:
                return FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Keychains/login.keychain-db").path
            case .path(let path):
                return (path as NSString).expandingTildeInPath
            }
        }
    }

    private let git: any GitManaging
    private let shell: any ShellExecuting
    private let encrypter: any EncryptionService
    private let wwdrProvider: any WWDRCertificateProviding

    nonisolated(unsafe) private let logger = Cronista(module: "blimp", category: "CertificateInstaller")

    public init(
        git: any GitManaging,
        shell: any ShellExecuting = DefaultShellExecutor(),
        encrypter: any EncryptionService = FileEncrypter(),
        wwdrProvider: any WWDRCertificateProviding = URLWWDRCertificateProvider()
    ) {
        self.git = git
        self.shell = shell
        self.encrypter = encrypter
        self.wwdrProvider = wwdrProvider
    }

    /// Convenience initializer over a local Git storage clone.
    public init(storagePath: String) {
        self.init(git: GitStorage(localPath: storagePath))
    }

    /// Installs all stored certificates of the given type into the keychain.
    /// - Parameters:
    ///   - passphrase: Storage passphrase, used both to decrypt the stored file and as the p12 import password.
    ///   - keychainPassword: When provided, runs `security set-key-partition-list` so codesign
    ///     can use the keys without a UI prompt.
    public func installCertificates(
        platform: ProvisioningAPI.Platform,
        type: ProvisioningAPI.CertificateType,
        passphrase: String,
        keychain: Keychain = .login,
        keychainPassword: String? = nil,
        installWWDR: Bool = true
    ) async throws -> [InstalledCertificate] {
        logger.info("Installing certificates for \(platform.rawValue)/\(type.rawValue)")

        try await git.cloneOrPull()

        let keychainPath = keychain.resolvedPath

        if installWWDR {
            try await ensureWWDRCertificate(keychainPath: keychainPath)
        }

        let certDir = type.storageDirectory(for: platform)
        let certFiles = try listCertificateFiles(in: certDir)

        guard !certFiles.isEmpty else {
            throw Error.noCertificatesFound("No .p12 files found in \(certDir)")
        }

        logger.info("Found \(certFiles.count) certificate(s) in storage")

        var installed: [InstalledCertificate] = []

        for fileName in certFiles {
            let certificateId = (fileName as NSString).deletingPathExtension
            let storedData = try await git.readFile(path: "\(certDir)/\(fileName)")
            let p12Data = FileEncrypter.isEncrypted(storedData)
                ? try encrypter.decrypt(data: storedData, password: passphrase)
                : storedData

            try importP12(p12Data, passphrase: passphrase, keychainPath: keychainPath)

            installed.append(InstalledCertificate(certificateId: certificateId, type: type, keychainPath: keychainPath))
            logger.info("Imported certificate \(certificateId)")
        }

        if let keychainPassword {
            try allowCodesignAccess(keychainPath: keychainPath, keychainPassword: keychainPassword)
        }

        logger.info("Installed \(installed.count) certificate(s)")
        return installed
    }

    // MARK: - Private

    private func ensureWWDRCertificate(keychainPath: String) async throws {
        let findResult = try? shell.run(arguments: [
            "security", "find-certificate", "-c", "Apple Worldwide Developer Relations", keychainPath
        ])

        if findResult != nil {
            logger.info("WWDR certificate already present")
            return
        }

        logger.info("Fetching WWDR intermediate certificate")

        let data: Data
        do {
            data = try await wwdrProvider.fetch()
        } catch {
            throw Error.wwdrUnavailable("Could not fetch the WWDR certificate: \(error.localizedDescription)")
        }

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).cer")

        defer {
            try? FileManager.default.removeItem(at: tempFile)
        }

        try data.write(to: tempFile)
        _ = try shell.run(arguments: ["security", "import", tempFile.path, "-k", keychainPath])
    }

    private func importP12(_ p12Data: Data, passphrase: String, keychainPath: String) throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).p12")

        defer {
            try? FileManager.default.removeItem(at: tempFile)
        }

        let created = FileManager.default.createFile(
            atPath: tempFile.path,
            contents: p12Data,
            attributes: [.posixPermissions: 0o600]
        )
        guard created else {
            throw Error.importFailed("Could not write temporary p12 file")
        }

        _ = try shell.run(arguments: [
            "security", "import", tempFile.path,
            "-k", keychainPath,
            "-P", passphrase,
            "-T", "/usr/bin/codesign"
        ])
    }

    private func allowCodesignAccess(keychainPath: String, keychainPassword: String) throws {
        _ = try shell.run(arguments: [
            "security", "set-key-partition-list",
            "-S", "apple-tool:,apple:,codesign:",
            "-s",
            "-k", keychainPassword,
            keychainPath
        ])
    }

    private func listCertificateFiles(in directory: String) throws -> [String] {
        let dirURL = git.localURL.appendingPathComponent(directory)
        guard FileManager.default.fileExists(atPath: dirURL.path) else {
            return []
        }

        let contents = try FileManager.default.contentsOfDirectory(atPath: dirURL.path)
        return contents.filter { $0.hasSuffix(".p12") }.sorted()
    }

    public enum Error: Swift.Error, LocalizedError {
        case noCertificatesFound(String)
        case wwdrUnavailable(String)
        case importFailed(String)

        public var errorDescription: String? {
            switch self {
            case .noCertificatesFound(let msg): return msg
            case .wwdrUnavailable(let msg): return msg
            case .importFailed(let msg): return msg
            }
        }
    }
}
