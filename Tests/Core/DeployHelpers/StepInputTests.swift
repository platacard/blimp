@testable import DeployHelpers
import XCTest

final class StepInputTests: XCTestCase {
    func testExplicitOptionWinsOverTheEnvironment() throws {
        let sut = StepInput(environment: ["BUILD_ID": "from-env"])
        XCTAssertEqual(try sut.value("BUILD_ID", option: "from-option"), "from-option")
    }

    func testFallsBackToTheEnvironment() throws {
        let sut = StepInput(environment: ["BUILD_ID": "from-env"])
        XCTAssertEqual(try sut.value("BUILD_ID", option: nil), "from-env")
    }

    func testEmptyValuesCountAsMissing() throws {
        let sut = StepInput(environment: ["BUILD_ID": ""])
        XCTAssertThrowsError(try sut.value("BUILD_ID", option: "")) { error in
            XCTAssertEqual(error as? StepInput.Error, .missing("BUILD_ID"))
        }
    }

    func testMissingValueNamesTheOptionAndVariable() {
        let sut = StepInput(environment: [:])
        XCTAssertThrowsError(try sut.value("BUILD_ID", option: nil)) { error in
            XCTAssertEqual(
                "\(error)",
                "No build id: pass --build-id or set BUILD_ID in the environment"
            )
        }
    }
}
