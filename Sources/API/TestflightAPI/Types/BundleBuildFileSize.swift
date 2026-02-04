import Foundation

public struct BundleBuildFileSize: Sendable {
    public let deviceModel: String
    public let downloadBytes: Int
    public let instalBytes: Int

    public init(deviceModel: String, downloadBytes: Int, instalBytes: Int) {
        self.deviceModel = deviceModel
        self.downloadBytes = downloadBytes
        self.instalBytes = instalBytes
    }
}
