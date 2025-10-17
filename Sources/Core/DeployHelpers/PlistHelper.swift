import Foundation
import Cronista

/// Simplifies the plist interactions
public struct PlistHelper: Sendable {
    private var logger: Cronista { Cronista(module: "blimp", category: "PlistHelper") }
    private var fileManager: FileManager { .default }

    public static let `default` = PlistHelper()
    
    public func getStringValue(key: String, path: String) -> String? {
        let value: String? = getValue(key: key, path: path)
        
        guard let value, !value.isEmpty else {
            logger.error("Cannot extract value for key: \(key) from path: \(path)")
            return nil
        }
        
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public func getValue<Value>(key: String, path: String) -> Value? {
        guard let data = fileManager.contents(atPath: path) else {
            logger.error("Cannot read data from path: \(path)")
            return nil
        }

        do {
            let content = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            guard let value = content?[key] as? Value else {
                logger.error("Cannot extract value for key: \(key) from path: \(path)")
                logger.info("plist content:\n\n\(content.debugDescription)")
                return nil
            }
            
            return value
        } catch {
            logger.error("Cannot parse plist from path: \(path). Error: \(error)")
            return nil
        }
    }
}

public extension PlistHelper {
    func getAppVersion(path: String) -> String? {
        guard let version = getStringValue(key: "CFBundleShortVersionString", path: path) else {
            logger.warning("Cannot get app version from path: \(path)")
            return nil
        }
        
        return version
    }
}

extension PlistHelper {
    enum Error: Swift.Error {
        case noAppVersion
    }
}
