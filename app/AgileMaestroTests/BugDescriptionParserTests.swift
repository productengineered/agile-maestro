import XCTest
@testable import AgileMaestro

// MARK: - BugDescriptionParserTests

final class BugDescriptionParserTests: XCTestCase {

    // MARK: - summary

    func testSummary_primaryHeading() {
        let md = """
        ## Summary
        Crash on launch when no network.
        """
        let sut = BugDescriptionParser(description: md)
        XCTAssertEqual(sut.summary, "Crash on launch when no network.")
    }

    func testSummary_absentReturnsNil() {
        let md = "## Steps\n1. Open app."
        let sut = BugDescriptionParser(description: md)
        XCTAssertNil(sut.summary)
    }

    // MARK: - steps (alias chain)

    func testSteps_primaryHeading() throws {
        let md = """
        ## Steps to Reproduce
        1. Open app.
        2. Tap settings.
        """
        let sut = BugDescriptionParser(description: md)
        let steps = try XCTUnwrap(sut.steps)
        XCTAssert(steps.contains("Open app."))
    }

    func testSteps_aliasSteps() throws {
        let md = """
        ## Steps
        1. Launch.
        2. Crash.
        """
        let sut = BugDescriptionParser(description: md)
        let steps = try XCTUnwrap(sut.steps)
        XCTAssert(steps.contains("Launch."))
    }

    func testSteps_aliasRepro() throws {
        let md = """
        ## Repro
        Open the file and wait.
        """
        let sut = BugDescriptionParser(description: md)
        let steps = try XCTUnwrap(sut.steps)
        XCTAssert(steps.contains("Open the file"))
    }

    func testSteps_primaryTakesPrecedenceOverAlias() {
        let md = """
        ## Steps to Reproduce
        Primary content.

        ## Steps
        Alias content.
        """
        let sut = BugDescriptionParser(description: md)
        XCTAssertEqual(sut.steps, "Primary content.")
    }

    func testSteps_absentReturnsNil() {
        let md = "## Summary\nSomething happened."
        let sut = BugDescriptionParser(description: md)
        XCTAssertNil(sut.steps)
    }

    // MARK: - expected (alias chain)

    func testExpected_primaryHeading() {
        let md = """
        ## Expected Behavior
        The app should stay open.
        """
        let sut = BugDescriptionParser(description: md)
        XCTAssertEqual(sut.expected, "The app should stay open.")
    }

    func testExpected_aliasExpected() {
        let md = """
        ## Expected
        No crash.
        """
        let sut = BugDescriptionParser(description: md)
        XCTAssertEqual(sut.expected, "No crash.")
    }

    func testExpected_absentReturnsNil() {
        let md = "## Actual Behavior\nCrash occurred."
        let sut = BugDescriptionParser(description: md)
        XCTAssertNil(sut.expected)
    }

    // MARK: - actual (alias chain)

    func testActual_primaryHeading() {
        let md = """
        ## Actual Behavior
        App crashes immediately.
        """
        let sut = BugDescriptionParser(description: md)
        XCTAssertEqual(sut.actual, "App crashes immediately.")
    }

    func testActual_aliasActual() {
        let md = """
        ## Actual
        Crash on tap.
        """
        let sut = BugDescriptionParser(description: md)
        XCTAssertEqual(sut.actual, "Crash on tap.")
    }

    func testActual_absentReturnsNil() {
        let md = "## Expected Behavior\nShould work."
        let sut = BugDescriptionParser(description: md)
        XCTAssertNil(sut.actual)
    }

    // MARK: - severity

    func testSeverity_present() {
        let md = """
        ## Severity
        P0 - Critical
        """
        let sut = BugDescriptionParser(description: md)
        XCTAssertEqual(sut.severity, "P0 - Critical")
    }

    func testSeverity_absentReturnsNil() {
        let md = "## Summary\nSomething."
        let sut = BugDescriptionParser(description: md)
        XCTAssertNil(sut.severity)
    }

    // MARK: - discoveryContext (alias chain)

    func testDiscoveryContext_primaryHeading() {
        let md = """
        ## Discovery Context
        Found during smoke testing on 2026-03-28.
        """
        let sut = BugDescriptionParser(description: md)
        XCTAssertEqual(sut.discoveryContext, "Found during smoke testing on 2026-03-28.")
    }

    func testDiscoveryContext_aliasContext() {
        let md = """
        ## Context
        Reproduced on macOS 26.
        """
        let sut = BugDescriptionParser(description: md)
        XCTAssertEqual(sut.discoveryContext, "Reproduced on macOS 26.")
    }

    func testDiscoveryContext_primaryTakesPrecedenceOverAlias() {
        let md = """
        ## Discovery Context
        Primary context.

        ## Context
        Alias context.
        """
        let sut = BugDescriptionParser(description: md)
        XCTAssertEqual(sut.discoveryContext, "Primary context.")
    }

    func testDiscoveryContext_absentReturnsNil() {
        let md = "## Summary\nSomething."
        let sut = BugDescriptionParser(description: md)
        XCTAssertNil(sut.discoveryContext)
    }

    // MARK: - hasKnownSections

    func testHasKnownSections_trueWhenAnySectionPresent() {
        let md = "## Summary\nA crash."
        let sut = BugDescriptionParser(description: md)
        XCTAssertTrue(sut.hasKnownSections)
    }

    func testHasKnownSections_falseWhenNoKnownSections() {
        let md = "## Notes\nSome random content."
        let sut = BugDescriptionParser(description: md)
        XCTAssertFalse(sut.hasKnownSections)
    }

    func testHasKnownSections_falseForEmptyDescription() {
        let sut = BugDescriptionParser(description: "")
        XCTAssertFalse(sut.hasKnownSections)
    }

    // MARK: - Full description round-trip

    func testFullBugDescription_allSectionsPresent() throws {
        let md = """
        ## Summary
        App crashes on launch.

        ## Steps to Reproduce
        1. Open app.
        2. Wait two seconds.

        ## Expected Behavior
        App remains open.

        ## Actual Behavior
        App terminates with EXC_BAD_ACCESS.

        ## Severity
        P0 - Critical

        ## Discovery Context
        Found during nightly CI run.
        """
        let sut = BugDescriptionParser(description: md)

        XCTAssertEqual(sut.summary, "App crashes on launch.")
        let steps = try XCTUnwrap(sut.steps)
        XCTAssert(steps.contains("Open app."))
        XCTAssertEqual(sut.expected, "App remains open.")
        XCTAssertEqual(sut.actual, "App terminates with EXC_BAD_ACCESS.")
        XCTAssertEqual(sut.severity, "P0 - Critical")
        XCTAssertEqual(sut.discoveryContext, "Found during nightly CI run.")
        XCTAssertTrue(sut.hasKnownSections)
    }

    func testDescriptionWithOnlyUnknownSections_hasNoKnownSections() {
        let md = """
        ## Notes
        Some notes here.

        ## References
        - Link 1
        """
        let sut = BugDescriptionParser(description: md)

        XCTAssertNil(sut.summary)
        XCTAssertNil(sut.steps)
        XCTAssertNil(sut.expected)
        XCTAssertNil(sut.actual)
        XCTAssertNil(sut.severity)
        XCTAssertNil(sut.discoveryContext)
        XCTAssertFalse(sut.hasKnownSections)
    }
}
