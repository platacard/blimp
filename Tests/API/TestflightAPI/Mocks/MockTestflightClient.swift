import Foundation
@testable import TestflightAPI

class MockTestflightClient: APIProtocol, @unchecked Sendable {

    // MARK: - Call Tracking

    var userInvitationGetCollectionCalls: [String?] = []
    var userInvitationCreateCalls: [(email: String, firstName: String, lastName: String)] = []
    var userInvitationDeleteCalls: [String] = []
    var betaTesterGetCollectionCalls: [(email: String?, appId: String?)] = []
    var betaTesterCreateCalls: [(email: String, firstName: String, lastName: String, betaGroupIds: [String])] = []
    var betaTesterInvitationCreateCalls: [(betaTesterId: String, appId: String)] = []
    var betaTesterBetaGroupsCreateCalls: [(testerId: String, groupIds: [String])] = []
    var betaGroupsGetCollectionCalls: [(names: [String]?, appId: String?)] = []

    // MARK: - Mock Data

    var existingUserInvitations: [MockUserInvitation] = []
    var existingBetaTesters: [MockBetaTester] = []
    var existingBetaGroups: [MockBetaGroup] = []

    // MARK: - Response Configuration

    var userInvitationCreateBehavior: UserInvitationCreateBehavior = .success
    var userInvitationDeleteBehavior: UserInvitationDeleteBehavior = .success
    var betaTesterCreateBehavior: BetaTesterCreateBehavior = .success
    var betaTesterInvitationCreateBehavior: BetaTesterInvitationCreateBehavior = .success

    enum UserInvitationCreateBehavior {
        case success
        case conflict
        case forbidden(String)
        case badRequest(String)
    }

    enum UserInvitationDeleteBehavior {
        case success
        case notFound
        case conflict(String)
    }

    enum BetaTesterCreateBehavior {
        case success
        case conflictIsDeveloper
        case forbidden(String)
    }

    enum BetaTesterInvitationCreateBehavior {
        case success
        case conflict
        case badRequest(String)
    }

    // MARK: - Invitation-Related Methods

    func userInvitationsGetCollection(_ input: Operations.UserInvitationsGetCollection.Input) async throws -> Operations.UserInvitationsGetCollection.Output {
        let emailFilter = input.query.filter_lbrack_email_rbrack_?.first
        userInvitationGetCollectionCalls.append(emailFilter)

        let matchingInvitations = existingUserInvitations.filter { invitation in
            if let emailFilter {
                return invitation.email == emailFilter
            }
            return true
        }

        let invitationData = matchingInvitations.map { invitation in
            Components.Schemas.UserInvitation(
                _type: .userInvitations,
                id: invitation.id,
                attributes: .init(
                    email: invitation.email,
                    firstName: invitation.firstName,
                    lastName: invitation.lastName,
                    expirationDate: nil,
                    roles: [.developer],
                    allAppsVisible: true,
                    provisioningAllowed: false
                )
            )
        }

        return .ok(.init(body: .json(.init(
            data: invitationData,
            links: .init(_self: "http://test")
        ))))
    }

    func userInvitationsCreateInstance(_ input: Operations.UserInvitationsCreateInstance.Input) async throws -> Operations.UserInvitationsCreateInstance.Output {
        guard case .json(let request) = input.body else {
            fatalError("Expected JSON body")
        }

        let email = request.data.attributes.email
        let firstName = request.data.attributes.firstName
        let lastName = request.data.attributes.lastName

        userInvitationCreateCalls.append((email: email, firstName: firstName, lastName: lastName))

        switch userInvitationCreateBehavior {
        case .success:
            let newInvitation = Components.Schemas.UserInvitation(
                _type: .userInvitations,
                id: "invite-\(UUID().uuidString)",
                attributes: .init(
                    email: email,
                    firstName: firstName,
                    lastName: lastName,
                    expirationDate: nil,
                    roles: [.developer],
                    allAppsVisible: true,
                    provisioningAllowed: false
                )
            )
            return .created(.init(body: .json(.init(
                data: newInvitation,
                links: .init(_self: "http://test")
            ))))

        case .conflict:
            return .conflict(.init(body: .json(.init(
                errors: [.init(status: "409", code: "ENTITY_ERROR.RELATIONSHIP.INVALID", title: "User already exists", detail: "")]
            ))))

        case .forbidden(let message):
            return .forbidden(.init(body: .json(.init(
                errors: [.init(status: "403", code: "FORBIDDEN_ERROR", title: "Forbidden", detail: message)]
            ))))

        case .badRequest(let message):
            return .badRequest(.init(body: .json(.init(
                errors: [.init(status: "400", code: "PARAMETER_ERROR", title: message, detail: "")]
            ))))
        }
    }

    func userInvitationsDeleteInstance(_ input: Operations.UserInvitationsDeleteInstance.Input) async throws -> Operations.UserInvitationsDeleteInstance.Output {
        let invitationId = input.path.id
        userInvitationDeleteCalls.append(invitationId)

        switch userInvitationDeleteBehavior {
        case .success:
            existingUserInvitations.removeAll { $0.id == invitationId }
            return .noContent

        case .notFound:
            return .notFound(.init(body: .json(.init(
                errors: [.init(status: "404", code: "NOT_FOUND", title: "Invitation not found", detail: "")]
            ))))

        case .conflict(let message):
            return .conflict(.init(body: .json(.init(
                errors: [.init(status: "409", code: "CONFLICT", title: message, detail: "")]
            ))))
        }
    }

    func betaTestersGetCollection(_ input: Operations.BetaTestersGetCollection.Input) async throws -> Operations.BetaTestersGetCollection.Output {
        let emailFilter = input.query.filter_lbrack_email_rbrack_?.first
        let appFilter = input.query.filter_lbrack_apps_rbrack_?.first

        betaTesterGetCollectionCalls.append((email: emailFilter, appId: appFilter))

        let matchingTesters = existingBetaTesters.filter { tester in
            var matches = true
            if let emailFilter {
                matches = matches && tester.email == emailFilter
            }
            if let appFilter {
                matches = matches && tester.appIds.contains(appFilter)
            }
            return matches
        }

        let testerData = matchingTesters.map { tester in
            Components.Schemas.BetaTester(
                _type: .betaTesters,
                id: tester.id,
                attributes: .init(
                    firstName: tester.firstName,
                    lastName: tester.lastName,
                    email: tester.email,
                    state: tester.state
                )
            )
        }

        return .ok(.init(body: .json(.init(
            data: testerData,
            links: .init(_self: "http://test")
        ))))
    }

    func betaTestersCreateInstance(_ input: Operations.BetaTestersCreateInstance.Input) async throws -> Operations.BetaTestersCreateInstance.Output {
        guard case .json(let request) = input.body else {
            fatalError("Expected JSON body")
        }

        let email = request.data.attributes.email ?? ""
        let firstName = request.data.attributes.firstName ?? ""
        let lastName = request.data.attributes.lastName ?? ""
        let groupIds = request.data.relationships?.betaGroups?.data?.map(\.id) ?? []

        betaTesterCreateCalls.append((email: email, firstName: firstName, lastName: lastName, betaGroupIds: groupIds))

        switch betaTesterCreateBehavior {
        case .success:
            let newTester = Components.Schemas.BetaTester(
                _type: .betaTesters,
                id: "tester-\(UUID().uuidString)",
                attributes: .init(
                    firstName: firstName,
                    lastName: lastName,
                    email: email,
                    state: .invited
                )
            )
            return .created(.init(body: .json(.init(
                data: newTester,
                links: .init(_self: "http://test")
            ))))

        case .conflictIsDeveloper:
            return .conflict(.init(body: .json(.init(
                errors: [.init(status: "409", code: "ENTITY_ERROR", title: "User has developer role", detail: "")]
            ))))

        case .forbidden(let message):
            return .forbidden(.init(body: .json(.init(
                errors: [.init(status: "403", code: "FORBIDDEN_ERROR", title: "Forbidden", detail: message)]
            ))))
        }
    }

    func betaTesterInvitationsCreateInstance(_ input: Operations.BetaTesterInvitationsCreateInstance.Input) async throws -> Operations.BetaTesterInvitationsCreateInstance.Output {
        guard case .json(let request) = input.body else {
            fatalError("Expected JSON body")
        }

        let betaTesterId = request.data.relationships.betaTester?.data?.id ?? ""
        let appId = request.data.relationships.app.data.id

        betaTesterInvitationCreateCalls.append((betaTesterId: betaTesterId, appId: appId))

        switch betaTesterInvitationCreateBehavior {
        case .success:
            let invitation = Components.Schemas.BetaTesterInvitation(
                _type: .betaTesterInvitations,
                id: "invitation-\(UUID().uuidString)"
            )
            return .created(.init(body: .json(.init(
                data: invitation,
                links: .init(_self: "http://test")
            ))))

        case .conflict:
            return .conflict(.init(body: .json(.init(
                errors: [.init(status: "409", code: "CONFLICT", title: "Tester already accepted", detail: "")]
            ))))

        case .badRequest(let message):
            return .badRequest(.init(body: .json(.init(
                errors: [.init(status: "400", code: "BAD_REQUEST", title: message, detail: "")]
            ))))
        }
    }

    func betaTestersBetaGroupsCreateToManyRelationship(_ input: Operations.BetaTestersBetaGroupsCreateToManyRelationship.Input) async throws -> Operations.BetaTestersBetaGroupsCreateToManyRelationship.Output {
        let testerId = input.path.id
        guard case .json(let request) = input.body else {
            fatalError("Expected JSON body")
        }

        let groupIds = request.data.map(\.id)
        betaTesterBetaGroupsCreateCalls.append((testerId: testerId, groupIds: groupIds))

        return .noContent
    }

    func betaGroupsGetCollection(_ input: Operations.BetaGroupsGetCollection.Input) async throws -> Operations.BetaGroupsGetCollection.Output {
        let nameFilter = input.query.filter_lbrack_name_rbrack_
        let appFilter = input.query.filter_lbrack_app_rbrack_?.first

        betaGroupsGetCollectionCalls.append((names: nameFilter, appId: appFilter))

        let matchingGroups = existingBetaGroups.filter { group in
            var matches = true
            if let nameFilter, !nameFilter.isEmpty {
                matches = matches && nameFilter.contains(group.name)
            }
            if let appFilter {
                matches = matches && group.appId == appFilter
            }
            return matches
        }

        let groupData = matchingGroups.map { group in
            Components.Schemas.BetaGroup(
                _type: .betaGroups,
                id: group.id,
                attributes: .init(name: group.name)
            )
        }

        return .ok(.init(body: .json(.init(
            data: groupData,
            links: .init(_self: "http://test")
        ))))
    }

    // MARK: - Stub Implementations (Not Used in Invitation Tests)

    func betaAppReviewSubmissionsCreateInstance(_ input: Operations.BetaAppReviewSubmissionsCreateInstance.Input) async throws -> Operations.BetaAppReviewSubmissionsCreateInstance.Output {
        fatalError("Not implemented in mock")
    }

    func betaBuildLocalizationsCreateInstance(_ input: Operations.BetaBuildLocalizationsCreateInstance.Input) async throws -> Operations.BetaBuildLocalizationsCreateInstance.Output {
        fatalError("Not implemented in mock")
    }

    func betaBuildLocalizationsGetInstance(_ input: Operations.BetaBuildLocalizationsGetInstance.Input) async throws -> Operations.BetaBuildLocalizationsGetInstance.Output {
        fatalError("Not implemented in mock")
    }

    func betaBuildLocalizationsUpdateInstance(_ input: Operations.BetaBuildLocalizationsUpdateInstance.Input) async throws -> Operations.BetaBuildLocalizationsUpdateInstance.Output {
        fatalError("Not implemented in mock")
    }

    func betaGroupsGetInstance(_ input: Operations.BetaGroupsGetInstance.Input) async throws -> Operations.BetaGroupsGetInstance.Output {
        fatalError("Not implemented in mock")
    }

    func buildBetaNotificationsCreateInstance(_ input: Operations.BuildBetaNotificationsCreateInstance.Input) async throws -> Operations.BuildBetaNotificationsCreateInstance.Output {
        fatalError("Not implemented in mock")
    }

    func buildUploadFilesCreateInstance(_ input: Operations.BuildUploadFilesCreateInstance.Input) async throws -> Operations.BuildUploadFilesCreateInstance.Output {
        fatalError("Not implemented in mock")
    }

    func buildUploadFilesUpdateInstance(_ input: Operations.BuildUploadFilesUpdateInstance.Input) async throws -> Operations.BuildUploadFilesUpdateInstance.Output {
        fatalError("Not implemented in mock")
    }

    func buildUploadsCreateInstance(_ input: Operations.BuildUploadsCreateInstance.Input) async throws -> Operations.BuildUploadsCreateInstance.Output {
        fatalError("Not implemented in mock")
    }

    func buildUploadsGetInstance(_ input: Operations.BuildUploadsGetInstance.Input) async throws -> Operations.BuildUploadsGetInstance.Output {
        fatalError("Not implemented in mock")
    }

    func buildsGetCollection(_ input: Operations.BuildsGetCollection.Input) async throws -> Operations.BuildsGetCollection.Output {
        fatalError("Not implemented in mock")
    }

    func buildsGetInstance(_ input: Operations.BuildsGetInstance.Input) async throws -> Operations.BuildsGetInstance.Output {
        fatalError("Not implemented in mock")
    }

    func betaGroupsBuildsGetToManyRelationship(_ input: Operations.BetaGroupsBuildsGetToManyRelationship.Input) async throws -> Operations.BetaGroupsBuildsGetToManyRelationship.Output {
        fatalError("Not implemented in mock")
    }

    func betaGroupsBuildsCreateToManyRelationship(_ input: Operations.BetaGroupsBuildsCreateToManyRelationship.Input) async throws -> Operations.BetaGroupsBuildsCreateToManyRelationship.Output {
        fatalError("Not implemented in mock")
    }

    func betaGroupsBuildsDeleteToManyRelationship(_ input: Operations.BetaGroupsBuildsDeleteToManyRelationship.Input) async throws -> Operations.BetaGroupsBuildsDeleteToManyRelationship.Output {
        fatalError("Not implemented in mock")
    }

    func betaTestersBetaGroupsDeleteToManyRelationship(_ input: Operations.BetaTestersBetaGroupsDeleteToManyRelationship.Input) async throws -> Operations.BetaTestersBetaGroupsDeleteToManyRelationship.Output {
        fatalError("Not implemented in mock")
    }

    func buildBetaDetailsBuildGetToOneRelated(_ input: Operations.BuildBetaDetailsBuildGetToOneRelated.Input) async throws -> Operations.BuildBetaDetailsBuildGetToOneRelated.Output {
        fatalError("Not implemented in mock")
    }

    func buildBundlesBuildBundleFileSizesGetToManyRelated(_ input: Operations.BuildBundlesBuildBundleFileSizesGetToManyRelated.Input) async throws -> Operations.BuildBundlesBuildBundleFileSizesGetToManyRelated.Output {
        fatalError("Not implemented in mock")
    }

    func buildsAppEncryptionDeclarationGetToOneRelationship(_ input: Operations.BuildsAppEncryptionDeclarationGetToOneRelationship.Input) async throws -> Operations.BuildsAppEncryptionDeclarationGetToOneRelationship.Output {
        fatalError("Not implemented in mock")
    }

    func buildsAppEncryptionDeclarationUpdateToOneRelationship(_ input: Operations.BuildsAppEncryptionDeclarationUpdateToOneRelationship.Input) async throws -> Operations.BuildsAppEncryptionDeclarationUpdateToOneRelationship.Output {
        fatalError("Not implemented in mock")
    }

    func buildsBetaBuildLocalizationsGetToManyRelated(_ input: Operations.BuildsBetaBuildLocalizationsGetToManyRelated.Input) async throws -> Operations.BuildsBetaBuildLocalizationsGetToManyRelated.Output {
        fatalError("Not implemented in mock")
    }

    func buildsBetaGroupsCreateToManyRelationship(_ input: Operations.BuildsBetaGroupsCreateToManyRelationship.Input) async throws -> Operations.BuildsBetaGroupsCreateToManyRelationship.Output {
        fatalError("Not implemented in mock")
    }
}

// MARK: - Mock Data Types

struct MockUserInvitation {
    let id: String
    let email: String
    let firstName: String
    let lastName: String
}

struct MockBetaTester {
    let id: String
    let email: String
    let firstName: String
    let lastName: String
    let state: Components.Schemas.BetaTesterState
    let appIds: [String]
}

struct MockBetaGroup {
    let id: String
    let name: String
    let appId: String
}
