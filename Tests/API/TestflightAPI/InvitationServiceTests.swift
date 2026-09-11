import XCTest
@testable import TestflightAPI

final class InvitationServiceTests: XCTestCase {
    private var client: MockTestflightClient!
    private var sut: TestflightInvitationService!

    override func setUp() {
        client = MockTestflightClient()
        sut = TestflightInvitationService(client: client)
    }

    func testCreatesAnInvitationWhenNoneIsPending() async throws {
        let result = try await sut.ensureDeveloperInvite(email: "dev@example.com", firstName: "John", lastName: "Doe")

        XCTAssertEqual(result, .sent(email: "dev@example.com"))
        XCTAssertEqual(client.userInvitationCreateCalls.map(\.email), ["dev@example.com"])
        XCTAssertEqual(client.userInvitationDeleteCalls, [])
    }

    func testResendsAPendingDeveloperInvitation() async throws {
        client.existingUserInvitations = [.init(id: "invite-123", email: "dev@example.com", firstName: "John", lastName: "Doe")]

        let result = try await sut.ensureDeveloperInvite(email: "dev@example.com", firstName: "John", lastName: "Doe")

        XCTAssertEqual(result, .sent(email: "dev@example.com"))
        XCTAssertEqual(client.userInvitationDeleteCalls, ["invite-123"])
        XCTAssertEqual(client.userInvitationCreateCalls.count, 1)
    }

    func testLeavesAPendingInvitationWithOtherRoles() async throws {
        client.existingUserInvitations = [
            .init(id: "invite-123", email: "dev@example.com", firstName: "John", lastName: "Doe", roles: [.developer, .finance]),
        ]

        let result = try await sut.ensureDeveloperInvite(email: "dev@example.com", firstName: "John", lastName: "Doe")

        XCTAssertEqual(result, .pendingWithOtherRoles(email: "dev@example.com", roles: ["DEVELOPER", "FINANCE"]))
        XCTAssertEqual(client.userInvitationDeleteCalls, [])
        XCTAssertEqual(client.userInvitationCreateCalls.count, 0)
    }

    func testMatchesTheAddressExactlyDespiteSubstringFiltering() async throws {
        client.existingUserInvitations = [.init(id: "invite-au", email: "dev@example.com.au", firstName: "Jane", lastName: "Doe")]

        let result = try await sut.ensureDeveloperInvite(email: "dev@example.com", firstName: "John", lastName: "Doe")

        XCTAssertEqual(result, .sent(email: "dev@example.com"))
        XCTAssertEqual(client.userInvitationDeleteCalls, [])
    }

    func testReportsAnAlreadyRegisteredTeamMember() async throws {
        client.userInvitationCreateBehavior = .conflict

        let result = try await sut.ensureDeveloperInvite(email: "member@example.com", firstName: "Jane", lastName: "Doe")

        XCTAssertEqual(result, .alreadyRegistered(email: "member@example.com"))
    }

    func testAFailedLookupIsAnErrorNotAnAbsentInvitation() async {
        client.userInvitationGetCollectionBehavior = .tooManyRequests

        await XCTAssertThrowsErrorAsync(try await sut.ensureDeveloperInvite(email: "dev@example.com", firstName: "John", lastName: "Doe")) { error in
            guard case .lookupFailed = error as? InvitationError else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(client.userInvitationCreateCalls.count, 0)
    }

    func testAFailedResendAfterDeletionSaysSo() async {
        client.existingUserInvitations = [.init(id: "invite-123", email: "dev@example.com", firstName: "John", lastName: "Doe")]
        client.userInvitationCreateBehavior = .forbidden("No permission")

        await XCTAssertThrowsErrorAsync(try await sut.ensureDeveloperInvite(email: "dev@example.com", firstName: "John", lastName: "Doe")) { error in
            guard case .resendFailed(let email, _) = error as? InvitationError else { return XCTFail("\(error)") }
            XCTAssertEqual(email, "dev@example.com")
            XCTAssertTrue(error.localizedDescription.contains("could not send a new one"), error.localizedDescription)
        }
        XCTAssertEqual(client.userInvitationDeleteCalls, ["invite-123"])
    }

    func testForbiddenCreationIsPropagated() async {
        client.userInvitationCreateBehavior = .forbidden("No permission")

        await XCTAssertThrowsErrorAsync(try await sut.ensureDeveloperInvite(email: "dev@example.com", firstName: "John", lastName: "Doe")) { error in
            guard case .forbidden(let message) = error as? InvitationError else { return XCTFail("\(error)") }
            XCTAssertTrue(message.contains("No permission"), message)
        }
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ handler: (Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error", file: file, line: line)
    } catch {
        handler(error)
    }
}
