import Foundation
import Cronista
import TestflightAPI
import AppsAPI
import JWTProvider
import Crypto

public struct AppStoreConnectAPIUploader: AppStoreConnectUploader {

    private let logger = Cronista(module: "blimp", category: "ASCTransporter")
    private let testflightAPI: TestflightAPI
    private let appsAPI: AppsAPI
    private let urlSession: URLSession
    private let maxConcurrentChunkUploads: Int
    private let maxUploadRetries: Int
    private let pollIntervalNanoseconds: UInt64
    private let maxPollAttempts: Int

    public init(
        jwtProvider: any JWTProviding = DefaultJWTProvider(),
        urlSession: URLSession = .shared,
        maxConcurrentChunkUploads: Int = 4,
        maxUploadRetries: Int = 3,
        uploadStatusPollInterval: TimeInterval = 30,
        uploadStatusMaxAttempts: Int = 60
    ) {
        self.testflightAPI = TestflightAPI(jwtProvider: jwtProvider)
        self.appsAPI = AppsAPI(jwtProvider: jwtProvider)
        self.urlSession = urlSession
        self.maxConcurrentChunkUploads = max(1, maxConcurrentChunkUploads)
        self.maxUploadRetries = max(1, maxUploadRetries)
        self.pollIntervalNanoseconds = UInt64(max(uploadStatusPollInterval, 0.5) * 1_000_000_000)
        self.maxPollAttempts = max(1, uploadStatusMaxAttempts)
    }

    public func upload(config: UploadConfig, verbose: Bool) async throws {
        guard let filePath = config.filePath else {
            throw TransporterError.toolError(ASCTransporterError.missingRequiredArgument("IPA file path (--file) is required for upload"))
        }

        guard let appVersion = config.appVersion else {
            throw TransporterError.toolError(ASCTransporterError.missingRequiredArgument("App version (--appVersion) is required for upload"))
        }

        guard let buildNumber = config.buildNumber else {
            throw TransporterError.toolError(ASCTransporterError.missingRequiredArgument("Build number (--buildNumber) is required for upload"))
        }

        guard let platform = config.platform?.asTestflightPlatform else {
            throw TransporterError.toolError(ASCTransporterError.missingRequiredArgument("Platform (--platform) is required for upload"))
        }

        let ipaURL = URL(fileURLWithPath: filePath, isDirectory: false).standardizedFileURL

        guard FileManager.default.fileExists(atPath: ipaURL.path()) else {
            throw TransporterError.toolError(ASCTransporterError.invalidFile("IPA not found at path \(ipaURL.path())"))
        }

        let fileAttributes = try FileManager.default.attributesOfItem(atPath: ipaURL.path())
        guard let fileSize = (fileAttributes[.size] as? NSNumber)?.int64Value else {
            throw TransporterError.toolError(ASCTransporterError.invalidFile("Unable to determine IPA file size"))
        }

        logger.info("Preparing build upload for \(config.bundleId) version \(appVersion) (\(buildNumber)).")

        let appId = try await appsAPI.getAppId(bundleId: config.bundleId)
        let descriptor = TestflightAPI.UploadFileDescriptor.ipa(fileName: ipaURL.lastPathComponent, fileSize: fileSize)

        var plan: TestflightAPI.BuildUploadPlan
        do {
            plan = try await testflightAPI.createBuildUpload(
                appId: appId,
                appVersion: appVersion,
                buildNumber: buildNumber,
                platform: platform,
                file: descriptor
            )
        } catch {
            throw TransporterError.toolError(error)
        }

        if !plan.status.warnings.isEmpty {
            plan.status.warnings.forEach { warning in
                logger.warning("Upload plan warning: \(warning)")
            }
        }

        if case .failed = plan.status.phase {
            throw TransporterError.toolError(ASCTransporterError.uploadFailed(plan.status.errors))
        }

        let checksums = try computeChecksums(for: ipaURL)

        do {
            try await uploadBinary(plan.operations, fileURL: ipaURL, verbose: verbose)
        } catch {
            logger.error("Uploading chunks failed:\n")
            logger.error(error)

            throw TransporterError.toolError(error)
        }

        logger.info("Notifying App Store Connect that upload is complete.")
        do {
            try await testflightAPI.markUploadComplete(
                uploadFileId: plan.uploadFileId,
                checksum: .init(sha256: checksums.sha256Base64, md5: checksums.md5Base64)
            )
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
            throw TransporterError.toolError(ASCTransporterError.uploadFailed(finalStatus.errors))
        case .awaitingUpload, .processing:
            logger.warning("Upload finished with unexpected state: \(finalStatus.phase)")
        }
    }
}


// MARK: - Upload Helpers

private extension AppStoreConnectAPIUploader {

    struct FileChecksums {
        let sha256Base64: String
        let md5Base64: String
    }

    func computeChecksums(for fileURL: URL) throws -> FileChecksums {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var sha256 = SHA256()
        var md5 = Insecure.MD5()

        while true {
            let chunk = try handle.read(upToCount: 8 * 1024 * 1024)
            guard let chunk, !chunk.isEmpty else { break }
            sha256.update(data: chunk)
            md5.update(data: chunk)
        }

        let sha256Digest = Data(sha256.finalize())
        let md5Digest = Data(md5.finalize())

        return .init(
            sha256Base64: sha256Digest.base64EncodedString(),
            md5Base64: md5Digest.base64EncodedString()
        )
    }

    func uploadBinary(_ operations: [TestflightAPI.UploadOperation], fileURL: URL, verbose: Bool) async throws {
        guard !operations.isEmpty else {
            logger.info("No upload operations returned; skipping binary upload phase.")
            return
        }

        let sortedOperations = operations.sorted { $0.offset < $1.offset }
        var iterator = sortedOperations.makeIterator()

        try await withThrowingTaskGroup(of: Void.self) { group in
            let initialCount = min(maxConcurrentChunkUploads, sortedOperations.count)

            for _ in 0..<initialCount {
                guard let operation = iterator.next() else { break }

                group.addTask {
                    try await self.uploadOperation(operation, fileURL: fileURL, verbose: verbose)
                }
            }

            while let _ = try await group.next() {
                if let nextOperation = iterator.next() {
                    group.addTask {
                        try await self.uploadOperation(nextOperation, fileURL: fileURL, verbose: verbose)
                    }
                }
            }
        }
    }

    func uploadOperation(_ operation: TestflightAPI.UploadOperation, fileURL: URL, verbose: Bool) async throws {
        let data = try readChunk(fileURL: fileURL, offset: operation.offset, length: operation.length)

        if verbose {
            logger.info("Uploading chunk offset=\(operation.offset) length=\(operation.length) part=\(operation.partNumber ?? -1)")
        }

        var attempt = 0
        while attempt < maxUploadRetries {
            do {
                var request = URLRequest(url: operation.url)
                request.httpMethod = operation.method
                for (header, value) in operation.headers {
                    request.setValue(value, forHTTPHeaderField: header)
                }

                let (_, response) = try await urlSession.upload(for: request, from: data)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw ASCTransporterError.invalidResponse("Non-HTTP response while uploading chunk")
                }

                if (200..<300).contains(httpResponse.statusCode) {
                    if verbose {
                        logger.info("Finished chunk offset=\(operation.offset) length=\(operation.length)")
                    }
                    return
                }

                if shouldRetry(statusCode: httpResponse.statusCode) {
                    attempt += 1
                    if verbose {
                        logger.warning("Chunk upload received status \(httpResponse.statusCode). Retrying attempt \(attempt)/\(maxUploadRetries).")
                    }
                    try await Task.sleep(nanoseconds: retryDelayNanoseconds(forAttempt: attempt))
                    continue
                } else {
                    throw ASCTransporterError.serverError(statusCode: httpResponse.statusCode)
                }
            } catch {
                attempt += 1
                if attempt >= maxUploadRetries {
                    throw error
                }
                if verbose {
                    logger.warning("Chunk upload failed with \(error.localizedDescription). Retrying attempt \(attempt)/\(maxUploadRetries).")
                }
                try await Task.sleep(nanoseconds: retryDelayNanoseconds(forAttempt: attempt))
            }
        }

        throw ASCTransporterError.uploadFailed(["Exceeded maximum retry attempts for chunk offset \(operation.offset)"])
    }

    func readChunk(fileURL: URL, offset: Int64, length: Int64) throws -> Data {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        try handle.seek(toOffset: UInt64(offset))

        var remaining = length
        var buffer = Data(capacity: Int(length))

        while remaining > 0 {
            let chunkSize = min(remaining, Int64(8 * 1024 * 1024))
            let data = try handle.read(upToCount: Int(chunkSize)) ?? Data()
            if data.isEmpty {
                break
            }
            buffer.append(data)
            remaining -= Int64(data.count)
        }

        guard buffer.count == length else {
            throw ASCTransporterError.invalidFile("Failed to read expected number of bytes for chunk starting at offset \(offset)")
        }

        return buffer
    }

    func shouldRetry(statusCode: Int) -> Bool {
        statusCode == 429 || (500..<600).contains(statusCode)
    }

    func retryDelayNanoseconds(forAttempt attempt: Int) -> UInt64 {
        let base: UInt64 = 500_000_000 // 0.5 seconds
        let multiplier = UInt64(1 << max(0, attempt - 1))
        return base * max(1, multiplier)
    }

    func pollUploadCompletion(uploadId: String, verbose: Bool) async throws -> TestflightAPI.UploadStatus {
        var attempt = 0

        while attempt < maxPollAttempts {
            let status = try await testflightAPI.getUploadStatus(uploadId: uploadId)

            switch status.phase {
            case .awaitingUpload, .processing:
                attempt += 1
                if verbose {
                    logger.info("Upload state: \(status.phase) (attempt \(attempt)/\(maxPollAttempts))")
                }
                try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            case .complete, .failed:
                return status
            }
        }

        throw ASCTransporterError.uploadTimedOut
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

extension AppStoreConnectAPIUploader: @unchecked Sendable {}

