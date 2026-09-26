import Foundation

/// Lenient counterparts of the generated profile responses: the name filter also returns other
/// profiles, and a profile type, state or platform missing from the published OpenAPI spec would
/// make the generated closed enums reject the whole reply. Only the fields blimp reads are decoded.
struct ProfileResource: Decodable {
    struct Attributes: Decodable {
        let name: String?
        let profileType: String?
        let profileContent: String?
        let expirationDate: Date?
    }

    let id: String
    let attributes: Attributes?

    var profile: ProvisioningAPI.Profile {
        ProvisioningAPI.Profile(
            id: id,
            name: attributes?.name ?? "",
            type: attributes?.profileType.flatMap(ProvisioningAPI.ProfileType.init(rawValue:)),
            content: attributes?.profileContent.flatMap { Data(base64Encoded: $0) },
            expirationDate: attributes?.expirationDate
        )
    }
}

struct CreatedProfileResponse: Decodable {
    let data: ProfileResource
}

struct ProfilesPageResponse: Decodable {
    struct Links: Decodable {
        let next: String?
    }

    let data: [ProfileResource]
    let links: Links
}
