import XCTest
@testable import TestflightAPI

final class InvitationServiceTests: XCTestCase {
    var mockClient: MockTestflightClient!
    var service: TestflightInvitationService!

    override func setUp() async throws {
        mockClient = MockTestflightClient()
        service = TestflightInvitationService(client: mockClient)
    }

    // MARK: - Developer Invitation Tests

    func testEnsureDeveloperInvite_CreatesNew_WhenNoneExists() async throws {
        let result = try await service.ensureDeveloperInvite(
            email: "dev@example.com",
            firstName: "John",
            lastName: "Doe"
        )

        XCTAssertEqual(result, .sent(email: "dev@example.com"))
        XCTAssertEqual(mockClient.userInvitationCreateCalls.count, 1)
        XCTAssertEqual(mockClient.userInvitationCreateCalls.first?.email, "dev@example.com")
        XCTAssertEqual(mockClient.userInvitationDeleteCalls.count, 0)
    }

    func testEnsureDeveloperInvite_DeletesAndRecreates_WhenExists() async throws {
        mockClient.existingUserInvitations = [
            MockUserInvitation(
                id: "invite-123",
                email: "dev@example.com",
                firstName: "John",
                lastName: "Doe"
            )
        ]

        let result = try await service.ensureDeveloperInvite(
            email: "dev@example.com",
            firstName: "John",
            lastName: "Updated"
        )

        XCTAssertEqual(result, .sent(email: "dev@example.com"))
        XCTAssertEqual(mockClient.userInvitationDeleteCalls, ["invite-123"])
        XCTAssertEqual(mockClient.userInvitationCreateCalls.count, 1)
    }

    func testEnsureDeveloperInvite_ReturnsAlreadyRegistered_WhenUserIsTeamMember() async throws {
        mockClient.userInvitationCreateBehavior = .conflict

        let result = try await service.ensureDeveloperInvite(
            email: "existing@example.com",
            firstName: "Jane",
            lastName: "Doe"
        )

        XCTAssertEqual(result, .alreadyRegistered(email: "existing@example.com"))
    }

    func testEnsureDeveloperInvite_ThrowsForbidden_OnForbiddenResponse() async throws {
        mockClient.userInvitationCreateBehavior = .forbidden("No permission")

        do {
            _ = try await service.ensureDeveloperInvite(
                email: "test@example.com",
                firstName: "Test",
                lastName: "User"
            )
            XCTFail("Should have thrown an error")
        } catch let error as InvitationError {
            if case .forbidden(let message) = error {
                XCTAssertTrue(message.contains("No permission") || message.contains("Forbidden"))
            } else {
                XCTFail("Expected forbidden error, got \(error)")
            }
        }
    }

    // MARK: - Beta Tester Invitation Tests

    func testEnsureBetaTesterInvite_CreatesNew_WhenNotFound() async throws {
        mockClient.existingBetaGroups = [
            MockBetaGroup(id: "group-1", name: "Beta Testers", appId: "app-123")
        ]

        let result = try await service.ensureBetaTesterInvite(
            appId: "app-123",
            betaGroupIds: ["group-1"],
            email: "tester@example.com",
            firstName: "Test",
            lastName: "User"
        )

        XCTAssertEqual(result, .sent(email: "tester@example.com"))
        XCTAssertEqual(mockClient.betaTesterCreateCalls.count, 1)
        XCTAssertEqual(mockClient.betaTesterCreateCalls.first?.email, "tester@example.com")
    }

    func testEnsureBetaTesterInvite_ResendsInvite_WhenStateIsInvited() async throws {
        mockClient.existingBetaTesters = [
            MockBetaTester(
                id: "tester-123",
                email: "tester@example.com",
                firstName: "Test",
                lastName: "User",
                state: .invited,
                appIds: ["app-123"]
            )
        ]

        let result = try await service.ensureBetaTesterInvite(
            appId: "app-123",
            betaGroupIds: ["group-1"],
            email: "tester@example.com",
            firstName: "Test",
            lastName: "User"
        )

        XCTAssertEqual(result, .sent(email: "tester@example.com"))
        XCTAssertEqual(mockClient.betaTesterInvitationCreateCalls.count, 1)
        XCTAssertEqual(mockClient.betaTesterInvitationCreateCalls.first?.betaTesterId, "tester-123")
        XCTAssertEqual(mockClient.betaTesterCreateCalls.count, 0)
    }

    func testEnsureBetaTesterInvite_ResendsInvite_WhenStateIsNotInvited() async throws {
        mockClient.existingBetaTesters = [
            MockBetaTester(
                id: "tester-123",
                email: "tester@example.com",
                firstName: "Test",
                lastName: "User",
                state: .notInvited,
                appIds: ["app-123"]
            )
        ]

        let result = try await service.ensureBetaTesterInvite(
            appId: "app-123",
            betaGroupIds: ["group-1"],
            email: "tester@example.com",
            firstName: "Test",
            lastName: "User"
        )

        XCTAssertEqual(result, .sent(email: "tester@example.com"))
        XCTAssertEqual(mockClient.betaTesterInvitationCreateCalls.count, 1)
    }

    func testEnsureBetaTesterInvite_SkipsInviteAPI_WhenStateIsAccepted() async throws {
        mockClient.existingBetaTesters = [
            MockBetaTester(
                id: "tester-123",
                email: "active@example.com",
                firstName: "Active",
                lastName: "Tester",
                state: .accepted,
                appIds: ["app-123"]
            )
        ]

        let result = try await service.ensureBetaTesterInvite(
            appId: "app-123",
            betaGroupIds: ["group-1"],
            email: "active@example.com",
            firstName: "Active",
            lastName: "Tester"
        )

        XCTAssertEqual(result, .alreadyAccepted(email: "active@example.com"))
        XCTAssertEqual(mockClient.betaTesterInvitationCreateCalls.count, 0)
        XCTAssertEqual(mockClient.betaTesterCreateCalls.count, 0)
    }

    func testEnsureBetaTesterInvite_SkipsInviteAPI_WhenStateIsInstalled() async throws {
        mockClient.existingBetaTesters = [
            MockBetaTester(
                id: "tester-123",
                email: "active@example.com",
                firstName: "Active",
                lastName: "Tester",
                state: .installed,
                appIds: ["app-123"]
            )
        ]

        let result = try await service.ensureBetaTesterInvite(
            appId: "app-123",
            betaGroupIds: ["group-1"],
            email: "active@example.com",
            firstName: "Active",
            lastName: "Tester"
        )

        XCTAssertEqual(result, .alreadyAccepted(email: "active@example.com"))
        XCTAssertEqual(mockClient.betaTesterInvitationCreateCalls.count, 0)
    }

    func testEnsureBetaTesterInvite_CreatesNewTester_WhenStateIsRevoked() async throws {
        mockClient.existingBetaTesters = [
            MockBetaTester(
                id: "tester-123",
                email: "revoked@example.com",
                firstName: "Revoked",
                lastName: "Tester",
                state: .revoked,
                appIds: ["app-123"]
            )
        ]

        let result = try await service.ensureBetaTesterInvite(
            appId: "app-123",
            betaGroupIds: ["group-1"],
            email: "revoked@example.com",
            firstName: "Revoked",
            lastName: "Tester"
        )

        XCTAssertEqual(result, .sent(email: "revoked@example.com"))
        XCTAssertEqual(mockClient.betaTesterCreateCalls.count, 1)
    }

    func testEnsureBetaTesterInvite_ThrowsError_OnUnexpected409() async throws {
        mockClient.existingBetaTesters = [
            MockBetaTester(
                id: "tester-123",
                email: "tester@example.com",
                firstName: "Test",
                lastName: "User",
                state: .invited,
                appIds: ["app-123"]
            )
        ]
        mockClient.betaTesterInvitationCreateBehavior = .conflict

        do {
            _ = try await service.ensureBetaTesterInvite(
                appId: "app-123",
                betaGroupIds: ["group-1"],
                email: "tester@example.com",
                firstName: "Test",
                lastName: "User"
            )
            XCTFail("Should have thrown an error")
        } catch let error as InvitationError {
            if case .unexpected(let message) = error {
                XCTAssertTrue(message.contains("409") || message.contains("state check"))
            } else {
                XCTFail("Expected unexpected error, got \(error)")
            }
        }
    }

    func testEnsureBetaTesterInvite_FallsBackToDeveloper_WhenCreateReturns409() async throws {
        mockClient.betaTesterCreateBehavior = .conflictIsDeveloper

        let result = try await service.ensureBetaTesterInvite(
            appId: "app-123",
            betaGroupIds: ["group-1"],
            email: "dev@example.com",
            firstName: "Dev",
            lastName: "User"
        )

        XCTAssertEqual(mockClient.betaTesterCreateCalls.count, 1)
        XCTAssertEqual(mockClient.userInvitationCreateCalls.count, 1)
        XCTAssertEqual(result, .sent(email: "dev@example.com"))
    }

    func testEnsureBetaTesterInvite_AssignsToGroups_WhenTesterExists() async throws {
        mockClient.existingBetaTesters = [
            MockBetaTester(
                id: "tester-123",
                email: "tester@example.com",
                firstName: "Test",
                lastName: "User",
                state: .invited,
                appIds: ["app-123"]
            )
        ]

        _ = try await service.ensureBetaTesterInvite(
            appId: "app-123",
            betaGroupIds: ["group-1", "group-2"],
            email: "tester@example.com",
            firstName: "Test",
            lastName: "User"
        )

        XCTAssertEqual(mockClient.betaTesterBetaGroupsCreateCalls.count, 1)
        XCTAssertEqual(mockClient.betaTesterBetaGroupsCreateCalls.first?.testerId, "tester-123")
        XCTAssertEqual(mockClient.betaTesterBetaGroupsCreateCalls.first?.groupIds, ["group-1", "group-2"])
    }

    // MARK: - Error Propagation Tests (No try? allowed)

    func testErrors_ArePropagated_NotSilenced() async throws {
        mockClient.betaTesterCreateBehavior = .forbidden("Access denied")

        do {
            _ = try await service.ensureBetaTesterInvite(
                appId: "app-123",
                betaGroupIds: ["group-1"],
                email: "test@example.com",
                firstName: "Test",
                lastName: "User"
            )
            XCTFail("Should have thrown an error")
        } catch let error as InvitationError {
            if case .forbidden = error {
                // Expected - error was propagated
            } else {
                XCTFail("Expected forbidden error")
            }
        }
    }
}
