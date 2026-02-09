import Foundation
import Cronista

public struct TestflightInvitationService: InvitationService, Sendable {
    private let client: any APIProtocol
    nonisolated(unsafe) private let logger: Cronista

    init(client: any APIProtocol) {
        self.client = client
        self.logger = Cronista(
            module: "blimp",
            category: "InvitationService",
            isFileLoggingEnabled: true
        )
    }

    // MARK: - Developer Invitations

    public func ensureDeveloperInvite(
        email: String,
        firstName: String,
        lastName: String
    ) async throws -> InvitationResult {
        if let existingInvitation = try await findExistingUserInvitation(email: email) {
            logger.info("Found existing invitation for \(email.redactedEmail), deleting to resend...")
            try await deleteUserInvitation(id: existingInvitation.id)
        }

        let response = try await client.userInvitationsCreateInstance(
            body: .json(.init(data: .init(
                _type: .userInvitations,
                attributes: .init(
                    email: email,
                    firstName: firstName,
                    lastName: lastName,
                    roles: [.developer],
                    allAppsVisible: true,
                    provisioningAllowed: false
                )
            )))
        )

        switch response {
        case .created(let created):
            let resultEmail = (try? created.body.json.data.attributes?.email) ?? email
            logger.info("Developer invite sent to \(resultEmail.redactedEmail)")
            return .sent(email: resultEmail)

        case .conflict:
            logger.info("User \(email.redactedEmail) is already a registered team member")
            return .alreadyRegistered(email: email)

        case .forbidden(let forbidden):
            let message = (try? forbidden.body.json.errorDescription) ?? "Forbidden"
            throw InvitationError.forbidden(message)

        case .badRequest(let badRequest):
            let message = (try? badRequest.body.json.errorDescription) ?? "Bad request"
            throw InvitationError.badRequest(message)

        case .unauthorized(let unauthorized):
            let message = (try? unauthorized.body.json.errorDescription) ?? "Unauthorized"
            throw InvitationError.forbidden(message)

        case .unprocessableContent(let unprocessable):
            let message = (try? unprocessable.body.json.errorDescription) ?? "Unprocessable"
            throw InvitationError.badRequest(message)

        case .tooManyRequests(let tooMany):
            let message = (try? tooMany.body.json.errorDescription) ?? "Rate limited"
            throw InvitationError.unexpected("Rate limited: \(message)")

        case .undocumented(let statusCode, _):
            throw InvitationError.unexpected("Undocumented response: \(statusCode)")
        }
    }

    // MARK: - Beta Tester Invitations

    public func ensureBetaTesterInvite(
        appId: String,
        betaGroupIds: [String],
        email: String,
        firstName: String,
        lastName: String
    ) async throws -> InvitationResult {
        if let existingTester = try await findBetaTester(appId: appId, email: email) {
            try await assignTesterToGroups(testerId: existingTester.id, betaGroupIds: betaGroupIds)

            switch existingTester.state {
            case .accepted, .installed:
                logger.info("Tester \(email.redactedEmail) is already actively testing")
                return .alreadyAccepted(email: email)

            case .invited, .notInvited:
                return try await sendBetaTesterInvitation(
                    appId: appId,
                    testerId: existingTester.id,
                    email: email
                )

            case .revoked:
                logger.info("Tester \(email.redactedEmail) was revoked, creating new...")
            }
        }

        return try await createNewBetaTester(
            appId: appId,
            betaGroupIds: betaGroupIds,
            email: email,
            firstName: firstName,
            lastName: lastName
        )
    }

    // MARK: - Private Helpers

    private func findExistingUserInvitation(email: String) async throws -> (id: String, email: String)? {
        let response = try await client.userInvitationsGetCollection(
            query: .init(filter_lbrack_email_rbrack_: [email])
        )

        guard case .ok(let ok) = response else {
            return nil
        }

        let invitation = try ok.body.json.data.first(where: { $0.attributes?.email == email })
        guard let invitation else { return nil }

        return (id: invitation.id, email: email)
    }

    private func deleteUserInvitation(id: String) async throws {
        let response = try await client.userInvitationsDeleteInstance(
            path: .init(id: id)
        )

        switch response {
        case .noContent:
            logger.info("Deleted existing user invitation \(id)")

        case .notFound:
            logger.info("User invitation \(id) already deleted")

        case .conflict(let conflict):
            let message = (try? conflict.body.json.errorDescription) ?? "Conflict"
            throw InvitationError.unexpected("Cannot delete invitation: \(message)")

        case .badRequest(let badRequest):
            let message = (try? badRequest.body.json.errorDescription) ?? "Bad request"
            throw InvitationError.badRequest(message)

        case .unauthorized(let unauthorized):
            let message = (try? unauthorized.body.json.errorDescription) ?? "Unauthorized"
            throw InvitationError.forbidden(message)

        case .forbidden(let forbidden):
            let message = (try? forbidden.body.json.errorDescription) ?? "Forbidden"
            throw InvitationError.forbidden(message)

        case .tooManyRequests(let tooMany):
            let message = (try? tooMany.body.json.errorDescription) ?? "Rate limited"
            throw InvitationError.unexpected("Rate limited: \(message)")

        case .undocumented(let statusCode, _):
            throw InvitationError.unexpected("Undocumented response: \(statusCode)")
        }
    }

    private func findBetaTester(appId: String, email: String) async throws -> BetaTesterInfo? {
        let response = try await client.betaTestersGetCollection(
            query: .init(
                filter_lbrack_email_rbrack_: [email],
                filter_lbrack_apps_rbrack_: [appId]
            )
        )

        guard case .ok(let ok) = response else { return nil }

        let tester = try ok.body.json.data.first(where: { $0.attributes?.email == email })
        guard let tester, let state = tester.attributes?.state else { return nil }

        return BetaTesterInfo(id: tester.id, state: state)
    }

    private func assignTesterToGroups(testerId: String, betaGroupIds: [String]) async throws {
        _ = try await client.betaTestersBetaGroupsCreateToManyRelationship(
            path: .init(id: testerId),
            body: .json(.init(data: betaGroupIds.map { .init(_type: .betaGroups, id: $0) }))
        )
        logger.info("Assigned tester \(testerId) to groups: \(betaGroupIds)")
    }

    private func sendBetaTesterInvitation(
        appId: String,
        testerId: String,
        email: String
    ) async throws -> InvitationResult {
        let response = try await client.betaTesterInvitationsCreateInstance(
            body: .json(.init(data: .init(
                _type: .betaTesterInvitations,
                relationships: .init(
                    betaTester: .init(data: .init(_type: .betaTesters, id: testerId)),
                    app: .init(data: .init(_type: .apps, id: appId))
                )
            )))
        )

        switch response {
        case .created:
            logger.info("Beta tester invitation sent to \(email.redactedEmail)")
            return .sent(email: email)

        case .conflict:
            throw InvitationError.unexpected("Got 409 resending invitation - state check failed for \(email.redactedEmail)")

        case .badRequest(let badRequest):
            let message = (try? badRequest.body.json.errorDescription) ?? "Bad request"
            throw InvitationError.badRequest(message)

        case .forbidden(let forbidden):
            let message = (try? forbidden.body.json.errorDescription) ?? "Forbidden"
            throw InvitationError.forbidden(message)

        case .unauthorized(let unauthorized):
            let message = (try? unauthorized.body.json.errorDescription) ?? "Unauthorized"
            throw InvitationError.forbidden(message)

        case .unprocessableContent(let unprocessable):
            let message = (try? unprocessable.body.json.errorDescription) ?? "Unprocessable"
            throw InvitationError.badRequest(message)

        case .tooManyRequests(let tooMany):
            let message = (try? tooMany.body.json.errorDescription) ?? "Rate limited"
            throw InvitationError.unexpected("Rate limited: \(message)")

        case .undocumented(let statusCode, _):
            throw InvitationError.unexpected("Undocumented response: \(statusCode)")
        }
    }

    private func createNewBetaTester(
        appId: String,
        betaGroupIds: [String],
        email: String,
        firstName: String,
        lastName: String
    ) async throws -> InvitationResult {
        typealias Groups = Components.Schemas.BetaTesterCreateRequest.DataPayload.RelationshipsPayload.BetaGroupsPayload.DataPayloadPayload
        let mappedGroups: [Groups] = betaGroupIds.map { .init(_type: .betaGroups, id: $0) }

        let response = try await client.betaTestersCreateInstance(
            body: .json(.init(data: .init(
                _type: .betaTesters,
                attributes: .init(firstName: firstName, lastName: lastName, email: email),
                relationships: .init(betaGroups: .init(data: mappedGroups))
            )))
        )

        switch response {
        case .created(let created):
            let testerId = try created.body.json.data.id
            logger.info("Created beta tester \(testerId) for \(email.redactedEmail)")
            return .sent(email: email)

        case .conflict:
            logger.info("\(email.redactedEmail) is a developer, sending developer invite instead...")
            return try await ensureDeveloperInvite(
                email: email,
                firstName: firstName,
                lastName: lastName
            )

        case .badRequest(let badRequest):
            let message = (try? badRequest.body.json.errorDescription) ?? "Bad request"
            throw InvitationError.badRequest(message)

        case .forbidden(let forbidden):
            let message = (try? forbidden.body.json.errorDescription) ?? "Forbidden"
            throw InvitationError.forbidden(message)

        case .unauthorized(let unauthorized):
            let message = (try? unauthorized.body.json.errorDescription) ?? "Unauthorized"
            throw InvitationError.forbidden(message)

        case .unprocessableContent(let unprocessable):
            let message = (try? unprocessable.body.json.errorDescription) ?? "Unprocessable"
            throw InvitationError.badRequest(message)

        case .tooManyRequests(let tooMany):
            let message = (try? tooMany.body.json.errorDescription) ?? "Rate limited"
            throw InvitationError.unexpected("Rate limited: \(message)")

        case .undocumented(let statusCode, _):
            throw InvitationError.unexpected("Undocumented response: \(statusCode)")
        }
    }
}

// MARK: - Helper Types

private struct BetaTesterInfo {
    let id: String
    let state: Components.Schemas.BetaTesterState
}
