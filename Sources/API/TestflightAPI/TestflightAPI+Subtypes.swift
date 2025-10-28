import OpenAPIRuntime
import OpenAPIURLSession

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

extension TestflightAPI {
    enum Error: Swift.Error {
        case badRequest(String? = nil)
        case undocumented(String? = nil)
        case badResponse(String? = nil)
    }
}
