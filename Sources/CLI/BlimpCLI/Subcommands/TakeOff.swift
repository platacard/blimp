import Foundation
import BlimpKit
import ArgumentParser
import Cronista
import DeployHelpers

struct TakeOff: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "takeoff",
        abstract: "Archives the app for subsequent distribution"
    )

    // MARK: - Archive Options

    @Option(help: "Scheme name to archive/export")
    var scheme: String

    @Option(help: "Workspace file path")
    var workspace: String?

    @Option(help: "Xcode project file path (alternative to workspace)")
    var project: String?

    @Option(help: "Build configuration (Debug, Beta, Release, or custom)")
    var configuration: String = "Release"

    @Option(help: "Path to save the *.xcarchive")
    var archivePath: String = "build/Archives/app.xcarchive"

    @Option(help: "Path to export the ipa file to")
    var ipaPath: String = "build"

    // MARK: - Export Options (xcodebuild)

    @Option(help: "Export method: app-store-connect, release-testing, debugging, enterprise, developer-id")
    var method: String = "app-store-connect"

    @Option(help: "Signing style: manual or automatic")
    var signingStyle: String?

    @Option(help: "Signing certificate: 'Apple Distribution', 'Apple Development', or custom name")
    var signingCertificate: String?

    @Option(
        name: .customLong("provisioning-profile"),
        parsing: .upToNextOption,
        help: "Provisioning profile mapping (repeatable). Format: 'bundleId:profileName' or 'bundleId'"
    )
    var provisioningProfiles: [ProvisioningProfile] = []

    @Option(help: "Developer team ID")
    var teamID: String?

    @Flag(
        name: .customLong("manage-version"),
        help: "Let Xcode manage app version and build number"
    )
    var manageAppVersionAndBuildNumber = false

    @Flag(
        name: .customLong("internal-testing-only"),
        help: "Restrict build to internal TestFlight testing only"
    )
    var testFlightInternalTestingOnly = false

    @Flag(
        inversion: .prefixedNo,
        help: "Include symbols for App Store exports"
    )
    var uploadSymbols = true

    // MARK: - Legacy Option

    @Option(help: "Legacy: Export options plist path. Overrides individual export options if provided")
    var deployConfig: String?

    // MARK: - Flags

    @Flag(help: "Produce more output")
    var verbose = false

    private var logger: Cronista { Cronista(module: "blimp", category: "TakeOff") }

    func validate() throws {
        guard workspace != nil || project != nil else {
            throw ValidationError("Either --workspace or --project must be provided")
        }
        if workspace != nil && project != nil {
            throw ValidationError("Cannot specify both --workspace and --project")
        }
    }

    func run() async throws {
        let takeoff = Blimp.TakeOff()
        guard let buildConfiguration = Blimp.TakeOff.Configuration(rawValue: configuration) else {
            throw ValidationError("Invalid configuration: \(configuration)")
        }

        var archiveArgs: [Blimp.TakeOff.ArchiveArgument] = [
            .clean,
            .scheme(scheme),
            .archivePath(archivePath),
            .configuration(buildConfiguration),
            .destination(.anyIOSDevice),
            .cleanOutput
        ]

        if let workspace {
            archiveArgs.insert(.workspacePath(workspace), at: 1)
        } else if let project {
            archiveArgs.insert(.projectPath(project), at: 1)
        }

        logger.info("Archiving \(scheme)...")
        try takeoff.archive(arguments: archiveArgs, verbose: verbose)
        logger.info("Archive complete")

        logger.info("Exporting archive at \(archivePath)...")

        if let deployConfig {
            try takeoff.export(
                arguments: [
                    .exportArchive(archivePath),
                    .exportPath(ipaPath),
                    .optionsPlistPath(deployConfig)
                ],
                verbose: verbose
            )
        } else {
            let exportOptions = buildExportOptions()
            try takeoff.export(
                archivePath: archivePath,
                exportPath: ipaPath,
                options: exportOptions,
                verbose: verbose
            )
        }

        logger.info("Done! Exported IPA is at \(ipaPath)/\(scheme).ipa")
    }

    private func buildExportOptions() -> ExportOptions {
        let exportMethod = ExportOptions.Method(rawValue: method) ?? .appStoreConnect
        let style = signingStyle.flatMap { ExportOptions.SigningStyle(rawValue: $0) }
        let certificate = signingCertificate.flatMap { ExportOptions.SigningCertificate(rawValue: $0) }

        let profiles: [String: String]? = provisioningProfiles.isEmpty
            ? nil
            : Dictionary(uniqueKeysWithValues: provisioningProfiles.map { ($0.bundleId, $0.profileName) })

        return ExportOptions(
            method: exportMethod,
            signingStyle: style,
            signingCertificate: certificate,
            provisioningProfiles: profiles,
            teamID: teamID,
            manageAppVersionAndBuildNumber: manageAppVersionAndBuildNumber ? true : nil,
            testFlightInternalTestingOnly: testFlightInternalTestingOnly ? true : nil,
            uploadSymbols: uploadSymbols ? true : nil
        )
    }
}

// MARK: - ProvisioningProfile Type

/// A provisioning profile mapping parsed from CLI arguments
/// Format: "bundleId:profileName" or "bundleId" (uses bundleId as profile name)
struct ProvisioningProfile: ExpressibleByArgument, Sendable {
    let bundleId: String
    let profileName: String

    init?(argument: String) {
        let components = argument.split(separator: ":", maxSplits: 1)
        guard let first = components.first else { return nil }

        self.bundleId = String(first)

        if components.count > 1 {
            self.profileName = String(components[1])
        } else {
            self.profileName = self.bundleId
        }
    }
}
