import Foundation
import Cronista

/// `POST /v1/userInvitations` answers 409 when an invitation for the address is
/// already pending. A pending developer-only invitation is deleted and sent
/// again; one carrying other roles is left alone.
public struct TestflightInvitationService: InvitationService, Sendable {
    private let client: any APIProtocol
    nonisolated(unsafe) private let logger: Cronista

    init(client: any APIProtocol) {
        self.client = client
        self.logger = Cronista(module: "blimp", category: "InvitationService", isFileLoggingEnabled: true)
    }

    public func ensureDeveloperInvite(email: String, firstName: String, lastName: String) async throws -> InvitationResult {
        guard let pending = try await pendingInvitation(email: email) else {
            return try await create(email: email, firstName: firstName, lastName: lastName)
        }
        guard Set(pending.roles) == [.developer] else {
            let roles = pending.roles.map(\.rawValue)
            logger.info("\(email.redactedEmail) has a pending invitation with roles \(roles); leaving it")
            return .pendingWithOtherRoles(email: email, roles: roles)
        }

        logger.info("Deleting the pending developer invitation for \(email.redactedEmail) to resend it")
        try await delete(invitationId: pending.id)
        do {
            return try await create(email: email, firstName: firstName, lastName: lastName)
        } catch {
            throw InvitationError.resendFailed(email: email, reason: error.localizedDescription)
        }
    }
}

private extension TestflightInvitationService {
    struct PendingInvitation {
        let id: String
        let roles: [Components.Schemas.UserRole]
    }

    static let lookupPageSize = 200

    func pendingInvitation(email: String) async throws -> PendingInvitation? {
        let response = try await client.userInvitationsGetCollection(
            query: .init(filter_lbrack_email_rbrack_: [email], limit: Self.lookupPageSize)
        )

        switch response {
        case .ok(let ok):
            let page = try ok.body.json
            // filter[email] matches substrings; match the address exactly, and
            // never guess from a partial listing.
            guard page.links.next == nil else {
                throw InvitationError.lookupFailed("more than \(Self.lookupPageSize) pending invitations match \(email.redactedEmail)")
            }
            let invitation = page.data.first { $0.attributes?.email == email }
            return invitation.map { .init(id: $0.id, roles: $0.attributes?.roles ?? []) }
        case .badRequest(let failure):
            throw InvitationError.lookupFailed((try? failure.body.json.errorDescription) ?? "Bad request")
        case .unauthorized(let failure):
            throw InvitationError.lookupFailed((try? failure.body.json.errorDescription) ?? "Unauthorized")
        case .forbidden(let failure):
            throw InvitationError.lookupFailed((try? failure.body.json.errorDescription) ?? "Forbidden")
        case .tooManyRequests(let failure):
            throw InvitationError.lookupFailed((try? failure.body.json.errorDescription) ?? "Rate limited")
        case .undocumented(let statusCode, _):
            throw InvitationError.lookupFailed("Undocumented response: \(statusCode)")
        }
    }

    func delete(invitationId: String) async throws {
        let response = try await client.userInvitationsDeleteInstance(path: .init(id: invitationId))

        switch response {
        case .noContent:
            logger.info("Deleted user invitation \(invitationId)")
        case .notFound:
            logger.info("User invitation \(invitationId) was already deleted")
        case .conflict(let failure):
            throw InvitationError.unexpected("Cannot delete invitation: \((try? failure.body.json.errorDescription) ?? "Conflict")")
        case .badRequest(let failure):
            throw InvitationError.badRequest((try? failure.body.json.errorDescription) ?? "Bad request")
        case .unauthorized(let failure):
            throw InvitationError.unauthorized((try? failure.body.json.errorDescription) ?? "Unauthorized")
        case .forbidden(let failure):
            throw InvitationError.forbidden((try? failure.body.json.errorDescription) ?? "Forbidden")
        case .tooManyRequests(let failure):
            throw InvitationError.unexpected("Rate limited: \((try? failure.body.json.errorDescription) ?? "")")
        case .undocumented(let statusCode, _):
            throw InvitationError.unexpected("Undocumented response: \(statusCode)")
        }
    }

    func create(email: String, firstName: String, lastName: String) async throws -> InvitationResult {
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
        case .created:
            logger.info("Developer invite sent to \(email.redactedEmail)")
            return .sent(email: email)
        case .conflict:
            // 409 also answers a pending invitation; only an empty re-query means membership.
            guard try await pendingInvitation(email: email) == nil else {
                throw InvitationError.pendingInvitationConflict(email: email)
            }
            logger.info("\(email.redactedEmail) is already a team member")
            return .alreadyRegistered(email: email)
        case .badRequest(let failure):
            throw InvitationError.badRequest((try? failure.body.json.errorDescription) ?? "Bad request")
        case .unprocessableContent(let failure):
            throw InvitationError.badRequest((try? failure.body.json.errorDescription) ?? "Unprocessable")
        case .unauthorized(let failure):
            throw InvitationError.unauthorized((try? failure.body.json.errorDescription) ?? "Unauthorized")
        case .forbidden(let failure):
            throw InvitationError.forbidden((try? failure.body.json.errorDescription) ?? "Forbidden")
        case .tooManyRequests(let failure):
            throw InvitationError.unexpected("Rate limited: \((try? failure.body.json.errorDescription) ?? "")")
        case .undocumented(let statusCode, _):
            throw InvitationError.unexpected("Undocumented response: \(statusCode)")
        }
    }
}
