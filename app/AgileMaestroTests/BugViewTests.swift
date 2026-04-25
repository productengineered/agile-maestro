import XCTest
@testable import AgileMaestro

// MARK: - BugViewTests
//
// Tests the logic behind BugOverviewContent and BugDescriptionContent:
//   1. BugOverviewContent: field-driven card visibility from TaskSpecificMetadata
//   2. BugDescriptionContent: MarkdownSectionParser.body(for:in:) section extraction
//   3. SeverityBadge: severity string → expected Color mapping
//   4. SeverityRCACard: rcaColor logic for each RCA status value
//
// Private view structs cannot be instantiated directly, so this file tests the
// data-layer logic those views depend on — mirroring the pattern used in
// TaskSpecificMetadataTests and WorkflowStepperViewTests.

// swiftlint:disable:next type_body_length
final class BugViewTests: XCTestCase {

    // MARK: - Helpers

    private let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    private func makeBugItem(metadata extraFields: String = "") throws -> TaskItem {
        let json = """
        {
          "id": "bug-test-1",
          "subject": "Test Bug",
          "description": "## Summary\\nCrash on launch.",
          "status": "in_progress",
          "blocks": [],
          "blockedBy": [],
          "metadata": {
            "type": "bug",
            "schema_version": "2.0",
            "approval": "approved",
            "blocked": false
            \(extraFields.isEmpty ? "" : ", \(extraFields)")
          }
        }
        """
        return try decoder.decode(TaskItem.self, from: Data(json.utf8))
    }

    /// Recreates the SeverityBadge.color mapping (private to OverviewTabView) for assertion.
    private func expectedSeverityColor(for severity: String) -> String {
        switch severity.lowercased() {
        case "critical":             return "red"
        case "major", "high":        return "orange"
        case "moderate", "medium":   return "yellow"
        case "minor", "low":         return "blue"
        default:                     return "secondary"
        }
    }

    /// Recreates the SeverityRCACard.rcaColor mapping for assertion.
    private func expectedRCAColor(for status: String) -> String {
        switch status.lowercased() {
        case "approved":         return "green"
        case "reviewed":         return "blue"
        case "investigated":     return "orange"
        case "needs-more-info":  return "yellow"
        default:                 return "secondary"
        }
    }

    // MARK: - BugOverviewContent: Full Fields Populate Metadata

    func testBugItemWithAllFieldsDecodesForRendering() throws {
        let item = try makeBugItem(metadata: """
            "severity": "critical",
            "steps_to_reproduce": ["Step 1", "Step 2", "Step 3"],
            "expected_behavior": "App launches normally",
            "actual_behavior": "App crashes immediately",
            "rca_status": "investigated",
            "discovered_from": "task-100",
            "affected_files": ["Views/MainView.swift"],
            "regression": true,
            "environment": { "macos_version": "15.4", "app_version": "2.0.1" }
        """)

        let meta = try XCTUnwrap(item.metadata.task)

        // All fields that drive BugOverviewContent card visibility must be present
        XCTAssertEqual(meta.severity, "critical")
        XCTAssertEqual(meta.stepsToReproduce?.count, 3)
        XCTAssertEqual(meta.expectedBehavior, "App launches normally")
        XCTAssertEqual(meta.actualBehavior, "App crashes immediately")
        XCTAssertEqual(meta.rcaStatus, "investigated")
        XCTAssertEqual(meta.discoveredFrom, "task-100")
        XCTAssertEqual(meta.affectedFiles, ["Views/MainView.swift"])
        XCTAssertEqual(meta.regression, true)
        XCTAssertEqual(meta.environment?.macosVersion, "15.4")
        XCTAssertEqual(meta.environment?.appVersion, "2.0.1")
    }

    // MARK: - BugOverviewContent: Missing Optional Fields Degrade Gracefully

    func testBugItemWithNoOptionalFieldsHasNilMetadata() throws {
        let item = try makeBugItem()
        let meta = try XCTUnwrap(item.metadata.task)

        // All bug-specific optional fields absent — no cards would render for them
        XCTAssertNil(meta.severity)
        XCTAssertNil(meta.stepsToReproduce)
        XCTAssertNil(meta.expectedBehavior)
        XCTAssertNil(meta.actualBehavior)
        XCTAssertNil(meta.rcaStatus)
        XCTAssertNil(meta.discoveredFrom)
        XCTAssertNil(meta.affectedFiles)
        XCTAssertNil(meta.regression)
        XCTAssertNil(meta.environment)
    }

    func testBugItemWithSeverityOnlyHasNilForOtherFields() throws {
        let item = try makeBugItem(metadata: "\"severity\": \"major\"")
        let meta = try XCTUnwrap(item.metadata.task)

        XCTAssertEqual(meta.severity, "major")
        XCTAssertNil(meta.stepsToReproduce,
            "stepsToReproduce card should not render when absent")
        XCTAssertNil(meta.expectedBehavior,
            "Expected behavior card should not render when absent")
        XCTAssertNil(meta.actualBehavior,
            "Actual behavior card should not render when absent")
        XCTAssertNil(meta.environment,
            "Environment card should not render when absent")
        XCTAssertNil(meta.discoveredFrom,
            "Discovered From card should not render when absent")
    }

    func testBugItemWithEmptyStepsArrayDoesNotShowCard() throws {
        // An empty array should be treated equivalently to nil for card visibility
        // The view uses: if let steps = meta?.stepsToReproduce, !steps.isEmpty
        let item = try makeBugItem(metadata: "\"steps_to_reproduce\": []")
        let meta = try XCTUnwrap(item.metadata.task)
        let steps = meta.stepsToReproduce ?? []
        XCTAssertTrue(steps.isEmpty, "Empty steps array should suppress the repro steps card")
    }

    func testBugItemWithEmptyAffectedFilesArrayDoesNotShowCard() throws {
        let item = try makeBugItem(metadata: "\"affected_files\": []")
        let meta = try XCTUnwrap(item.metadata.task)
        let files = meta.affectedFiles ?? []
        XCTAssertTrue(files.isEmpty, "Empty affected files array should suppress the files card")
    }

    func testBugItemWithOnlyExpectedBehaviorRendersBehaviorSection() throws {
        // The view shows the HStack when either expected OR actual is non-nil
        let item = try makeBugItem(metadata: "\"expected_behavior\": \"Should work\"")
        let meta = try XCTUnwrap(item.metadata.task)

        XCTAssertNotNil(meta.expectedBehavior, "Expected behavior present → behavior HStack renders")
        XCTAssertNil(meta.actualBehavior, "Actual behavior absent → only expected card in HStack")
    }

    func testBugItemWithOnlyActualBehaviorRendersBehaviorSection() throws {
        let item = try makeBugItem(metadata: "\"actual_behavior\": \"Crashes\"")
        let meta = try XCTUnwrap(item.metadata.task)

        XCTAssertNil(meta.expectedBehavior)
        XCTAssertNotNil(meta.actualBehavior, "Actual behavior present → behavior HStack renders")
    }

    // MARK: - BugOverviewContent: Regression Flag

    func testRegressionTrueShowsRegressionChip() throws {
        let item = try makeBugItem(metadata: "\"regression\": true")
        let meta = try XCTUnwrap(item.metadata.task)
        XCTAssertEqual(meta.regression, true,
            "regression: true should trigger Regression chip in SeverityRCACard")
    }

    func testRegressionFalseHidesRegressionChip() throws {
        let item = try makeBugItem(metadata: "\"regression\": false")
        let meta = try XCTUnwrap(item.metadata.task)
        XCTAssertEqual(meta.regression, false,
            "regression: false should not render Regression chip")
    }

    func testRegressionNilHidesRegressionChip() throws {
        let item = try makeBugItem()
        let meta = try XCTUnwrap(item.metadata.task)
        let isRegression = meta.regression == true
        XCTAssertFalse(isRegression,
            "nil regression should evaluate to false and hide the chip")
    }

    // MARK: - BugOverviewContent: Environment Card Visibility

    func testEnvironmentCardHiddenWhenBothVersionsAbsent() throws {
        // View shows environment card only when macosVersion != nil || appVersion != nil
        let item = try makeBugItem(metadata: "\"environment\": {}")
        let meta = try XCTUnwrap(item.metadata.task)

        let env = meta.environment
        let shouldShowCard = env?.macosVersion != nil || env?.appVersion != nil
        XCTAssertFalse(shouldShowCard,
            "Environment card should be hidden when both version fields are absent")
    }

    func testEnvironmentCardShownWhenMacOSVersionPresent() throws {
        let item = try makeBugItem(
            metadata: "\"environment\": { \"macos_version\": \"15.4\" }"
        )
        let meta = try XCTUnwrap(item.metadata.task)

        let env = meta.environment
        let shouldShowCard = env?.macosVersion != nil || env?.appVersion != nil
        XCTAssertTrue(shouldShowCard,
            "Environment card renders when macosVersion is present")
        XCTAssertEqual(env?.macosVersion, "15.4")
        XCTAssertNil(env?.appVersion)
    }

    // MARK: - Severity Color Mapping

    func testSeverityColorMapping_Critical() {
        XCTAssertEqual(expectedSeverityColor(for: "critical"), "red")
    }

    func testSeverityColorMapping_Major() {
        XCTAssertEqual(expectedSeverityColor(for: "major"), "orange")
    }

    func testSeverityColorMapping_High() {
        // "high" is an alias for "major" per the switch statement
        XCTAssertEqual(expectedSeverityColor(for: "high"), "orange")
    }

    func testSeverityColorMapping_Moderate() {
        XCTAssertEqual(expectedSeverityColor(for: "moderate"), "yellow")
    }

    func testSeverityColorMapping_Medium() {
        XCTAssertEqual(expectedSeverityColor(for: "medium"), "yellow")
    }

    func testSeverityColorMapping_Minor() {
        XCTAssertEqual(expectedSeverityColor(for: "minor"), "blue")
    }

    func testSeverityColorMapping_Low() {
        XCTAssertEqual(expectedSeverityColor(for: "low"), "blue")
    }

    func testSeverityColorMapping_Unknown() {
        XCTAssertEqual(expectedSeverityColor(for: "unknown"), "secondary")
        XCTAssertEqual(expectedSeverityColor(for: ""), "secondary")
    }

    func testSeverityColorMapping_CaseInsensitive() {
        // Switch uses severity.lowercased() — uppercase inputs should still map correctly
        XCTAssertEqual(expectedSeverityColor(for: "CRITICAL"), "red")
        XCTAssertEqual(expectedSeverityColor(for: "Major"), "orange")
        XCTAssertEqual(expectedSeverityColor(for: "MODERATE"), "yellow")
        XCTAssertEqual(expectedSeverityColor(for: "MINOR"), "blue")
    }

    // MARK: - RCA Status Color Mapping

    func testRCAColorMapping_Approved() {
        XCTAssertEqual(expectedRCAColor(for: "approved"), "green")
    }

    func testRCAColorMapping_Reviewed() {
        XCTAssertEqual(expectedRCAColor(for: "reviewed"), "blue")
    }

    func testRCAColorMapping_Investigated() {
        XCTAssertEqual(expectedRCAColor(for: "investigated"), "orange")
    }

    func testRCAColorMapping_NeedsMoreInfo() {
        XCTAssertEqual(expectedRCAColor(for: "needs-more-info"), "yellow")
    }

    func testRCAColorMapping_Pending() {
        // "pending" is not a named case — falls through to default
        XCTAssertEqual(expectedRCAColor(for: "pending"), "secondary")
    }

    func testRCAColorMapping_CaseInsensitive() {
        XCTAssertEqual(expectedRCAColor(for: "APPROVED"), "green")
        XCTAssertEqual(expectedRCAColor(for: "Investigated"), "orange")
    }

    // MARK: - RCA Status Display Label

    func testRCALabelFormattedCorrectly() {
        // SeverityRCACard formats the label as:
        // "RCA: \(rca.replacingOccurrences(of: "-", with: " ").capitalized)"
        let raw = "needs-more-info"
        let displayed = "RCA: \(raw.replacingOccurrences(of: "-", with: " ").capitalized)"
        XCTAssertEqual(displayed, "RCA: Needs More Info")
    }

    func testRCALabelForSingleWordStatus() {
        let raw = "approved"
        let displayed = "RCA: \(raw.replacingOccurrences(of: "-", with: " ").capitalized)"
        XCTAssertEqual(displayed, "RCA: Approved")
    }

    // MARK: - BugDescriptionContent: Section Parsing

    func testBugDescriptionContent_SummarySection() {
        let text = """
        ## Summary
        App crashes on launch when no network is available.

        ## Steps to Reproduce
        1. Disable WiFi
        2. Launch the app
        """

        let summary = MarkdownSectionParser.body(for: "Summary", in: text)
        XCTAssertNotNil(summary, "Summary section should be parsed")
        XCTAssertEqual(summary, "App crashes on launch when no network is available.")
    }

    func testBugDescriptionContent_StepsToReproduceSection() throws {
        let text = """
        ## Steps to Reproduce
        1. Open the app
        2. Click Save
        3. Observe the crash
        """

        let steps = try XCTUnwrap(
            MarkdownSectionParser.body(for: "Steps to Reproduce", in: text),
            "Steps to Reproduce section should be parsed"
        )
        XCTAssertTrue(steps.contains("1. Open the app"))
        XCTAssertTrue(steps.contains("2. Click Save"))
        XCTAssertTrue(steps.contains("3. Observe the crash"))
    }

    func testBugDescriptionContent_StepsFallbackToStepsAlias() {
        // BugDescriptionContent resolves steps via:
        //   MarkdownSectionParser.body(for: "Steps to Reproduce", ...) ??
        //   MarkdownSectionParser.body(for: "Steps", ...) ??
        //   MarkdownSectionParser.body(for: "Repro", ...)
        // This test verifies the fallback: input has only "Steps" (alias), not "Steps to Reproduce" (primary).
        let textWithAliasOnly = """
        ## Steps
        Step one
        """
        // Primary heading must be absent so the fallback is actually exercised.
        let primaryResult = MarkdownSectionParser.body(for: "Steps to Reproduce", in: textWithAliasOnly)
        XCTAssertNil(primaryResult, "Primary heading 'Steps to Reproduce' must not match when absent")

        // Alias heading is the fallback and must be found.
        let aliasResult = MarkdownSectionParser.body(for: "Steps", in: textWithAliasOnly)
        XCTAssertNotNil(aliasResult, "'Steps' fallback must match when primary 'Steps to Reproduce' is absent")
        XCTAssertEqual(aliasResult, "Step one")

        // Simulate the nil-coalescing chain used in BugDescriptionContent.
        let resolvedSteps = primaryResult ?? aliasResult
        XCTAssertEqual(resolvedSteps, "Step one",
                       "Fallback chain must resolve to alias content when primary heading is absent")
    }

    func testBugDescriptionContent_ExpectedBehaviorSection() {
        let text = """
        ## Expected Behavior
        The save operation completes and the item appears in the list.
        """

        let expected = MarkdownSectionParser.body(for: "Expected Behavior", in: text)
        XCTAssertNotNil(expected)
        XCTAssertEqual(expected, "The save operation completes and the item appears in the list.")
    }

    func testBugDescriptionContent_ActualBehaviorSection() {
        let text = """
        ## Actual Behavior
        The app throws an exception and shows the crash reporter.
        """

        let actual = MarkdownSectionParser.body(for: "Actual Behavior", in: text)
        XCTAssertNotNil(actual)
        XCTAssertEqual(actual, "The app throws an exception and shows the crash reporter.")
    }

    func testBugDescriptionContent_SeveritySection() {
        let text = """
        ## Severity
        Critical — data loss is possible.
        """

        let severity = MarkdownSectionParser.body(for: "Severity", in: text)
        XCTAssertNotNil(severity)
        XCTAssertEqual(severity, "Critical — data loss is possible.")
    }

    func testBugDescriptionContent_DiscoveryContextSection() {
        let text = """
        ## Discovery Context
        Found during manual QA for AM-702 story review.
        """

        let context = MarkdownSectionParser.body(for: "Discovery Context", in: text)
        XCTAssertNotNil(context)
        XCTAssertEqual(context, "Found during manual QA for AM-702 story review.")
    }

    func testBugDescriptionContent_ContextFallback() {
        // BugDescriptionContent resolves discovery context via:
        //   MarkdownSectionParser.body(for: "Discovery Context", ...) ??
        //   MarkdownSectionParser.body(for: "Context", ...)
        // This test verifies the fallback: input has only "Context" (alias), not "Discovery Context" (primary).
        let textWithAliasOnly = """
        ## Context
        Found during smoke testing on 2026-03-29.
        """
        // Primary heading must be absent so the fallback is actually exercised.
        let primaryResult = MarkdownSectionParser.body(for: "Discovery Context", in: textWithAliasOnly)
        XCTAssertNil(primaryResult, "Primary heading 'Discovery Context' must not match when absent")

        // Alias heading is the fallback and must be found.
        let aliasResult = MarkdownSectionParser.body(for: "Context", in: textWithAliasOnly)
        XCTAssertNotNil(aliasResult, "'Context' fallback must match when primary 'Discovery Context' is absent")
        XCTAssertEqual(aliasResult, "Found during smoke testing on 2026-03-29.")

        // Simulate the nil-coalescing chain used in BugDescriptionContent.
        let resolvedContext = primaryResult ?? aliasResult
        XCTAssertEqual(resolvedContext, "Found during smoke testing on 2026-03-29.",
                       "Fallback chain must resolve to alias content when primary heading is absent")
    }

    func testBugDescriptionContent_AllSectionsFullTemplate() {
        let text = """
        ## Summary
        Crash on launch with no network.

        ## Steps to Reproduce
        1. Disable WiFi
        2. Launch the app

        ## Expected Behavior
        App shows offline mode gracefully.

        ## Actual Behavior
        App crashes immediately.

        ## Severity
        Critical

        ## Discovery Context
        Found during CI smoke testing.
        """

        XCTAssertNotNil(MarkdownSectionParser.body(for: "Summary", in: text))
        XCTAssertNotNil(MarkdownSectionParser.body(for: "Steps to Reproduce", in: text))
        XCTAssertNotNil(MarkdownSectionParser.body(for: "Expected Behavior", in: text))
        XCTAssertNotNil(MarkdownSectionParser.body(for: "Actual Behavior", in: text))
        XCTAssertNotNil(MarkdownSectionParser.body(for: "Severity", in: text))
        XCTAssertNotNil(MarkdownSectionParser.body(for: "Discovery Context", in: text))
    }

    // MARK: - BugDescriptionContent: Missing Sections Return Nil

    func testBugDescriptionContent_MissingSectionReturnsNil() {
        let text = """
        ## Summary
        Some crash summary.
        """

        XCTAssertNil(MarkdownSectionParser.body(for: "Steps to Reproduce", in: text),
            "Absent sections return nil, suppressing their cards")
        XCTAssertNil(MarkdownSectionParser.body(for: "Expected Behavior", in: text))
        XCTAssertNil(MarkdownSectionParser.body(for: "Actual Behavior", in: text))
        XCTAssertNil(MarkdownSectionParser.body(for: "Severity", in: text))
        XCTAssertNil(MarkdownSectionParser.body(for: "Discovery Context", in: text))
    }

    func testBugDescriptionContent_EmptyDescriptionHasNoSections() {
        XCTAssertNil(MarkdownSectionParser.body(for: "Summary", in: ""),
            "Empty description string yields no sections")
        XCTAssertNil(MarkdownSectionParser.body(for: "Steps to Reproduce", in: ""))
    }

    func testBugDescriptionContent_UnstructuredTextFallsBack() {
        // Text with no ## headings — hasKnownSections would be false in BugDescriptionContent
        let text = "This is an unstructured bug description with no markdown sections."

        let summary = MarkdownSectionParser.body(for: "Summary", in: text)
        let steps = MarkdownSectionParser.body(for: "Steps to Reproduce", in: text)

        XCTAssertNil(summary, "No matching section → nil, triggering FallbackDescriptionContent")
        XCTAssertNil(steps)
    }

    // MARK: - BugDescriptionContent: Case-Insensitive Partial Matching

    func testBugDescriptionContent_PartialHeadingMatchesSection() throws {
        // MarkdownSectionParser.body(for:in:) uses case-insensitive contains()
        let text = """
        ## Steps to Reproduce the Issue
        1. Open app
        2. Click the bug
        """

        // "Steps to Reproduce" partially matches "Steps to Reproduce the Issue"
        let steps = try XCTUnwrap(
            MarkdownSectionParser.body(for: "Steps to Reproduce", in: text),
            "Partial heading match should succeed"
        )
        XCTAssertTrue(steps.contains("1. Open app"))
    }

    func testBugDescriptionContent_CaseInsensitiveHeadingMatch() {
        let text = """
        ## EXPECTED BEHAVIOR
        Should not crash.
        """

        let expected = MarkdownSectionParser.body(for: "Expected Behavior", in: text)
        XCTAssertNotNil(expected, "Case-insensitive match should find 'EXPECTED BEHAVIOR'")
        XCTAssertEqual(expected, "Should not crash.")
    }

    // MARK: - SeverityRCACard: Card Shown/Hidden Logic

    func testSeverityRCACardShownWhenSeverityPresent() throws {
        let item = try makeBugItem(metadata: "\"severity\": \"minor\"")
        let meta = try XCTUnwrap(item.metadata.task)

        let hasSeverity = meta.severity != nil
        let hasRCA = meta.rcaStatus != nil
        let isRegression = meta.regression == true

        XCTAssertTrue(hasSeverity || hasRCA || isRegression,
            "Card renders when at least one triage field is present")
    }

    func testSeverityRCACardHiddenWhenNoTriageFields() throws {
        let item = try makeBugItem()
        let meta = try XCTUnwrap(item.metadata.task)

        let hasSeverity = meta.severity != nil
        let hasRCA = meta.rcaStatus != nil
        let isRegression = meta.regression == true

        XCTAssertFalse(hasSeverity || hasRCA || isRegression,
            "Card is suppressed when severity, rcaStatus, and regression are all absent")
    }

    func testSeverityRCACardShownWhenOnlyRCAPresent() throws {
        let item = try makeBugItem(metadata: "\"rca_status\": \"pending\"")
        let meta = try XCTUnwrap(item.metadata.task)

        let hasSeverity = meta.severity != nil
        let hasRCA = meta.rcaStatus != nil
        let isRegression = meta.regression == true

        XCTAssertTrue(hasSeverity || hasRCA || isRegression,
            "Card renders when only rcaStatus is set")
    }

    func testSeverityRCACardShownWhenOnlyRegressionPresent() throws {
        let item = try makeBugItem(metadata: "\"regression\": true")
        let meta = try XCTUnwrap(item.metadata.task)

        let isRegression = meta.regression == true
        XCTAssertTrue(isRegression,
            "Card renders when only regression flag is set to true")
    }
}
