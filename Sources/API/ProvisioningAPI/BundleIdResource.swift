import Foundation

/// Lenient counterpart of the generated bundle ID listing: `filter[identifier]` also returns
/// longer identifiers, and those can carry platform values the published OpenAPI spec does not
/// list (e.g. `SERVICES` for Services IDs), which the generated closed enum rejects for the whole page.
struct BundleIdResource: Decodable {
    struct Attributes: Decodable {
        let identifier: String?
    }

    let id: String
    let attributes: Attributes?
}

struct BundleIdsPageResponse: Decodable {
    struct Links: Decodable {
        let next: String?
    }

    let data: [BundleIdResource]
    let links: Links
}
