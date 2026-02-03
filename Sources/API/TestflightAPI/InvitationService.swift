import Foundation

/// Result of an invitation operation
public enum InvitationResult: Sendable, Equatable {
    case sent(email: String)
    case alreadyAccepted(email: String)
    case alreadyRegistered(email: String)
}

/// Error types for invitation operations
public enum InvitationError: Error, Sendable, Equatable {
    case forbidden(String)
    case badRequest(String)
    case unexpected(String)
}

/// Protocol for invitation operations - enables testing
public protocol InvitationService: Sendable {
    /// Ensure a developer invitation is sent/resent.
    /// Deletes any existing invitation first, then creates a new one.
    /// Returns `.alreadyRegistered` if user is already a team member.
    func ensureDeveloperInvite(
        email: String,
        firstName: String,
        lastName: String
    ) async throws -> InvitationResult

    /// Ensure a beta tester invitation is sent.
    /// Checks tester state first to prevent 409 errors.
    /// Returns `.alreadyAccepted` if user is already testing.
    func ensureBetaTesterInvite(
        appId: String,
        betaGroupIds: [String],
        email: String,
        firstName: String,
        lastName: String
    ) async throws -> InvitationResult
}
