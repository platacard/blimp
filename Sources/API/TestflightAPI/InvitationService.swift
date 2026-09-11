import Foundation

public enum InvitationResult: Sendable, Equatable {
    case sent(email: String)
    /// A pending invitation with roles other than developer exists; left untouched.
    case pendingWithOtherRoles(email: String, roles: [String])
    case alreadyRegistered(email: String)
}

public enum InvitationError: LocalizedError, Sendable, Equatable {
    case unauthorized(String)
    case forbidden(String)
    case badRequest(String)
    case lookupFailed(String)
    /// Creation answered 409 while a pending invitation for the address still exists.
    case pendingInvitationConflict(email: String)
    /// The pending invitation was deleted but a new one could not be sent.
    case resendFailed(email: String, reason: String)
    case unexpected(String)

    public var errorDescription: String? {
        switch self {
        case .unauthorized(let message): "Unauthorized: \(message)"
        case .forbidden(let message): "Forbidden: \(message)"
        case .badRequest(let message): "Bad request: \(message)"
        case .lookupFailed(let message): "Could not look up pending invitations: \(message)"
        case .pendingInvitationConflict(let email):
            "A pending invitation for \(email.redactedEmail) still exists; retry to resend it"
        case .resendFailed(let email, let reason):
            "Deleted the pending invitation for \(email.redactedEmail) but could not send a new one: \(reason)"
        case .unexpected(let message): message
        }
    }
}

public protocol InvitationService: Sendable {
    /// Sends a developer invitation, resending it when one is already pending.
    func ensureDeveloperInvite(email: String, firstName: String, lastName: String) async throws -> InvitationResult
}
