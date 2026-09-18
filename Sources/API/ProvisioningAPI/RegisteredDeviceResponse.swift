import Foundation

/// Lenient counterpart of the generated `DeviceResponse`: Apple returns device statuses
/// (e.g. `PROCESSING`) that are absent from the published OpenAPI spec, so the generated
/// closed enums fail to decode a freshly registered device.
struct RegisteredDeviceResponse: Decodable {
    struct Payload: Decodable {
        let id: String
        let attributes: Attributes?
    }

    struct Attributes: Decodable {
        let name: String?
        let udid: String?
        let platform: String?
        let status: String?
    }

    let data: Payload

    func device(fallbackName: String, fallbackUDID: String, fallbackPlatform: ProvisioningAPI.Platform) -> ProvisioningAPI.Device {
        let attributes = data.attributes
        let platform: ProvisioningAPI.Platform = switch attributes?.platform {
        case "IOS": .ios
        case "MAC_OS": .macos
        default: fallbackPlatform
        }
        return ProvisioningAPI.Device(
            id: data.id,
            name: attributes?.name ?? fallbackName,
            udid: attributes?.udid ?? fallbackUDID,
            platform: platform,
            status: .init(apiValue: attributes?.status)
        )
    }
}
