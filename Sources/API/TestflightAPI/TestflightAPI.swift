import Foundation
import OpenAPIRuntime
import OpenAPIURLSession
import JWTProvider
import Cronista
import Auth
import ClientTransport

public struct TestflightAPI {
    private let jwtProvider: any JWTProviding
    private let client: any APIProtocol
    private let logger = Cronista(module: "blimp", category: "TestFlightAPI")

    public init(jwtProvider: any JWTProviding) {
        self.jwtProvider = jwtProvider

        self.client = Client(
            serverURL: try! Servers.Server1.url(),
            configuration: .init(dateTranscoder: .iso8601WithFractionalSeconds),
            transport: RetryingURLSessionTransport(),
            middlewares: [
                AuthMiddleware { try jwtProvider.token() }
            ]
        )
    }

    public func createBuildUpload(
        appId: String,
        appVersion: String,
        buildNumber: String,
        platform: TestflightAPI.Platform,
        file: UploadFileDescriptor
    ) async throws -> BuildUploadPlan {
        let request = Components.Schemas.BuildUploadCreateRequest(
            data: .init(
                _type: .buildUploads,
                attributes: .init(
                    cfBundleShortVersionString: appVersion,
                    cfBundleVersion: buildNumber,
                    platform: platform.asApiPlatform
                ),
                relationships: .init(
                    app: .init(
                        data: .init(_type: .apps, id: appId)
                    )
                )
            )
        )

        let response = try await client.buildUploads_createInstance(.init(body: .json(request)))

        switch response {
        case .created(let created):
            let payload = try created.body.json
            let buildUpload = payload.data
            let status = try buildUpload.asUploadStatus()

            let existingFiles = payload.included?.compactMap { item -> Components.Schemas.BuildUploadFile? in
                if case let .buildUploadFiles(fileItem) = item {
                    return fileItem
                }
                return nil
            } ?? []

            let assetFile = existingFiles.first(where: { $0.matches(assetType: file.assetType) && ($0.attributes?.uploadOperations?.isEmpty == false) })

            let resolvedFile: Components.Schemas.BuildUploadFile
            if let assetFile {
                resolvedFile = assetFile
            } else {
                resolvedFile = try await createBuildUploadFile(uploadId: buildUpload.id, file: file)
            }

            let operations = try resolvedFile.makeUploadOperations()

            return BuildUploadPlan(
                uploadId: buildUpload.id,
                uploadFileId: resolvedFile.id,
                operations: operations,
                status: status
            )
        case .badRequest(let badRequest):
            let message = (try? badRequest.body.json.errorDescription) ?? "Bad request"
            throw Error.badRequest(message)
        case .unauthorized(let unauthorized):
            let message = (try? unauthorized.body.json.errorDescription) ?? "Unauthorized"
            throw Error.badResponse(message)
        case .forbidden(let forbidden):
            let message = (try? forbidden.body.json.errorDescription) ?? "Forbidden"
            throw Error.badResponse(message)
        case .unprocessableContent(let unprocessable):
            let message = (try? unprocessable.body.json.errorDescription) ?? "Unprocessable content"
            throw Error.badResponse(message)
        case .conflict(let conflict):
            let message = (try? conflict.body.json.errorDescription) ?? "Conflict"
            throw Error.badResponse(message)
        case .tooManyRequests(let tooMany):
            let message = (try? tooMany.body.json.errorDescription) ?? "Too many requests"
            throw Error.badResponse(message)
        case .undocumented(let statusCode, let undocumentedPayload):
            throw Error.undocumented("\(statusCode): \(undocumentedPayload.body.debugDescription)")
        }
    }

    public func markUploadComplete(uploadFileId: String, checksum: UploadChecksum) async throws {
        let updateRequest = Components.Schemas.BuildUploadFileUpdateRequest(
            data: .init(
                _type: .buildUploadFiles,
                id: uploadFileId,
                attributes: .init(
                    sourceFileChecksums: checksum.asComponents(),
                    uploaded: true
                )
            )
        )

        let response = try await client.buildUploadFiles_updateInstance(
            .init(
                path: .init(id: uploadFileId),
                body: .json(updateRequest)
            )
        )

        switch response {
        case .ok:
            return
        case .badRequest(let badRequest):
            let message = (try? badRequest.body.json.errorDescription) ?? "Bad request"
            throw Error.badRequest(message)
        case .unauthorized(let unauthorized):
            let message = (try? unauthorized.body.json.errorDescription) ?? "Unauthorized"
            throw Error.badResponse(message)
        case .forbidden(let forbidden):
            let message = (try? forbidden.body.json.errorDescription) ?? "Forbidden"
            throw Error.badResponse(message)
        case .notFound:
            throw Error.badResponse("Upload file \(uploadFileId) not found")
        case .unprocessableContent(let unprocessable):
            let message = (try? unprocessable.body.json.errorDescription) ?? "Unprocessable content"
            throw Error.badResponse(message)
        case .conflict(let conflict):
            let message = (try? conflict.body.json.errorDescription) ?? "Conflict"
            throw Error.badResponse(message)
        case .tooManyRequests(let tooMany):
            let message = (try? tooMany.body.json.errorDescription) ?? "Too many requests"
            throw Error.badResponse(message)
        case .undocumented(let statusCode, let undocumentedPayload):
            throw Error.undocumented("\(statusCode): \(undocumentedPayload.body.debugDescription)")
        }
    }

    public func getUploadStatus(uploadId: String) async throws -> UploadStatus {
        let response = try await client.buildUploads_getInstance(
            .init(
                path: .init(id: uploadId),
                query: .init(fields_lbrack_buildUploads_rbrack_: [.state])
            )
        )

        switch response {
        case .ok(let ok):
            let payload = try ok.body.json
            return try payload.data.asUploadStatus()
        case .badRequest(let badRequest):
            let message = (try? badRequest.body.json.errorDescription) ?? "Bad request"
            throw Error.badRequest(message)
        case .unauthorized(let unauthorized):
            let message = (try? unauthorized.body.json.errorDescription) ?? "Unauthorized"
            throw Error.badResponse(message)
        case .forbidden(let forbidden):
            let message = (try? forbidden.body.json.errorDescription) ?? "Forbidden"
            throw Error.badResponse(message)
        case .notFound:
            throw Error.badResponse("Upload \(uploadId) not found")
        case .tooManyRequests(let tooMany):
            let message = (try? tooMany.body.json.errorDescription) ?? "Too many requests"
            throw Error.badResponse(message)
        case .undocumented(let statusCode, let undocumentedPayload):
            throw Error.undocumented("\(statusCode): \(undocumentedPayload.body.debugDescription)")
        }
    }

    public func getBuildID(
        appId: String,
        appVersion: String,
        buildNumber: String,
        states: [BetaProcessingState] = BetaProcessingState.allCases,
        limit: Int = 10,
        sorted sort: [BetaBuildSort] = [.uploadDateDesc]
    ) async throws -> String? {
        let response = try await client.builds_getCollection(
            Operations.builds_getCollection.Input(
                query: .init(
                    filter_lbrack_version_rbrack_: [buildNumber],
                    filter_lbrack_processingState_rbrack_: states.map { $0.asGeneratedApiState },
                    filter_lbrack_preReleaseVersion_period_version_rbrack_: [appVersion],
                    filter_lbrack_app_rbrack_: [appId],
                    sort: sort.map { $0.asGeneratedApiPayload },
                    fields_lbrack_builds_rbrack_: [.app, .betaGroups, .buildBetaDetail, .preReleaseVersion, .version],
                    fields_lbrack_preReleaseVersions_rbrack_: [.version],
                    fields_lbrack_apps_rbrack_: [.bundleId, .builds],
                    limit: limit,
                    include: [.app, .buildBetaDetail, .preReleaseVersion]
                )
            )
        )

        switch response {
            case .badRequest(let badRequest):
                logger.info("Bad request: \(badRequest)")
            case .unauthorized(let unauthorized):
                logger.info("Unauthorized: \(unauthorized)")
            case .forbidden(let forbidden):
                logger.info("Forbidden: \(forbidden)")
            case .ok(let ok):
                let builds = try ok.body.json.data

                // The build has appeared in the app store connect and it's the exact match
                if let build = builds.first, build.attributes?.version == buildNumber {
                    return build.id
                    // The build has not yet appeared. Try a bit later
                } else {
                    return nil
                }
            case .undocumented(let statusCode, let undocumentedPayload):
                logger.info("Undocumented response. Update the openapi.json spec. Status: \(statusCode), Payload: \(undocumentedPayload)")
            case .tooManyRequests(let response):
                logger.info("Too many requests. 429, \(response)")
        }

        throw Error.badResponse()
    }

    public func getBuildProcessingResult(id: String) async throws -> BuildProcessingResult {
        let response = try await client.builds_getInstance(
            .init(
                path: .init(id: id),
                query: .init(
                    fields_lbrack_builds_rbrack_: [.buildBetaDetail, .preReleaseVersion, .processingState, .betaBuildLocalizations, .buildBundles],
                    fields_lbrack_preReleaseVersions_rbrack_: [.version],
                    include: [.buildBetaDetail, .preReleaseVersion, .buildBundles, .betaBuildLocalizations]
                )
            )
        )
        guard
            let processingState = try response.ok.body.json.data.attributes?.processingState,
            let buildBundleID = try? response.ok.body.json.data.relationships?.buildBundles?.data?.first?.id,
            let buildLocalizationIDs = try? (response.ok.body.json.data.relationships?.betaBuildLocalizations?.data?.compactMap { $0.id })
        else {
            throw Error.badResponse()
        }

        return .init(
            processingState: processingState.asProcessingState,
            buildBundleID: buildBundleID,
            buildLocalizationIDs: buildLocalizationIDs
        )
    }

    public func inviteDeveloper(
        email: String,
        firstName: String,
        lastName: String
    ) async throws {
        let response = try await client.userInvitations_createInstance(
            body: .json(.init(data: .init(
                _type: .userInvitations,
                attributes: .init(
                    email: email,
                    firstName: firstName,
                    lastName: lastName,
                    roles: [.DEVELOPER],
                    allAppsVisible: true,
                    provisioningAllowed: false
                )
            )))
        )

        let email = try response.created.body.json.data.attributes?.email
        logger.info("Invite sent to \(email?.redactedEmail ?? "unknown")")
    }

    public func inviteBetaTester(
        appIds: [String],
        betaGroups: [String],
        email: String,
        firstName: String,
        lastName: String
    ) async throws {
        for appId in appIds {
            let betaGroupIds = try await getBetaGroupIds(appId: appId, betaGroups: betaGroups)

            logger.info("Beta groups names: \(betaGroups)")
            logger.info("Got beta groups ids for \(appId): \(betaGroupIds))")

            if let betaTesterId = try await getBetaTesterId(appId: appId, email: email) {
                try await assignExistingTesterToGroups(betaGroupIds, betaTesterId, appId: appId)
                try? await resendBetaTesterInviteMail(appId: appId, betaTesterId: betaTesterId) // betaTester relationship deprecated WTF??
            } else {
                _ = try await createNewBetaTester(
                    betaGroupIds,
                    appId: appId,
                    firstName: firstName,
                    lastName: lastName,
                    email: email
                )
            }
        }
    }

    public func setBetaGroups(appId: String, buildId: String, betaGroups: [String], isInternal: Bool = false) async throws {
        let betaGroupsIds = try await getBetaGroupIds(appId: appId, betaGroups: betaGroups)

        typealias Groups = Components.Schemas.BuildBetaGroupsLinkagesRequest.dataPayload
        let mappedGroups: Groups = betaGroupsIds.map { .init(_type: .betaGroups, id: $0) }

        let response = try await client.builds_betaGroups_createToManyRelationship(
            .init(
                path: .init(id: buildId),
                body: .json(.init(data: mappedGroups))
            )
        )

        _ = try response.noContent

        logger.info("The following beta groups were set: [\(betaGroups.joined(separator: ", "))]")
    }

    public func setChangelog(localizationIds: [String], changelog: String) async throws {
        // TODO: the first for TF is always en-US. Improve this to create the new locales if needed
        if let localizationId = localizationIds.first {
            let response = try await client.betaBuildLocalizations_updateInstance(
                .init(
                    path: .init(id: localizationId),
                    body: .json(
                        .init(
                            data: .init(
                                _type: .betaBuildLocalizations,
                                id: localizationId,
                                attributes: .init(whatsNew: changelog)
                            )
                        )
                    )
                )
            )
            _ = try response.ok
        }

        logger.info("Changelog entry has been created:\n\(changelog)")
    }

    public func sendToTestflightReview(buildId: String) async throws {
        let result = try await client.betaAppReviewSubmissions_createInstance(
            body: .json(.init(data: .init(
                _type: .betaAppReviewSubmissions,
                relationships: .init(build: .init(data: .init(_type: .builds, id: buildId)))
            )))
        )

        _ = try result.created

        logger.info("Sent to review")
    }

    public func getBuildBundleIDs(
        appId: String,
        state: BetaBuildState,
        limit: Int = 10
    ) async throws -> [String] {
        let response = try await client.builds_getCollection(
            Operations.builds_getCollection.Input(
                query: .init(
                    filter_lbrack_betaAppReviewSubmission_period_betaReviewState_rbrack_: [state.asGeneratedApiState],
                    filter_lbrack_app_rbrack_: [appId],
                    fields_lbrack_builds_rbrack_: [.app, .betaGroups, .buildBundles],
                    fields_lbrack_apps_rbrack_: [.bundleId, .builds],
                    limit: limit,
                    include: [.app, .buildBetaDetail, .buildBundles]
                ),
                headers: Operations.builds_getCollection.Input.Headers()
            )
        )

        switch response {
            case .badRequest(let badRequest):
                logger.info("Bad request: \(badRequest)")
            case .unauthorized(let unauthorized):
                logger.info("Unauthorized: \(unauthorized)")
            case .forbidden(let forbidden):
                logger.info("Forbidden: \(forbidden)")
            case .ok(let ok):
                let data = try ok.body.json.data
                return try data.map { build in
                    guard let id = build.relationships?.buildBundles?.data?.first?.id else {
                        throw Error.badResponse()
                    }

                    return id
                }
            case .undocumented(let statusCode, let undocumentedPayload):
                logger.info("Undocumented response. Update the openapi.json spec. Status: \(statusCode), Payload: \(undocumentedPayload)")
            case .tooManyRequests(let response):
                logger.info("Too many requests. 429, \(response)")
        }

        throw Error.badResponse()
    }

    public func getBundleBuildSizes(
        buildBundleID: String,
        devices: [String]
    ) async throws -> [BundleBuildFileSize] {
        let response = try await client.buildBundles_buildBundleFileSizes_getToManyRelated(
            path: .init(id: buildBundleID)
        )

        switch response {
            case .badRequest(let badRequest):
                logger.info("Bad request: \(badRequest)")
            case .unauthorized(let unauthorized):
                logger.info("Unauthorized: \(unauthorized)")
            case .forbidden(let forbidden):
                logger.info("Forbidden: \(forbidden)")
            case .ok(let ok):
                let data = try ok.body.json.data

                let devicesSet = Set(devices)

                let array: [BundleBuildFileSize] = try data.compactMap { item in
                    guard
                        let attributes = item.attributes,
                        let deviceModel = attributes.deviceModel,
                        let downloadBytes = attributes.downloadBytes,
                        let installBytes = attributes.installBytes
                    else {
                        throw Error.badResponse()
                    }

                    guard
                        devicesSet.contains(deviceModel)
                    else {
                        return nil
                    }

                    let fileSizeInfo = BundleBuildFileSize(
                        deviceModel: deviceModel,
                        downloadBytes: downloadBytes,
                        instalBytes: installBytes
                    )

                    return fileSizeInfo
                }

                return array
            case .undocumented(let statusCode, let undocumentedPayload):
                logger.info("Undocumented response. Update the openapi.json spec. Status: \(statusCode), Payload: \(undocumentedPayload)")
            case .notFound(_):
                logger.info("BuildBundleID: \(buildBundleID) not found")
            case .tooManyRequests(let response):
                logger.info("Too many requests. 429, \(response)")
        }

        throw Error.badResponse()
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

    struct UploadChecksum: Sendable {
        public let sha256: String?
        public let md5: String?

        public init(sha256: String? = nil, md5: String? = nil) {
            self.sha256 = sha256
            self.md5 = md5
        }
    }
}

// MARK: - Upload platforms

public extension TestflightAPI {

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
            @unknown default:
                fatalError("New platform case without a corresponding API case")
            }
        }
    }
}

// MARK: - Private

private extension TestflightAPI {

    func createBuildUploadFile(uploadId: String, file: UploadFileDescriptor) async throws -> Components.Schemas.BuildUploadFile {
        let request = Components.Schemas.BuildUploadFileCreateRequest(
            data: .init(
                _type: .buildUploadFiles,
                attributes: .init(
                    assetType: file.assetType.generatedValue,
                    fileName: file.fileName,
                    fileSize: file.fileSize,
                    uti: file.uti.generatedValue
                ),
                relationships: .init(
                    buildUpload: .init(
                        data: .init(
                            _type: .buildUploads,
                            id: uploadId
                        )
                    )
                )
            )
        )

        let response = try await client.buildUploadFiles_createInstance(
            .init(body: .json(request))
        )

        switch response {
        case .created(let created):
            let resource = try created.body.json.data
            guard !(resource.attributes?.uploadOperations?.isEmpty ?? true) else {
                throw Error.badResponse("No upload operations returned for build upload file")
            }
            return resource
        case .badRequest(let badRequest):
            let message = (try? badRequest.body.json.errorDescription) ?? "Bad request"
            throw Error.badRequest(message)
        case .unauthorized(let unauthorized):
            let message = (try? unauthorized.body.json.errorDescription) ?? "Unauthorized"
            throw Error.badResponse(message)
        case .forbidden(let forbidden):
            let message = (try? forbidden.body.json.errorDescription) ?? "Forbidden"
            throw Error.badResponse(message)
        case .unprocessableContent(let unprocessable):
            let message = (try? unprocessable.body.json.errorDescription) ?? "Unprocessable content"
            throw Error.badResponse(message)
        case .conflict(let conflict):
            let message = (try? conflict.body.json.errorDescription) ?? "Conflict"
            throw Error.badResponse(message)
        case .tooManyRequests(let tooMany):
            let message = (try? tooMany.body.json.errorDescription) ?? "Too many requests"
            throw Error.badResponse(message)
        case .undocumented(let statusCode, let undocumentedPayload):
            throw Error.undocumented("\(statusCode): \(undocumentedPayload.body.debugDescription)")
        }
    }

    func getBetaGroupIds(appId: String, betaGroups: [String]) async throws -> [String] {
        let betaGroupsResponse = try await client.betaGroups_getCollection(
            .init(
                query: .init(
                    filter_lbrack_name_rbrack_: betaGroups,
                    filter_lbrack_app_rbrack_: [appId]
                )
            )
        )

        return try betaGroupsResponse.ok.body.json.data.map(\.id)
    }

    func getBetaTesterId(appId: String, email: String) async throws -> String? {
        let betaTestersResponse = try await client.betaTesters_getCollection(
            .init(query: .init(
                filter_lbrack_email_rbrack_: [email],
                filter_lbrack_apps_rbrack_: [appId]
            ))
        )

        let singleTesterData = try betaTestersResponse.ok.body.json.data.first(where: { $0.attributes?.email == email })
        let singleTesterState = singleTesterData?.attributes?.state

        if singleTesterState == .REVOKED {
            logger.info("Tester \(email.redactedEmail) has been revoked, will invite again")
            return nil
        } else {
            return singleTesterData.map(\.id)
        }
    }

    func assignExistingTesterToGroups(_ betaGroupIds: [String], _ betaTesterId: String, appId: String) async throws {
        for betaGroupId in betaGroupIds {
            _ = try await client.betaTesters_betaGroups_createToManyRelationship(
                path: .init(id: betaTesterId),
                body: .json(.init(data: [.init(_type: .betaGroups, id: betaGroupId)]))
            )

            logger.info("Assigned tester to beta group \(betaGroupId): \(betaTesterId)")
        }
    }

    func createNewBetaTester(_ betaGroupIds: [String], appId: String, firstName: String, lastName: String, email: String) async throws -> String? {
        typealias Groups = Components.Schemas.BetaTesterCreateRequest.dataPayload.relationshipsPayload.betaGroupsPayload.dataPayloadPayload
        let mappedGroups: [Groups] = betaGroupIds.map { .init(_type: .betaGroups, id: $0) }

        let result = try await client.betaTesters_createInstance(
            .init(body: .json(.init(
                data: .init(
                    _type: .betaTesters,
                    attributes: .init(firstName: firstName, lastName: lastName, email: email),
                    relationships: .init(betaGroups: .init(data: mappedGroups))
                )
            )))
        )

        let isDeveloper = try? result.conflict

        if isDeveloper != nil {
            logger.info("\(email.redactedEmail) has the developer role. Resending the invite...")
            try await inviteDeveloper(email: email, firstName: firstName, lastName: lastName)
            return nil
        } else {
            let betaTesterId = try result.created.body.json.data.id
            logger.info("Invited \(email.redactedEmail) with beta tester id: \(betaTesterId) to app id: \(appId)")
            return betaTesterId
        }
    }

    func resendBetaTesterInviteMail(appId: String, betaTesterId: String) async throws {
        _ = try await client.betaTesterInvitations_createInstance(
            .init(body: .json(.init(data: .init(
                _type: .betaTesterInvitations,
                relationships: .init(
                    betaTester: .init(
                        data: .init(_type: .betaTesters, id: betaTesterId)
                    ),
                    app: .init(
                        data: .init( _type: .apps, id: appId)
                    )
                )
            ))))
        )

        logger.info("Sent beta tester invitation email")
    }
}

private extension TestflightAPI.UploadFileDescriptor.AssetType {
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

private extension TestflightAPI.UploadFileDescriptor.UTI {
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

private extension TestflightAPI.UploadChecksum {
    func asComponents() -> Components.Schemas.Checksums? {
        if sha256 == nil && md5 == nil {
            return nil
        }

        let filePayload = sha256.map { hash in
            Components.Schemas.Checksums.filePayload(hash: hash, algorithm: .SHA_256)
        }

        let compositePayload = md5.map { hash in
            Components.Schemas.Checksums.compositePayload(hash: hash, algorithm: .MD5)
        }

        return .init(file: filePayload, composite: compositePayload)
    }
}

private extension Components.Schemas.BuildUploadFile {
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

private extension TestflightAPI.UploadOperation {

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

private extension Components.Schemas.BuildUpload {
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

private extension Array where Element == Components.Schemas.StateDetail {
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

private extension Components.Schemas.ErrorResponse {
    var errorDescription: String {
        guard let errors, !errors.isEmpty else {
            return "Unknown error"
        }

        return errors.map { "\($0.code): \($0.detail)" }.joined(separator: " | ")
    }
}

// MARK: Helpers

private extension String {

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
