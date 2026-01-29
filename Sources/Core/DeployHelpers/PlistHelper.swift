import Foundation

public struct PlistHelper: Sendable {

    public init() {}

    public func getStringValue(key: String, path: String) -> String? {
        guard let dict = NSDictionary(contentsOfFile: path) else { return nil }
        return dict[key] as? String
    }
}
