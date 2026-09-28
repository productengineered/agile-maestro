import XCTest
@testable import AgileMaestro

// MARK: - KanbanCardViewTests
//
// Tests the Tier-2 UAT badge added to epic kanban cards (task-7/AM-801-5,
// SM-EPICCARD-800-T1..T4). Covers all 4 badge states — passed, failed, skipped,
// absent/malformed — plus the combined accessibility label (IS-800-10,
// IS-BADGE-TOOLTIP-800-4).
//
// This project has no snapshot/image-diffing library. Following the
// `WorkflowStepperView.computeSteps(for:)` precedent, the badge text and combined
// accessibility label are exposed as non-`private` (directly testable) members so
// their content can be verified without rendering an actual view hierarchy.

// MARK: - Badge Text Test Case

/// Replaces a 3-member tuple (SwiftLint `large_tuple`) for `testUATBadgeText_AllStates`.
private struct BadgeTextCase {
    let result: UATTier2Result
    let failedCount: Int
    let expected: String
}

final class KanbanCardViewTests: XCTestCase {

    // MARK: - Helpers

    private let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    /// Decodes a minimal epic `TaskItem`, optionally with a raw `uat` metadata JSON fragment
    /// (e.g. `{ "tier2": { "result": "passed" } }`).
    private func makeEpicTask(uatFragment: String? = nil) throws -> TaskItem {
        let uatJSON = uatFragment.map { ", \"uat\": \($0)" } ?? ""
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "subject": "Test Epic",
          "description": "",
          "status": "in_progress",
          "blocks": [],
          "blockedBy": [],
          "metadata": {
            "type": "epic",
            "schema_version": "2.0",
            "approval": "approved",
            "blocked": false\(uatJSON)
          }
        }
        """
        return try decoder.decode(TaskItem.self, from: Data(json.utf8))
    }

    private func makeCard(
        from task: TaskItem,
        blocked: Bool = false,
        reviewResult: String? = nil,
        progress: KanbanProgress? = nil
    ) -> KanbanCard {
        KanbanCard(
            id: task.id,
            type: task.type,
            displayId: task.displayId,
            title: task.subject,
            labels: task.labels,
            blocked: blocked,
            reviewResult: reviewResult,
            progress: progress,
            completedAt: nil,
            epicDisplayId: nil,
            column: "agent_uat",
            taskItem: task
        )
    }

    private func makeCardView(_ card: KanbanCard) -> KanbanCardView {
        KanbanCardView(card: card, onSelect: { _ in })
    }

    // MARK: - Badge Presence (SM-EPICCARD-800-T1..T4)

    func testBadgeAbsent_WhenUATMetadataMissing() throws {
        let task = try makeEpicTask()
        let card = makeCard(from: task)
        XCTAssertNil(card.uatTier2, "no uat key -> uatTier2 nil -> no badge rendered")
    }

    func testBadgeAbsent_WhenResultUnrecognized() throws {
        let task = try makeEpicTask(uatFragment: #"{ "tier2": { "result": "not-a-real-state" } }"#)
        let card = makeCard(from: task)
        XCTAssertNotNil(card.uatTier2, "sibling tier2 fields still decode")
        XCTAssertNil(card.uatTier2?.result, "unrecognized result -> nil -> no badge rendered")
    }

    func testBadgePresent_WhenPassed() throws {
        let task = try makeEpicTask(uatFragment: #"{ "tier2": { "result": "passed" } }"#)
        let card = makeCard(from: task)
        XCTAssertEqual(card.uatTier2?.result, .passed)
    }

    func testBadgePresent_WhenFailed() throws {
        let task = try makeEpicTask(
            uatFragment: #"{ "tier2": { "result": "failed", "failed_tests": ["a", "b", "c"] } }"#
        )
        let card = makeCard(from: task)
        XCTAssertEqual(card.uatTier2?.result, .failed)
        XCTAssertEqual(card.uatTier2?.failedTests?.count, 3)
    }

    func testBadgePresent_WhenSkipped() throws {
        let task = try makeEpicTask(
            uatFragment: #"{ "tier2": { "result": "skipped", "reason": "No UITest target" } }"#
        )
        let card = makeCard(from: task)
        XCTAssertEqual(card.uatTier2?.result, .skipped)
        XCTAssertEqual(card.uatTier2?.reason, "No UITest target")
    }

    // MARK: - Badge Text (KanbanCardView.uatBadgeText)

    func testUATBadgeText_AllStates() {
        let cases: [BadgeTextCase] = [
            BadgeTextCase(result: .passed, failedCount: 0, expected: "UAT ✓"),
            BadgeTextCase(result: .failed, failedCount: 3, expected: "UAT ✕ 3"),
            BadgeTextCase(result: .failed, failedCount: 0, expected: "UAT ✕"),
            BadgeTextCase(result: .skipped, failedCount: 0, expected: "UAT")
        ]
        for tc in cases {
            XCTAssertEqual(
                KanbanCardView.uatBadgeText(result: tc.result, failedCount: tc.failedCount), tc.expected,
                "\(tc.result) with failedCount \(tc.failedCount)"
            )
        }
    }

    // MARK: - Accessibility Label (IS-800-10, IS-BADGE-TOOLTIP-800-4)

    func testAccessibilityLabel_NoUAT_NoAddition() throws {
        let task = try makeEpicTask()
        let card = makeCard(from: task)
        let label = makeCardView(card).cardAccessibilityLabel
        XCTAssertFalse(label.contains("Agent UAT"), label)
    }

    func testAccessibilityLabel_MalformedResult_NoAddition() throws {
        let task = try makeEpicTask(uatFragment: #"{ "tier2": { "result": "bogus" } }"#)
        let card = makeCard(from: task)
        let label = makeCardView(card).cardAccessibilityLabel
        XCTAssertFalse(label.contains("Agent UAT"), label)
    }

    func testAccessibilityLabel_Passed() throws {
        let task = try makeEpicTask(uatFragment: #"{ "tier2": { "result": "passed" } }"#)
        let card = makeCard(from: task)
        let label = makeCardView(card).cardAccessibilityLabel
        XCTAssertTrue(label.contains("Agent UAT passed"), label)
    }

    func testAccessibilityLabel_Failed_PluralCount() throws {
        let task = try makeEpicTask(
            uatFragment: #"{ "tier2": { "result": "failed", "failed_tests": ["a", "b"] } }"#
        )
        let card = makeCard(from: task)
        let label = makeCardView(card).cardAccessibilityLabel
        XCTAssertTrue(label.contains("Agent UAT failed, 2 tests"), label)
    }

    func testAccessibilityLabel_Failed_SingularCount() throws {
        let task = try makeEpicTask(
            uatFragment: #"{ "tier2": { "result": "failed", "failed_tests": ["a"] } }"#
        )
        let card = makeCard(from: task)
        let label = makeCardView(card).cardAccessibilityLabel
        XCTAssertTrue(label.contains("Agent UAT failed, 1 test"), label)
        XCTAssertFalse(label.contains("1 tests"), label)
    }

    /// CR-801-3: nil/empty `failed_tests` must render "Agent UAT failed" with no
    /// spurious "0 tests" suffix — mirrors the badge text fix in `uatBadgeText`.
    func testAccessibilityLabel_Failed_NilFailedTests_OmitsZeroCount() throws {
        let task = try makeEpicTask(uatFragment: #"{ "tier2": { "result": "failed" } }"#)
        let card = makeCard(from: task)
        let label = makeCardView(card).cardAccessibilityLabel
        XCTAssertTrue(label.contains("Agent UAT failed"), label)
        XCTAssertFalse(label.contains("0 test"), label)
    }

    func testAccessibilityLabel_Failed_EmptyFailedTests_OmitsZeroCount() throws {
        let task = try makeEpicTask(
            uatFragment: #"{ "tier2": { "result": "failed", "failed_tests": [] } }"#
        )
        let card = makeCard(from: task)
        let label = makeCardView(card).cardAccessibilityLabel
        XCTAssertTrue(label.contains("Agent UAT failed"), label)
        XCTAssertFalse(label.contains("0 test"), label)
    }

    /// IS-800-10 / IS-BADGE-TOOLTIP-800-4: the skip reason must be reachable via the
    /// accessibility label, not solely via `.help()` (which VoiceOver may not reach).
    func testAccessibilityLabel_Skipped_IncludesReason() throws {
        let task = try makeEpicTask(
            uatFragment: #"{ "tier2": { "result": "skipped", "reason": "No UITest target configured" } }"#
        )
        let card = makeCard(from: task)
        let label = makeCardView(card).cardAccessibilityLabel
        XCTAssertTrue(label.contains("Agent UAT skipped, No UITest target configured"), label)
    }

    func testAccessibilityLabel_Skipped_NoReason() throws {
        let task = try makeEpicTask(uatFragment: #"{ "tier2": { "result": "skipped" } }"#)
        let card = makeCard(from: task)
        let label = makeCardView(card).cardAccessibilityLabel
        XCTAssertTrue(label.contains("Agent UAT skipped"), label)
        XCTAssertFalse(label.contains("Agent UAT skipped,"), label)
    }

    /// Confirms the UAT segment joins the existing combined label (Rejected/progress) rather
    /// than replacing it — no second VoiceOver stop introduced (IS-800-10).
    func testAccessibilityLabel_CombinesWithRejectedAndProgress() throws {
        let task = try makeEpicTask(
            uatFragment: #"{ "tier2": { "result": "failed", "failed_tests": ["a"] } }"#
        )
        let card = makeCard(
            from: task, reviewResult: "rejected", progress: KanbanProgress(completed: 2, total: 5, unit: "stories")
        )
        let label = makeCardView(card).cardAccessibilityLabel
        XCTAssertTrue(label.contains("Rejected"), label)
        XCTAssertTrue(label.contains("Agent UAT failed, 1 test"), label)
        XCTAssertTrue(label.contains("2 of 5 stories"), label)
    }

    // MARK: - Progress Text (KanbanCardView.progressText — TechDebt 3)

    func testProgressText_NoLinkedItems_OmitsLinkedSegment() {
        let progress = KanbanProgress(completed: 3, total: 8, unit: "stories")
        XCTAssertEqual(KanbanCardView.progressText(progress), "3 of 8 stories")
    }

    func testProgressText_WithLinkedItems_AppendsLinkedSegment() {
        let progress = KanbanProgress(completed: 16, total: 16, unit: "stories", linkedCount: 10)
        XCTAssertEqual(KanbanCardView.progressText(progress), "16 of 16 stories · 10 linked")
    }

    func testAccessibilityLabel_IncludesLinkedCount() throws {
        let task = try makeEpicTask()
        let card = makeCard(
            from: task,
            progress: KanbanProgress(completed: 16, total: 16, unit: "stories", linkedCount: 10)
        )
        let label = makeCardView(card).cardAccessibilityLabel
        XCTAssertTrue(label.contains("16 of 16 stories · 10 linked"), label)
    }
}
