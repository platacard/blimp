import Foundation
@testable import TestflightAPI

class MockTestflightClient: APIProtocol, @unchecked Sendable {
    var userInvitationGetCollectionCalls: [String?] = []
    var userInvitationCreateCalls: [(email: String, firstName: String, lastName: String)] = []
    var userInvitationDeleteCalls: [String] = []

    var existingUserInvitations: [MockUserInvitation] = []

    var userInvitationGetCollectionBehavior: UserInvitationGetCollectionBehavior = .success
    var userInvitationCreateBehavior: UserInvitationCreateBehavior = .success
    var userInvitationDeleteBehavior: UserInvitationDeleteBehavior = .success

    enum UserInvitationGetCollectionBehavior {
        case success
        case tooManyRequests
        case forbidden(String)
    }

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

    func userInvitationsGetCollection(_ input: Operations.UserInvitationsGetCollection.Input) async throws -> Operations.UserInvitationsGetCollection.Output {
        let emailFilter = input.query.filter_lbrack_email_rbrack_?.first
        userInvitationGetCollectionCalls.append(emailFilter)

        switch userInvitationGetCollectionBehavior {
        case .tooManyRequests:
            return .tooManyRequests(.init(body: .json(.init(
                errors: [.init(status: "429", code: "RATE_LIMIT_EXCEEDED", title: "Rate limited", detail: "")]
            ))))
        case .forbidden(let message):
            return .forbidden(.init(body: .json(.init(
                errors: [.init(status: "403", code: "FORBIDDEN_ERROR", title: "Forbidden", detail: message)]
            ))))
        case .success:
            break
        }

        // App Store Connect matches filter[email] as a substring.
        let matching = existingUserInvitations.filter { emailFilter.map($0.email.contains) ?? true }
        let data = matching.map { invitation in
            Components.Schemas.UserInvitation(
                _type: .userInvitations,
                id: invitation.id,
                attributes: .init(
                    email: invitation.email,
                    firstName: invitation.firstName,
                    lastName: invitation.lastName,
                    expirationDate: nil,
                    roles: invitation.roles,
                    allAppsVisible: true,
                    provisioningAllowed: false
                )
            )
        }
        return .ok(.init(body: .json(.init(data: data, links: .init(_self: "http://test")))))
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
        fatalError("Not used")
    }

    func betaTestersCreateInstance(_ input: Operations.BetaTestersCreateInstance.Input) async throws -> Operations.BetaTestersCreateInstance.Output {
        fatalError("Not used")
    }

    func betaTesterInvitationsCreateInstance(_ input: Operations.BetaTesterInvitationsCreateInstance.Input) async throws -> Operations.BetaTesterInvitationsCreateInstance.Output {
        fatalError("Not used")
    }

    func betaTestersBetaGroupsCreateToManyRelationship(_ input: Operations.BetaTestersBetaGroupsCreateToManyRelationship.Input) async throws -> Operations.BetaTestersBetaGroupsCreateToManyRelationship.Output {
        fatalError("Not used")
    }

    func betaGroupsGetCollection(_ input: Operations.BetaGroupsGetCollection.Input) async throws -> Operations.BetaGroupsGetCollection.Output {
        fatalError("Not used")
    }
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

struct MockUserInvitation {
    let id: String
    let email: String
    let firstName: String
    let lastName: String
    var roles: [Components.Schemas.UserRole] = [.developer]
}
