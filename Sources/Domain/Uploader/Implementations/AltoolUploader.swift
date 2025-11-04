import Foundation
import Corredor
import Cronista
import ASCCredentials
import RegexBuilder
import sys_wait

@available(*, deprecated, message: "Use AppStoreConnectAPIUploader")
public struct AltoolUploader: ASCCredentialsTrait {
    
    private enum Argument: String, BashArgument {
        case verbose

        var bashArgument: String {
            rawValue
        }
    }

    private var logger: Cronista { Cronista(module: "blimp", category: "TakeOff", isFileLoggingEnabled: true) }

    public init() {}
    
    public func upload(arguments: [TransporterSetting], verbose: Bool) throws {
        guard let apiKeyId, let apiIssuerId, let apiPrivateKey else {
            throw TransporterError.authRequired
        }

        let extraArguments: [Argument] = (verbose ? [.verbose] : []) + []

        do {
            let output = try Shell.command(
                "set -o pipefail && xcrun altool",
                arguments: arguments + [
                    AuthOption.apiKey(apiKeyId),
                    AuthOption.apiIssuer(apiIssuerId),
                    AuthOption.apiPrivateKey(apiPrivateKey)
                ] + extraArguments
            )
            .run()

            guard verbose else { return }
            makeFilteredLog(output)
        } catch {
            logger.warning("Uploading failed with \(error.localizedDescription). Try proceed.")
            throw TransporterError.toolError(error)
        }
    }
}

// MARK: - Subtype Extensions

extension AltoolUploader.AuthOption: BashArgument {
    public var bashArgument: String {
        switch self {
        case .apiKey(let key):
            "--apiKey \(key)"
        case .apiIssuer(let issuer):
            "--apiIssuer \"\(issuer)\""
        case .apiPrivateKey(let privateKey):
            "--auth-string \"\(privateKey)\""
        }
    }
}

public extension AltoolUploader {
    enum TransporterSetting {
        case upload
        case appVersion(String)
        case buildNumber(String)
        case file(String)
        case platform(Platform)
        case maxUploadSpeed
        case showProgress
        case oldAltool
        case verbose
    }
}

public extension AltoolUploader {
    enum AuthOption {
        case apiKey(String)
        case apiIssuer(String)
        case apiPrivateKey(String)
    }
}

extension AltoolUploader.TransporterSetting: BashArgument {
    public var bashArgument: String {
        switch self {
        case .upload:
            "--upload-app"
        case .file(let path):
            "-f \(path)"
        case .appVersion(let version):
            "--bundle-short-version-string \(version)" // Xcode 26 altool will fail with --upload-app + --bundle-short-version-string. Xcode 16 will not
        case .buildNumber(let number):
            "--bundle-version \(number)" // Same here. Use --upload-app -f with no build number/version
        case .platform(let platform):
            "-t \(platform.rawValue)"
        case .maxUploadSpeed:
            "-k 100000" // Don't throttle the upload with the default value. Value is Kbps
        case .showProgress:
            "--show-progress"
        case .oldAltool: // Xcode 26+ option only
            "--use-old-altool"
        case .verbose:
            "--verbose"
        }
    }
}

// MARK: - AppStoreConnectUploader Conformance

// FIXME: New altool from Xcode 26.0.1 has processing issues. Prefer using API uploader
public struct AltoolUploaderAdapter: AppStoreConnectUploader {
    private let altoolUploader: AltoolUploader
    
    public init(altoolUploader: AltoolUploader = AltoolUploader()) {
        self.altoolUploader = altoolUploader
    }
    
    public func upload(config: UploadConfig, verbose: Bool) async throws {
        var arguments: [AltoolUploader.TransporterSetting] = [.upload]

        arguments.append(.file(config.filePath))
        arguments.append(.appVersion(config.appVersion))
        arguments.append(.buildNumber(config.buildNumber))
        arguments.append(.platform(config.platform))
        arguments.append(.showProgress)
        arguments.append(.oldAltool)

        try self.altoolUploader.upload(arguments: arguments, verbose: verbose)
    }
}

// MARK: - Private

private extension AltoolUploader {

    /// The log is flooded in non-interactive shells, filter it to get some useful messages
    func makeFilteredLog(_ output: String?) {
        let filteredOutput = output?.split( separator: "\n")
            .map { String($0) } ?? []
        
        for line in filteredOutput {
            logger.info(line)
        }
    }
}
