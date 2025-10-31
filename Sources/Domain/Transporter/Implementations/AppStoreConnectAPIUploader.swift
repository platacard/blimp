import Foundation
import Cronista
import TestflightAPI
import AppsAPI
import JWTProvider
import Crypto

public actor AppStoreConnectAPIUploader: AppStoreConnectUploader {

    nonisolated(unsafe)
    private let logger = Cronista(module: "blimp", category: "ASCTransporter", isFileLoggingEnabled: true)
    private let testflightAPI: TestflightAPI
    private let appsAPI: AppsAPI
    private let urlSession: URLSession

    private let pollInterval: Int?

    private let maxPollAttempts: Int
    private let maxUploadRetries: Int

    private var currentUploadAttempt: [String: Int] = [:]

    public init(
        jwtProvider: any JWTProviding = DefaultJWTProvider(),
        urlSession: URLSession = .shared,
        maxUploadRetries: Int = 3,
        uploadStatusPollInterval: TimeInterval = 30,
        uploadStatusMaxAttempts: Int = 60,
        pollInterval: Int? = 30
    ) {
        self.testflightAPI = TestflightAPI(jwtProvider: jwtProvider)
        self.appsAPI = AppsAPI(jwtProvider: jwtProvider)
        self.urlSession = urlSession
        self.maxUploadRetries = max(1, maxUploadRetries)
        self.pollInterval = pollInterval
        self.maxPollAttempts = max(1, uploadStatusMaxAttempts)
    }

    public func upload(config: UploadConfig, verbose: Bool) async throws {
        let ipaURL = URL(fileURLWithPath: config.filePath, isDirectory: false).standardizedFileURL

        guard FileManager.default.fileExists(atPath: ipaURL.path()) else {
            throw TransporterError.toolError(ASCTransporterError.invalidFile("IPA not found at path \(ipaURL.path())"))
        }

        let fileAttributes = try FileManager.default.attributesOfItem(atPath: ipaURL.path())
        guard let fileSize = (fileAttributes[.size] as? NSNumber)?.int64Value else {
            throw TransporterError.toolError(ASCTransporterError.invalidFile("Unable to determine IPA file size"))
        }

        logger.info("Preparing build upload for \(config.bundleId) version \(config.appVersion) (\(config.buildNumber)).")

        let appId = try await appsAPI.getAppId(bundleId: config.bundleId)
        let descriptor = TestflightAPI.UploadFileDescriptor.ipa(fileName: ipaURL.lastPathComponent, fileSize: fileSize)

        var plan: TestflightAPI.BuildUploadPlan
        do {
            plan = try await testflightAPI.createBuildUpload(
                appId: appId,
                appVersion: config.appVersion,
                buildNumber: config.buildNumber,
                platform: config.platform.asTestflightPlatform,
                file: descriptor
            )
        } catch {
            throw TransporterError.toolError(error)
        }

        plan.status.warnings.forEach { warning in
            logger.warning("Upload plan warning: \(warning)")
        }

        if case .failed = plan.status.phase {
            logger.error("Uploading IPA failed: \(plan.status.errors.joined(separator: "\n")), \(config)")
            throw TransporterError.toolError(ASCTransporterError.uploadFailed(plan.status.errors))
        }

        do {
            try await uploadBinary(plan.operations, fileURL: ipaURL, verbose: verbose)
        } catch {
            logger.error("Uploading chunks failed:\n")
            logger.error(error)

            throw TransporterError.toolError(error)
        }

        logger.info("Notifying App Store Connect that upload is complete.")
        do {
            try await testflightAPI.markUploadComplete(uploadFileId: plan.uploadFileId)
        } catch {
            throw TransporterError.toolError(error)
        }

        let finalStatus = try await pollUploadCompletion(uploadId: plan.uploadId, verbose: verbose)

        switch finalStatus.phase {
        case .complete:
            if !finalStatus.warnings.isEmpty {
                finalStatus.warnings.forEach { logger.warning("Upload warning: \($0)") }
            }
            logger.info("IPA uploaded successfully via App Store Connect API.")
        case .failed:
            finalStatus.errors.forEach { logger.error($0) }
            throw TransporterError.toolError(ASCTransporterError.uploadFailed(finalStatus.errors))
        case .awaitingUpload, .processing:
            logger.warning("Upload finished with unexpected state: \(finalStatus.phase)")
        }
    }
}


// MARK: - Upload Helpers

private extension AppStoreConnectAPIUploader {

    func uploadBinary(_ operations: [TestflightAPI.UploadOperation], fileURL: URL, verbose: Bool) async throws {
        guard !operations.isEmpty else {
            logger.info("No upload operations returned; skipping binary upload phase.")
            return
        }

        await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0 ..< operations.count {
                group.addTask { [self] in
                    try await uploadOperation(operations[i], fileURL: fileURL, verbose: verbose)
                }
            }
        }
    }

    func uploadOperation(_ operation: TestflightAPI.UploadOperation, fileURL: URL, verbose: Bool) async throws {
        let data = try readChunk(fileURL: fileURL, offset: operation.offset, length: operation.length)

        if verbose {
            logger.info("Uploading chunk offset=\(operation.offset) length=\(operation.length) part=\(operation.partNumber ?? -1)")
        }

        do {
            var request = URLRequest(url: operation.url)
            request.timeoutInterval = 300
            request.httpMethod = operation.method
            request.allHTTPHeaderFields = operation.headers
            request.setValue("\(operation.length)", forHTTPHeaderField: "content-length")

            let (_, response) = try await urlSession.upload(for: request, from: data)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ASCTransporterError.invalidResponse("Non-HTTP response while uploading chunk")
            }

            if (200..<300).contains(httpResponse.statusCode) {
                if verbose {
                    logger.info("Finished chunk offset=\(operation.offset) length=\(operation.length)")
                }
                return
            } else {
                throw ASCTransporterError.serverError(statusCode: httpResponse.statusCode)
            }
        } catch {
            currentUploadAttempt[operation.url.absoluteString, default: 0] += 1

            let attempts = currentUploadAttempt[operation.url.absoluteString] ?? 0

            if attempts >= maxUploadRetries {
                throw error
            }

            if verbose {
                logger.warning("Chunk upload failed with \(error.localizedDescription). Retrying attempt \(attempts)/\(maxUploadRetries).")
            }

            try await Task.sleep(for: .seconds(retryDelay(forAttempt: attempts)))
            logger.warning("Retrying \(operation.url) for file: \(fileURL), partNumber: \(operation.partNumber ?? -1)")

            try await uploadOperation(operation, fileURL: fileURL, verbose: verbose)
        }
    }

    func readChunk(fileURL: URL, offset: Int64, length: Int64) throws -> Data {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        try handle.seek(toOffset: UInt64(offset))
        let data = try handle.read(upToCount: Int(length))

        guard let data, data.count == length else {
            throw ASCTransporterError.invalidFile("Failed to read expected number of bytes for chunk starting at offset \(offset)")
        }

        return data
    }

    func pollUploadCompletion(uploadId: String, verbose: Bool) async throws -> TestflightAPI.UploadStatus {
        var attempt = 0

        while attempt < maxPollAttempts {
            let status = try await testflightAPI.getUploadStatus(uploadId: uploadId)

            switch status.phase {
            case .awaitingUpload, .processing:
                guard let pollInterval else {
                    logger.info("No poll interval specified. The processing is skipped")
                    return status
                }

                attempt += 1

                if verbose {
                    logger.info("Upload state: \(status.phase) (attempt \(attempt)/\(maxPollAttempts))")
                }
                try await Task.sleep(for: .seconds(pollInterval))
            case .complete, .failed:
                return status
            }
        }

        throw ASCTransporterError.uploadTimedOut
    }
}

// MARK: Retry delay

private extension AppStoreConnectAPIUploader {

    func retryDelay(forAttempt attempt: Int) -> Int {
        let base = 5 // seconds
        let multiplier = attempt + 1
        return base * multiplier
    }
}

// MARK: - Supporting Types

private enum ASCTransporterError: Error, CustomStringConvertible {
    case missingRequiredArgument(String)
    case invalidFile(String)
    case invalidResponse(String)
    case serverError(statusCode: Int)
    case uploadFailed([String])
    case uploadTimedOut

    var description: String {
        switch self {
        case .missingRequiredArgument(let message):
            return message
        case .invalidFile(let message):
            return message
        case .invalidResponse(let message):
            return message
        case .serverError(let statusCode):
            return "Server returned status \(statusCode) while uploading chunk"
        case .uploadFailed(let errors):
            return errors.joined(separator: " | ")
        case .uploadTimedOut:
            return "Timed out waiting for App Store Connect to finish processing the uploaded build"
        }
    }
}

private extension Platform {

    var asTestflightPlatform: TestflightAPI.Platform {
        switch self {
        case .iOS: .iOS
        case .macOS: .macOS
        case .visionOS: .visionOS
        case .tvOS: .tvOS
        }
    }
}
