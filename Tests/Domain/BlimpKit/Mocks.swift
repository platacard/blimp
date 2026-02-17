import Foundation
import ProvisioningAPI
import TestflightAPI
import AppsAPI
import Uploader
import Gito
@testable import BlimpKit

// MARK: - Git Mock

actor MockGitRepo: GitManaging {
    var fileStore: [String: Data] = [:]
    var pushedCommits: [String] = []
    var cloneOrPullCalled = false
    private var remoteURL: String? = nil
    private let _localURL: URL

    nonisolated var localURL: URL {
        _localURL
    }

    init() {
        _localURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mock_git_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: _localURL, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: _localURL)
    }

    func cloneOrPull() throws {
        cloneOrPullCalled = true
    }

    func setRemote(url: String) throws {
        remoteURL = url
    }

    func hasRemote() -> Bool {
        return remoteURL != nil
    }

    func commitAndPush(message: String, push: Bool) throws {
        pushedCommits.append(message)
    }

    func fileExists(path: String) -> Bool {
        return fileStore[path] != nil
    }

    func readFile(path: String) throws -> Data {
        guard let data = fileStore[path] else {
            throw NSError(domain: "GitMock", code: 404, userInfo: nil)
        }
        return data
    }

    func writeFile(path: String, content: Data) throws {
        fileStore[path] = content
        // Also write to disk for file listing
        let fileURL = _localURL.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: fileURL)
    }
}

// MARK: - Certificate Generator Mock

class MockCertificateGenerator: CertificateGenerating, @unchecked Sendable {
    func generateCSR() throws -> (String, Data) {
        return ("CSR_CONTENT", "PRIVATE_KEY".data(using: .utf8)!)
    }

    func generateP12(certContent: Data, privateKey: Data, passphrase: String) throws -> Data {
        return "P12_CONTENT".data(using: .utf8)!
    }
}

// MARK: - Certificate Service Mock

class MockCertificateService: CertificateService, @unchecked Sendable {
    var certificates: [ProvisioningAPI.Certificate] = []
    var deletedCertificateIds: [String] = []

    func listCertificates(filterType: ProvisioningAPI.CertificateType?) async throws -> [ProvisioningAPI.Certificate] {
        if let filter = filterType {
            return certificates.filter { $0.type == filter }
        }
        return certificates
    }

    func createCertificate(csrContent: String, type: ProvisioningAPI.CertificateType) async throws -> ProvisioningAPI.Certificate {
        let cert = ProvisioningAPI.Certificate(
            id: UUID().uuidString,
            name: "Mock Cert",
            type: type,
            content: "CERT_CONTENT".data(using: .utf8),
            serialNumber: "123456"
        )
        certificates.append(cert)
        return cert
    }

    func deleteCertificate(id: String) async throws {
        deletedCertificateIds.append(id)
        certificates.removeAll { $0.id == id }
    }
}

// MARK: - Profile Service Mock

class MockProfileService: ProfileService, @unchecked Sendable {
    var bundleIds: [String: String] = [:]
    var profiles: [ProvisioningAPI.Profile] = []
    var deletedProfileIds: [String] = []

    func getBundleId(identifier: String) async throws -> String? {
        return bundleIds[identifier]
    }

    func createProfile(name: String, type: ProvisioningAPI.ProfileType, bundleId: String, certificateIds: [String], deviceIds: [String]?) async throws -> ProvisioningAPI.Profile {
        let profile = ProvisioningAPI.Profile(
            id: UUID().uuidString,
            name: name,
            type: type,
            content: "PROFILE_CONTENT".data(using: .utf8),
            expirationDate: Date().addingTimeInterval(3600)
        )
        profiles.append(profile)
        return profile
    }

    func listProfiles(name: String?) async throws -> [ProvisioningAPI.Profile] {
        if let name = name {
            return profiles.filter { $0.name == name }
        }
        return profiles
    }

    func deleteProfile(id: String) async throws {
        deletedProfileIds.append(id)
        profiles.removeAll { $0.id == id }
    }
}

// MARK: - Device Service Mock

class MockDeviceService: DeviceService, @unchecked Sendable {
    var devices: [ProvisioningAPI.Device] = []

    func registerDevice(name: String, udid: String, platform: ProvisioningAPI.Platform) async throws -> ProvisioningAPI.Device {
        let device = ProvisioningAPI.Device(id: UUID().uuidString, name: name, udid: udid, platform: platform, status: .enabled)
        devices.append(device)
        return device
    }

    func addDevice(name: String, udid: String, platform: ProvisioningAPI.Platform, status: ProvisioningAPI.Device.Status) {
        let device = ProvisioningAPI.Device(id: UUID().uuidString, name: name, udid: udid, platform: platform, status: status)
        devices.append(device)
    }

    func listDevices(platform: ProvisioningAPI.Platform?, status: ProvisioningAPI.Device.Status?) async throws -> [ProvisioningAPI.Device] {
        var filtered = devices
        if let platform {
            filtered = filtered.filter { $0.platform == platform }
        }
        if let status {
            filtered = filtered.filter { $0.status == status }
        }
        return filtered
    }
}

// MARK: - Build Query Service Mock

class MockBuildQueryService: BuildQueryService, @unchecked Sendable {
    var buildIdResponses: [String?] = []
    var processingResults: [TestflightAPI.BuildProcessingResult] = []
    var bundleSizes: [BundleBuildFileSize] = []
    var getBuildIDCallCount = 0
    var getProcessingResultCallCount = 0
    var errorToThrow: Error?

    func getBuildID(
        appId: String,
        appVersion: String,
        buildNumber: String,
        states: [TestflightAPI.ProcessingState],
        limit: Int,
        sorted: [TestflightAPI.BetaBuildSort]
    ) async throws -> String? {
        if let error = errorToThrow { throw error }
        let index = min(getBuildIDCallCount, buildIdResponses.count - 1)
        getBuildIDCallCount += 1
        return buildIdResponses.isEmpty ? nil : buildIdResponses[max(0, index)]
    }

    func getBuildProcessingResult(id: String) async throws -> TestflightAPI.BuildProcessingResult {
        if let error = errorToThrow { throw error }
        let index = min(getProcessingResultCallCount, processingResults.count - 1)
        getProcessingResultCallCount += 1
        return processingResults[max(0, index)]
    }

    func getBundleBuildSizes(buildBundleID: String, devices: [String]) async throws -> [BundleBuildFileSize] {
        if let error = errorToThrow { throw error }
        return bundleSizes
    }
}

// MARK: - Beta Management Service Mock

class MockBetaManagementService: BetaManagementService, @unchecked Sendable {
    var setBetaGroupsCalls: [(appId: String, buildId: String, betaGroups: [String])] = []
    var setChangelogCalls: [(localizationIds: [String], changelog: String)] = []
    var sendToReviewCalls: [String] = []
    var errorToThrow: Error?

    func setBetaGroups(appId: String, buildId: String, betaGroups: [String], isInternal: Bool) async throws {
        if let error = errorToThrow { throw error }
        setBetaGroupsCalls.append((appId, buildId, betaGroups))
    }

    func setChangelog(localizationIds: [String], changelog: String) async throws {
        if let error = errorToThrow { throw error }
        setChangelogCalls.append((localizationIds, changelog))
    }

    func sendToTestflightReview(buildId: String) async throws {
        if let error = errorToThrow { throw error }
        sendToReviewCalls.append(buildId)
    }
}

// MARK: - App Query Service Mock

class MockAppQueryService: AppQueryService, @unchecked Sendable {
    var appIds: [String: String] = [:]
    var errorToThrow: Error?

    func getAppId(bundleId: String) async throws -> String {
        if let error = errorToThrow { throw error }
        guard let appId = appIds[bundleId] else {
            throw NSError(domain: "MockAppQueryService", code: 404, userInfo: [NSLocalizedDescriptionKey: "App not found for bundle ID: \(bundleId)"])
        }
        return appId
    }
}

// MARK: - Uploader Mock

class MockUploader: AppStoreConnectUploader, @unchecked Sendable {
    var uploadCalls: [UploadConfig] = []
    var errorToThrow: Error?

    func upload(config: UploadConfig, verbose: Bool) async throws {
        if let error = errorToThrow { throw error }
        uploadCalls.append(config)
    }
}

