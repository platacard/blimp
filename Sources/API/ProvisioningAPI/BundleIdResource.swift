import Foundation

/// Lenient counterpart of the generated bundle ID listing: `filter[identifier]` also returns
/// longer identifiers, among them Services IDs whose platform (`SERVICES`) is absent from the
/// published OpenAPI spec, so the generated closed enum rejects the whole page.
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
