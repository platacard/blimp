import Foundation

/// Lenient counterparts of the generated device responses: Apple returns device statuses
/// (e.g. `PROCESSING`) that are absent from the published OpenAPI spec, so the generated
/// closed enums fail to decode freshly registered devices.
struct DeviceResource: Decodable {
    struct Attributes: Decodable {
        let name: String?
        let udid: String?
        let platform: String?
        let status: String?
    }

    let id: String
    let attributes: Attributes?

    var apiPlatform: ProvisioningAPI.Platform? {
        switch attributes?.platform {
        case "IOS": .ios
        case "MAC_OS": .macos
        default: nil
        }
    }

    func device(platform: ProvisioningAPI.Platform?, fallbackName: String = "", fallbackUDID: String = "") -> ProvisioningAPI.Device {
        ProvisioningAPI.Device(
            id: id,
            name: attributes?.name ?? fallbackName,
            udid: attributes?.udid ?? fallbackUDID,
            platform: platform,
            status: .init(apiValue: attributes?.status)
        )
    }
}

struct RegisteredDeviceResponse: Decodable {
    let data: DeviceResource
}

struct DevicesPageResponse: Decodable {
    struct Links: Decodable {
        let next: String?
    }

    let data: [DeviceResource]
    let links: Links
}
