import XCTest

final class AgileMaestroUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertFalse(app.windows.allElementsBoundByIndex.isEmpty)
    }
}
