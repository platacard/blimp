@testable import DeployHelpers
import Foundation
import XCTest

final class PlistHelperTests: XCTestCase {
    private let sut = PlistHelper()

    func test_HelperReadsStringValue() throws {
        // Given
        let plist = try plistPath()
        // When
        let value = sut.getStringValue(key: "TestKey", path: plist)
        // Then
        XCTAssertEqual(value, "TestValue")
    }

    func testHelperFailsToReadValue() throws {
        let plist = try plistPath()
        let noKeyValue = sut.getStringValue(key: "no_key", path: plist)
        XCTAssertNil(noKeyValue)
    }

    func testHelperFailsToReadFromInvalidPath() {
        // Given
        let invalidPath = "/nonexistent/path.plist"
        // When
        let value = sut.getStringValue(key: "TestKey", path: invalidPath)
        // Then
        XCTAssertNil(value)
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
