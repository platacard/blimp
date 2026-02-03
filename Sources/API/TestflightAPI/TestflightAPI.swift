import Foundation
import OpenAPIRuntime
import OpenAPIURLSession
import JWTProvider
import Cronista
import Auth
import ClientTransport

public struct TestflightAPI: Sendable {

    private let jwtProvider: any JWTProviding
    private let client: any APIProtocol

    nonisolated(unsafe) private let logger: Cronista

    public init(jwtProvider: any JWTProviding) {
        self.jwtProvider = jwtProvider
        self.logger = Cronista(
            module: "blimp",
            category: "TestFlightAPI",
            isFileLoggingEnabled: true
        )

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

        let response = try await client.buildUploadsCreateInstance(.init(body: .json(request)))

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
            logger.error(message)
            throw Error.badRequest(message)
        case .unauthorized(let unauthorized):
            let message = (try? unauthorized.body.json.errorDescription) ?? "Unauthorized"
            logger.error(message)
            throw Error.badResponse(message)
        case .forbidden(let forbidden):
            let message = (try? forbidden.body.json.errorDescription) ?? "Forbidden"
            logger.error(message)
            throw Error.badResponse(message)
        case .unprocessableContent(let unprocessable):
            let message = (try? unprocessable.body.json.errorDescription) ?? "Unprocessable content"
            logger.error(message)
            throw Error.badResponse(message)
        case .conflict(let conflict):
            let message = (try? conflict.body.json.errorDescription) ?? "Conflict"
            logger.error(message)
            throw Error.badResponse(message)
        case .tooManyRequests(let tooMany):
            let message = (try? tooMany.body.json.errorDescription) ?? "Too many requests"
            logger.error(message)
            throw Error.badResponse(message)
        case .undocumented(let statusCode, let undocumentedPayload):
            logger.error("\(statusCode): \(undocumentedPayload.body.debugDescription)")
            throw Error.undocumented("\(statusCode): \(undocumentedPayload.body.debugDescription)")
        }
    }

    public func markUploadComplete(uploadFileId: String) async throws {
        let updateRequest = Components.Schemas.BuildUploadFileUpdateRequest(
            data: .init(
                _type: .buildUploadFiles,
                id: uploadFileId,
                attributes: .init(
                    uploaded: true
                )
            )
        )

        let response = try await client.buildUploadFilesUpdateInstance(
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
            logger.error(message)
            throw Error.badRequest(message)
        case .unauthorized(let unauthorized):
            let message = (try? unauthorized.body.json.errorDescription) ?? "Unauthorized"
            logger.error(message)
            throw Error.badResponse(message)
        case .forbidden(let forbidden):
            let message = (try? forbidden.body.json.errorDescription) ?? "Forbidden"
            logger.error(message)
            throw Error.badResponse(message)
        case .notFound:
            logger.error("Not found error: \(response)")
            throw Error.badResponse("Upload file \(uploadFileId) not found")
        case .unprocessableContent(let unprocessable):
            let message = (try? unprocessable.body.json.errorDescription) ?? "Unprocessable content"
            logger.error(message)
            throw Error.badResponse(message)
        case .conflict(let conflict):
            let message = (try? conflict.body.json.errorDescription) ?? "Conflict"
            logger.error(message)
            throw Error.badResponse(message)
        case .tooManyRequests(let tooMany):
            let message = (try? tooMany.body.json.errorDescription) ?? "Too many requests"
            logger.error(message)
            throw Error.badResponse(message)
        case .undocumented(let statusCode, let undocumentedPayload):
            throw Error.undocumented("\(statusCode): \(undocumentedPayload.body.debugDescription)")
        }
    }

    public func getUploadStatus(uploadId: String) async throws -> UploadStatus {
        let response = try await client.buildUploadsGetInstance(
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
            logger.error(message)
            throw Error.badRequest(message)
        case .unauthorized(let unauthorized):
            let message = (try? unauthorized.body.json.errorDescription) ?? "Unauthorized"
            logger.error(message)
            throw Error.badResponse(message)
        case .forbidden(let forbidden):
            let message = (try? forbidden.body.json.errorDescription) ?? "Forbidden"
            logger.error(message)
            throw Error.badResponse(message)
        case .notFound:
            logger.error("Not found error: \(response)")
            throw Error.badResponse("Upload \(uploadId) not found")
        case .tooManyRequests(let tooMany):
            let message = (try? tooMany.body.json.errorDescription) ?? "Too many requests"
            logger.error(message)
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
        let response = try await client.buildsGetCollection(
            Operations.BuildsGetCollection.Input(
                query: .init(
                    filter_lbrack_version_rbrack_: [buildNumber],
                    filter_lbrack_processingState_rbrack_: states.map { $0.asGeneratedApiState },
                    filter_lbrack_preReleaseVersion_version_rbrack_: [appVersion],
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

        throw Error.badResponse("Unexpected response in getBuildID for appId: \(appId), appVersion: \(appVersion), buildNumber: \(buildNumber)")
    }

    public func getBuildProcessingResult(id: String) async throws -> BuildProcessingResult {
        let response = try await client.buildsGetInstance(
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
        let service = TestflightInvitationService(client: client)
        let result = try await service.ensureDeveloperInvite(
            email: email,
            firstName: firstName,
            lastName: lastName
        )

        switch result {
        case .sent(let email):
            logger.info("Developer invite sent to \(email.redactedEmail)")
        case .alreadyAccepted(let email), .alreadyRegistered(let email):
            logger.info("User \(email.redactedEmail) is already a team member")
        }
    }

    public func inviteBetaTester(
        appIds: [String],
        betaGroups: [String],
        email: String,
        firstName: String,
        lastName: String
    ) async throws {
        let service = TestflightInvitationService(client: client)

        for appId in appIds {
            let betaGroupIds = try await getBetaGroupIds(appId: appId, betaGroups: betaGroups)

            logger.info("Beta groups names: \(betaGroups)")
            logger.info("Got beta groups ids for \(appId): \(betaGroupIds)")

            let result = try await service.ensureBetaTesterInvite(
                appId: appId,
                betaGroupIds: betaGroupIds,
                email: email,
                firstName: firstName,
                lastName: lastName
            )

            switch result {
            case .sent(let email):
                logger.info("Invite sent to \(email.redactedEmail) for app \(appId)")
            case .alreadyAccepted(let email):
                logger.info("User \(email.redactedEmail) is already testing app \(appId)")
            case .alreadyRegistered(let email):
                logger.info("User \(email.redactedEmail) is a registered team member")
            }
        }
    }

    public func setBetaGroups(appId: String, buildId: String, betaGroups: [String], isInternal: Bool = false) async throws {
        let betaGroupsIds = try await getBetaGroupIds(appId: appId, betaGroups: betaGroups)

        typealias Groups = Components.Schemas.BuildBetaGroupsLinkagesRequest.DataPayload
        let mappedGroups: Groups = betaGroupsIds.map { .init(_type: .betaGroups, id: $0) }

        let response = try await client.buildsBetaGroupsCreateToManyRelationship(
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
            let response = try await client.betaBuildLocalizationsUpdateInstance(
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
        let result = try await client.betaAppReviewSubmissionsCreateInstance(
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
        let response = try await client.buildsGetCollection(
            Operations.BuildsGetCollection.Input(
                query: .init(
                    filter_lbrack_betaAppReviewSubmission_betaReviewState_rbrack_: [state.asGeneratedApiState],
                    filter_lbrack_app_rbrack_: [appId],
                    fields_lbrack_builds_rbrack_: [.app, .betaGroups, .buildBundles],
                    fields_lbrack_apps_rbrack_: [.bundleId, .builds],
                    limit: limit,
                    include: [.app, .buildBetaDetail, .buildBundles]
                ),
                headers: Operations.BuildsGetCollection.Input.Headers()
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
        let response = try await client.buildBundlesBuildBundleFileSizesGetToManyRelated(
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

        let response = try await client.buildUploadFilesCreateInstance(.init(body: .json(request)))

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
        let betaGroupsResponse = try await client.betaGroupsGetCollection(
            .init(
                query: .init(
                    filter_lbrack_name_rbrack_: betaGroups,
                    filter_lbrack_app_rbrack_: [appId]
                )
            )
        )

        return try betaGroupsResponse.ok.body.json.data.map(\.id)
    }
}
