import OpenAPIRuntime
import OpenAPIURLSession
import Foundation

public extension TestflightAPI {
    /// Unified processing state for domain layer consumption.
    /// Maps from multiple internal API types: Build.processingState, InternalBetaState, ExternalBetaState, AppVersionState
    enum ProcessingState: Sendable, Equatable {
        // Basic states (from Build.processingState)
        case processing
        case valid
        case failed
        case invalid
        // Terminal error states - fail fast, no polling needed
        case processingException      // From InternalBetaState/ExternalBetaState
        case missingExportCompliance  // From InternalBetaState/ExternalBetaState
        case betaRejected             // From ExternalBetaState
        case invalidBinary            // From AppVersionState

        /// Terminal errors should cause immediate failure without further polling
        public var isTerminalError: Bool {
            asTerminalError != nil
        }

        /// Type-safe conversion to terminal error (nil if not a terminal state)
        public var asTerminalError: TerminalError? {
            switch self {
            case .processingException: .processingException
            case .missingExportCompliance: .missingExportCompliance
            case .betaRejected: .betaRejected
            case .invalidBinary: .invalidBinary
            case .processing, .valid, .failed, .invalid: nil
            }
        }

        /// Terminal error states that require immediate failure without polling.
        /// Use this type when you need compile-time guarantee that only terminal states are handled.
        public enum TerminalError: Sendable, Equatable {
            case processingException
            case missingExportCompliance
            case betaRejected
            case invalidBinary
        }

        /// Basic states that can be used for API filtering (matches the 4 basic Build.processingState values)
        public static let allBasicStates: [ProcessingState] = [.processing, .failed, .invalid, .valid]
    }

    enum BetaBuildState: Sendable {
        case waitingForReview
        case inReview
        case approved
        case rejected
    }
    
    enum BetaBuildSort: Sendable {
        case appVersionAsc
        case appVersionDesc
        case uploadDateAsc
        case uploadDateDesc
    }
    
    struct BuildProcessingResult: Sendable {
        public let processingState: ProcessingState
        public let buildBundleID: String
        public let buildLocalizationIDs: [String]

public init(processingState: ProcessingState, buildBundleID: String, buildLocalizationIDs: [String]) {
            self.processingState = processingState
            self.buildBundleID = buildBundleID
            self.buildLocalizationIDs = buildLocalizationIDs
        }
    }

    enum Platform: Sendable {
        case iOS
        case macOS
        case tvOS
        case visionOS

        var asApiPlatform: Components.Schemas.Platform {
            switch self {
            case .iOS:
                return .ios
            case .macOS:
                return .macOs
            case .tvOS:
                return .tvOs
            case .visionOS:
                return .visionOs
            }
        }
    }
}

// MARK: - Upload Types

public extension TestflightAPI {
    struct BuildUploadPlan: Sendable {
        public let uploadId: String
        public let uploadFileId: String
        public let operations: [UploadOperation]
        public let status: UploadStatus

        public init(uploadId: String, uploadFileId: String, operations: [UploadOperation], status: UploadStatus) {
            self.uploadId = uploadId
            self.uploadFileId = uploadFileId
            self.operations = operations
            self.status = status
        }
    }

    struct UploadOperation: Sendable {
        public let method: String
        public let url: URL
        public let length: Int64
        public let offset: Int64
        public let headers: [String: String]
        public let expiration: Date?
        public let partNumber: Int64?
        public let entityTag: String?

        public init(
            method: String,
            url: URL,
            length: Int64,
            offset: Int64,
            headers: [String: String],
            expiration: Date?,
            partNumber: Int64?,
            entityTag: String?
        ) {
            self.method = method
            self.url = url
            self.length = length
            self.offset = offset
            self.headers = headers
            self.expiration = expiration
            self.partNumber = partNumber
            self.entityTag = entityTag
        }
    }

    struct UploadStatus: Sendable {
        public enum Phase: Sendable {
            case awaitingUpload
            case processing
            case complete
            case failed
        }

        public let phase: Phase
        public let errors: [String]
        public let warnings: [String]

        public init(phase: Phase, errors: [String], warnings: [String]) {
            self.phase = phase
            self.errors = errors
            self.warnings = warnings
        }
    }

    struct UploadFileDescriptor: Sendable {
        public enum AssetType: Sendable {
            case asset
            case assetDescription
            case assetSPI
        }

        public enum UTI: Sendable {
            case ipa
            case pkg
            case zip
            case binaryPropertyList
            case xmlPropertyList
        }

        public let fileName: String
        public let fileSize: Int64
        public let assetType: AssetType
        public let uti: UTI

        public init(fileName: String, fileSize: Int64, assetType: AssetType, uti: UTI) {
            self.fileName = fileName
            self.fileSize = fileSize
            self.assetType = assetType
            self.uti = uti
        }

        public static func ipa(fileName: String, fileSize: Int64) -> UploadFileDescriptor {
            .init(fileName: fileName, fileSize: fileSize, assetType: .asset, uti: .ipa)
        }
    }
}


typealias BuildCollectionQuery = Operations.BuildsGetCollection.Input.Query

extension TestflightAPI.ProcessingState {
    typealias FilterProcessingState = BuildCollectionQuery.FilterLbrackProcessingStateRbrackPayloadPayload

    /// Convert to API filter state (only basic states are valid for filtering)
    var asGeneratedApiState: FilterProcessingState {
        switch self {
        case .processing: .processing
        case .failed: .failed
        case .invalid: .invalid
        case .valid: .valid
        // Terminal errors map to failed for filtering purposes
        case .processingException, .missingExportCompliance, .betaRejected, .invalidBinary:
            .failed
        }
    }
}

// MARK: - Generated code mappings

typealias AttributeProcessingState = Components.Schemas.Build.AttributesPayload.ProcessingStatePayload

extension AttributeProcessingState {
    var asProcessingState: TestflightAPI.ProcessingState {
        switch self {
        case .processing: .processing
        case .failed: .failed
        case .invalid: .invalid
        case .valid: .valid
        }
    }
}

// MARK: - Internal API type mappings to unified ProcessingState

extension Components.Schemas.InternalBetaState {
    var asTerminalProcessingState: TestflightAPI.ProcessingState? {
        switch self {
        case .processingException: .processingException
        case .missingExportCompliance: .missingExportCompliance
        default: nil
        }
    }
}

extension Components.Schemas.ExternalBetaState {
    var asTerminalProcessingState: TestflightAPI.ProcessingState? {
        switch self {
        case .processingException: .processingException
        case .missingExportCompliance: .missingExportCompliance
        case .betaRejected: .betaRejected
        default: nil
        }
    }
}

extension Components.Schemas.AppVersionState {
    var asTerminalProcessingState: TestflightAPI.ProcessingState? {
        switch self {
        case .invalidBinary: .invalidBinary
        default: nil
        }
    }
}

extension TestflightAPI.BetaBuildState {
    typealias GeneratedBuildState = BuildCollectionQuery.FilterLbrackBetaAppReviewSubmissionBetaReviewStateRbrackPayloadPayload

    var asGeneratedApiState: GeneratedBuildState {
        switch self {
        case .waitingForReview: .waitingForReview
        case .inReview: .inReview
        case .rejected: .rejected
        case .approved: .approved
        }
    }
}

extension TestflightAPI.BetaBuildSort {
    typealias QuerySortPayload = Operations.BuildsGetCollection.Input.Query.SortPayloadPayload

    var asGeneratedApiPayload: QuerySortPayload {
        switch self {
        case .appVersionAsc: .preReleaseVersion
        case .appVersionDesc: ._hyphen_preReleaseVersion
        case .uploadDateAsc: .uploadedDate
        case .uploadDateDesc: ._hyphen_uploadedDate
        }
    }
}

extension TestflightAPI.UploadFileDescriptor.AssetType {
    var generatedValue: Components.Schemas.BuildUploadFileCreateRequest.DataPayload.AttributesPayload.AssetTypePayload {
        switch self {
        case .asset:
            return .asset
        case .assetDescription:
            return .assetDescription
        case .assetSPI:
            return .assetSpi
        }
    }
}

extension TestflightAPI.UploadFileDescriptor.UTI {
    var generatedValue: Components.Schemas.BuildUploadFileCreateRequest.DataPayload.AttributesPayload.UtiPayload {
        switch self {
        case .ipa:
            return .com_apple_ipa
        case .pkg:
            return .com_apple_pkg
        case .zip:
            return .com_pkware_zipArchive
        case .binaryPropertyList:
            return .com_apple_binaryPropertyList
        case .xmlPropertyList:
            return .com_apple_xmlPropertyList
        }
    }
}

extension Components.Schemas.BuildUploadFile {
    func matches(assetType: TestflightAPI.UploadFileDescriptor.AssetType) -> Bool {
        guard let value = attributes?.assetType else {
            return assetType == .asset
        }

        switch (value, assetType) {
        case (.asset, .asset), (.assetDescription, .assetDescription), (.assetSpi, .assetSPI):
            return true
        default:
            return false
        }
    }

    func makeUploadOperations() throws -> [TestflightAPI.UploadOperation] {
        guard let operations = attributes?.uploadOperations, !operations.isEmpty else {
            throw TestflightAPI.Error.badResponse("Missing upload operations in response")
        }

        return try operations.map { try TestflightAPI.UploadOperation(operation: $0) }
    }
}

extension TestflightAPI.UploadOperation {

    init(operation: Components.Schemas.DeliveryFileUploadOperation) throws {
        guard
            let method = operation.method,
            let urlString = operation.url,
            let url = URL(string: urlString),
            let length = operation.length,
            let offset = operation.offset
        else {
            throw TestflightAPI.Error.badResponse("Incomplete upload operation payload")
        }

        let headers = operation.requestHeaders?.reduce(into: [String: String]()) { result, header in
            if let name = header.name, let value = header.value {
                result[name] = value
            }
        } ?? [:]

        self.init(
            method: method,
            url: url,
            length: length,
            offset: offset,
            headers: headers,
            expiration: operation.expiration,
            partNumber: operation.partNumber,
            entityTag: operation.entityTag
        )
    }
}

extension Components.Schemas.BuildUpload {
    func asUploadStatus() throws -> TestflightAPI.UploadStatus {
        guard let stateWrapper = attributes?.state, let rawState = stateWrapper.state else {
            throw TestflightAPI.Error.badResponse("Missing upload state information")
        }

        let errors = stateWrapper.errors?.humanReadable ?? []
        let warnings = stateWrapper.warnings?.humanReadable ?? []

        let phase: TestflightAPI.UploadStatus.Phase
        switch rawState {
        case .awaitingUpload:
            phase = .awaitingUpload
        case .processing:
            phase = .processing
        case .complete:
            phase = .complete
        case .failed:
            phase = .failed
        }

        return .init(phase: phase, errors: errors, warnings: warnings)
    }
}

extension Components.Schemas.ErrorResponse {
    var errorDescription: String {
        guard let errors, !errors.isEmpty else {
            return "Unknown error"
        }

        return errors.map { "\($0.code): \($0.detail)" }.joined(separator: " | ")
    }
}

// MARK: Helpers

extension String {

    var redactedEmail: String {
        guard let atIndex = self.firstIndex(of: "@") else { return self }

        let namePart = self[..<atIndex]
        let domainPart = self[self.index(after: atIndex)...]

        // Show the first and last character of the username, mask the rest
        let prefix = namePart.prefix(1)
        let suffix = namePart.count > 1 ? namePart.suffix(1) : ""
        let maskedPart = String(repeating: "*", count: max(0, namePart.count - 2))

        return "\(prefix)\(maskedPart)\(suffix)@\(domainPart)"
    }
}

extension Array where Element == Components.Schemas.StateDetail {
    var humanReadable: [String] {
        map { detail in
            if let description = detail.description, !description.isEmpty {
                return description
            }
            if let code = detail.code, !code.isEmpty {
                return code
            }
            return "Unknown detail"
        }
    }
}

// MARK: - Base Error

extension TestflightAPI {
    enum Error: Swift.Error {
        case badRequest(String? = nil)
        case undocumented(String? = nil)
        case badResponse(String? = nil)
    }
}

// MARK: - Testability Protocol

/// Protocol for build processing operations - enables testing of Approach stage
public protocol BuildProcessingService: Sendable {
    func getBuildID(
        appId: String,
        appVersion: String,
        buildNumber: String,
        states: [TestflightAPI.ProcessingState],
        limit: Int,
        sorted: [TestflightAPI.BetaBuildSort]
    ) async throws -> String?

    func getBuildProcessingResult(id: String) async throws -> TestflightAPI.BuildProcessingResult
}

extension TestflightAPI: BuildProcessingService {}
