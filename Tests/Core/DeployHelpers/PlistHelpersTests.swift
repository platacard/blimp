@testable import DeployHelpers
import Foundation
import XCTest

final class PlistHelperTests: XCTestCase {
    private let sut = PlistHelper.default
    
    func test_HelperReadsStringValue() throws {
        // Given
        let plist = try plistPath()
        // When
        let value = sut.getStringValue(key: "TestKey", path: plist)
        // Then
        XCTAssertEqual(value, "TestValue")
    }
    
    func testHelperReadsAppVersion() throws {
        // Given
        let plist = try plistPath()
        // When
        let appVersion = sut.getAppVersion(path: plist)
        // Then
        XCTAssertEqual(appVersion, "1.0")
    }
    
    func testHelperFailsToReadValue() throws {
        let plist = try plistPath()
        let noKeyValue = sut.getStringValue(key: "no_key", path: plist)
        XCTAssertNil(noKeyValue)
    }
}

// MARK: - Helpers

extension PlistHelperTests {
    func plistPath() throws -> String {
        guard let path = Bundle.module.path(forResource: "App", ofType: "plist") else {
            XCTFail("File not found")
            return ""
        }
        
        return path
    }
}
