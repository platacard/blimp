import XCTest
import Foundation
import ProvisioningAPI
import Gito
@testable import BlimpKit

final class ProfileInstallerTests: XCTestCase {
    var mockGit: MockGitRepo!
    var mockShell: MockShellExecutor!
    var tempDir: URL!
    var installer: ProfileInstaller!

    override func setUp() async throws {
        try await super.setUp()
        mockGit = MockGitRepo()
        mockShell = MockShellExecutor()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        installer = ProfileInstaller(
            git: mockGit,
            shell: mockShell,
            systemProfilesDirectory: tempDir
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        await mockGit.cleanup()
        try await super.tearDown()
    }

    // MARK: - UUID Extraction

    func testInstallProfileExtractsUUIDAndCopies() async throws {
        let bundleId = "com.example.app"
        let uuid = "12345678-1234-1234-1234-123456789abc"
        let profilePath = "profiles/ios/IOS_APP_DEVELOPMENT/\(bundleId).mobileprovision"

        let profileData = "<?xml version=\"1.0\"?>fake profile".data(using: .utf8)!
        try await mockGit.writeFile(path: profilePath, content: profileData)

        mockShell.outputForCommand = { _ in
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>UUID</key>
                <string>\(uuid)</string>
                <key>Name</key>
                <string>Test Profile</string>
            </dict>
            </plist>
            """
        }

        let installed = try await installer.installProfiles(
            platform: .ios,
            type: .iosAppDevelopment
        )

        XCTAssertEqual(installed.count, 1)
        XCTAssertEqual(installed.first?.bundleId, bundleId)
        XCTAssertEqual(installed.first?.uuid, uuid)

        let expectedPath = tempDir.appendingPathComponent("\(uuid).mobileprovision")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedPath.path))
    }

    // MARK: - Bundle ID Filtering

    func testInstallProfileFiltersByExactBundleId() async throws {
        let profiles = [
            "com.example.app",
            "com.example.app.widget",
            "com.other.app"
        ]

        for bundleId in profiles {
            let path = "profiles/ios/IOS_APP_DEVELOPMENT/\(bundleId).mobileprovision"
            let data = "<?xml version=\"1.0\"?>fake".data(using: .utf8)!
            try await mockGit.writeFile(path: path, content: data)
        }

        var uuidCounter = 0
        mockShell.outputForCommand = { _ in
            uuidCounter += 1
            return """
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0">
            <dict>
                <key>UUID</key>
                <string>uuid-\(uuidCounter)</string>
            </dict>
            </plist>
            """
        }

        let installed = try await installer.installProfiles(
            platform: .ios,
            type: .iosAppDevelopment,
            bundleIdPattern: "com.example.app"
        )

        XCTAssertEqual(installed.count, 1)
        XCTAssertEqual(installed.first?.bundleId, "com.example.app")
    }

    func testInstallProfileFiltersByGlobPattern() async throws {
        let profiles = [
            "com.example.app",
            "com.example.app.widget",
            "com.other.app"
        ]

        for bundleId in profiles {
            let path = "profiles/ios/IOS_APP_DEVELOPMENT/\(bundleId).mobileprovision"
            let data = "<?xml version=\"1.0\"?>fake".data(using: .utf8)!
            try await mockGit.writeFile(path: path, content: data)
        }

        var uuidCounter = 0
        mockShell.outputForCommand = { _ in
            uuidCounter += 1
            return """
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0">
            <dict>
                <key>UUID</key>
                <string>uuid-\(uuidCounter)</string>
            </dict>
            </plist>
            """
        }

        let installed = try await installer.installProfiles(
            platform: .ios,
            type: .iosAppDevelopment,
            bundleIdPattern: "com.example.*"
        )

        XCTAssertEqual(installed.count, 2)
        XCTAssertTrue(installed.allSatisfy { $0.bundleId.hasPrefix("com.example") })
    }

    // MARK: - Edge Cases

    func testInstallProfileHandlesEmptyDirectory() async throws {
        let installed = try await installer.installProfiles(
            platform: .ios,
            type: .iosAppDevelopment
        )

        XCTAssertTrue(installed.isEmpty)
    }

    func testInstallProfileThrowsOnInvalidPlist() async throws {
        let bundleId = "com.example.app"
        let profilePath = "profiles/ios/IOS_APP_DEVELOPMENT/\(bundleId).mobileprovision"

        let profileData = "<?xml version=\"1.0\"?>fake".data(using: .utf8)!
        try await mockGit.writeFile(path: profilePath, content: profileData)

        mockShell.outputForCommand = { _ in "invalid output not plist" }

        do {
            _ = try await installer.installProfiles(
                platform: .ios,
                type: .iosAppDevelopment
            )
            XCTFail("Should throw error for invalid profile")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("UUID"))
        }
    }

    func testInstallProfileCreatesDirectoryIfNeeded() async throws {
        let bundleId = "com.example.app"
        let uuid = "12345678-1234-1234-1234-123456789abc"
        let profilePath = "profiles/ios/IOS_APP_DEVELOPMENT/\(bundleId).mobileprovision"

        let newTempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        installer = ProfileInstaller(
            git: mockGit,
            shell: mockShell,
            systemProfilesDirectory: newTempDir
        )

        let profileData = "<?xml version=\"1.0\"?>fake".data(using: .utf8)!
        try await mockGit.writeFile(path: profilePath, content: profileData)

        mockShell.outputForCommand = { _ in
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0">
            <dict>
                <key>UUID</key>
                <string>\(uuid)</string>
            </dict>
            </plist>
            """
        }

        let installed = try await installer.installProfiles(
            platform: .ios,
            type: .iosAppDevelopment
        )

        XCTAssertEqual(installed.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: newTempDir.path))

        try? FileManager.default.removeItem(at: newTempDir)
    }

    func testInstallProfileCallsSecurityCmsCommand() async throws {
        let bundleId = "com.example.app"
        let profilePath = "profiles/ios/IOS_APP_DEVELOPMENT/\(bundleId).mobileprovision"

        let profileData = "<?xml version=\"1.0\"?>fake".data(using: .utf8)!
        try await mockGit.writeFile(path: profilePath, content: profileData)

        mockShell.outputForCommand = { _ in
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0">
            <dict>
                <key>UUID</key>
                <string>test-uuid</string>
            </dict>
            </plist>
            """
        }

        _ = try await installer.installProfiles(
            platform: .ios,
            type: .iosAppDevelopment
        )

        XCTAssertEqual(mockShell.executedCommands.count, 1)
        let command = mockShell.executedCommands.first!
        XCTAssertTrue(command.contains("security"))
        XCTAssertTrue(command.contains("cms"))
        XCTAssertTrue(command.contains("-D"))
        XCTAssertTrue(command.contains("-i"))
    }
}

// MARK: - Mock Shell Executor

class MockShellExecutor: ShellExecuting, @unchecked Sendable {
    var outputForCommand: ((String) -> String)?
    var executedCommands: [String] = []

    func run(arguments: [String]) throws -> String {
        let command = arguments.joined(separator: " ")
        executedCommands.append(command)
        return outputForCommand?(command) ?? ""
    }
}
