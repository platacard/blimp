import OpenAPIRuntime
import OpenAPIURLSession
import Foundation

public extension TestflightAPI {
    enum BetaProcessingState: CaseIterable {
        case processing
        case failed
        case invalid
        case valid
    }
    
    enum BetaBuildState {
        case waitingForReview
        case inReview
        case approved
        case rejected
    }
    
    enum BetaBuildSort {
        case appVersionAsc
        case appVersionDesc
        case uploadDateAsc
        case uploadDateDesc
    }
    
    struct BuildProcessingResult {
        public let processingState: BetaProcessingState
        public let buildBundleID: String
        public let buildLocalizationIDs: [String]
    }

    enum Platform {
        case iOS
        case macOS
        case tvOS
        case visionOS

        var asApiPlatform: Components.Schemas.Platform {
            switch self {
            case .iOS:
                return .IOS
            case .macOS:
                return .MAC_OS
            case .tvOS:
                return .TV_OS
            case .visionOS:
                return .VISION_OS
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


typealias BuildCollectionQuery = Operations.builds_getCollection.Input.Query

extension TestflightAPI.BetaProcessingState {
    typealias FilterProcessingState = BuildCollectionQuery.filter_lbrack_processingState_rbrack_PayloadPayload
    
    var asGeneratedApiState: FilterProcessingState {
        switch self {
        case .processing: .PROCESSING
        case .failed: .FAILED
        case .invalid: .INVALID
        case .valid: .VALID
        }
    }
}

// MARK: - Generated code mappings

typealias AttributeProcessingState = Components.Schemas.Build.attributesPayload.processingStatePayload

extension AttributeProcessingState {
    var asProcessingState: TestflightAPI.BetaProcessingState {
        switch self {
        case .PROCESSING: .processing
        case .FAILED: .failed
        case .INVALID: .invalid
        case .VALID: .valid
        }
    }
}

extension TestflightAPI.BetaBuildState {
    typealias GeneratedBuildState = BuildCollectionQuery.filter_lbrack_betaAppReviewSubmission_period_betaReviewState_rbrack_PayloadPayload
    
    var asGeneratedApiState: GeneratedBuildState {
        switch self {
        case .waitingForReview: .WAITING_FOR_REVIEW
        case .inReview: .IN_REVIEW
        case .rejected: .REJECTED
        case .approved: .APPROVED
        }
    }
}

extension TestflightAPI.BetaBuildSort {
    typealias QuerySortPayload = Operations.builds_getCollection.Input.Query.sortPayloadPayload

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
    var generatedValue: Components.Schemas.BuildUploadFileCreateRequest.dataPayload.attributesPayload.assetTypePayload {
        switch self {
        case .asset:
            return .ASSET
        case .assetDescription:
            return .ASSET_DESCRIPTION
        case .assetSPI:
            return .ASSET_SPI
        }
    }
}

extension TestflightAPI.UploadFileDescriptor.UTI {
    var generatedValue: Components.Schemas.BuildUploadFileCreateRequest.dataPayload.attributesPayload.utiPayload {
        switch self {
        case .ipa:
            return .com_period_apple_period_ipa
        case .pkg:
            return .com_period_apple_period_pkg
        case .zip:
            return .com_period_pkware_period_zip_hyphen_archive
        case .binaryPropertyList:
            return .com_period_apple_period_binary_hyphen_property_hyphen_list
        case .xmlPropertyList:
            return .com_period_apple_period_xml_hyphen_property_hyphen_list
        }
    }
}

extension Components.Schemas.BuildUploadFile {
    func matches(assetType: TestflightAPI.UploadFileDescriptor.AssetType) -> Bool {
        guard let value = attributes?.assetType else {
            return assetType == .asset
        }

        switch (value, assetType) {
        case (.ASSET, .asset), (.ASSET_DESCRIPTION, .assetDescription), (.ASSET_SPI, .assetSPI):
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
        case .AWAITING_UPLOAD:
            phase = .awaitingUpload
        case .PROCESSING:
            phase = .processing
        case .COMPLETE:
            phase = .complete
        case .FAILED:
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
