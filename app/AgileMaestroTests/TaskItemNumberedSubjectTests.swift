import XCTest
@testable import AgileMaestro

/// Tests for `TaskItem.numberedSubject` and `TaskItem.displaySubject` — the sidebar
/// row's leading-number display string and its redundant-type-prefix stripping
/// (task-5: bracket the sidebar number and strip the redundant type prefix). This
/// is the single source `TreeRowView` uses both for its visual title and its
/// accessibility label, so covering it here covers both the row display string and
/// the accessibility label's type conveyance.
final class TaskItemNumberedSubjectTests: XCTestCase {

    // MARK: - Helpers

    private func decodeTask(_ json: String) throws -> TaskItem {
        try JSONDecoder().decode(TaskItem.self, from: Data(json.utf8))
    }

    private func makeTaskJSON(id: String, subject: String, type: String) -> String {
        """
        {
          "id": "\(id)", "subject": "\(subject)", "description": "", "status": "pending",
          "blocks": [], "blockedBy": [],
          "metadata": { "type": "\(type)" }
        }
        """
    }

    // MARK: - Format: "[<id>] <displaySubject>"

    func testNumberedSubjectFormatsIdAndStrippedSubject() throws {
        let task = try decodeTask(makeTaskJSON(id: "80", subject: "TechDebt: OPS-110 code-r", type: "techdebt"))

        XCTAssertEqual(task.numberedSubject, "[80] OPS-110 code-r")
    }

    /// `numberedSubject` must use the raw `id` (the `.json` filename stem) — never
    /// `displayId` — since a ticket-style displayId (e.g. "AM-100") would not match
    /// the file on disk.
    func testNumberedSubjectUsesRawIdNotDisplayId() throws {
        let json = """
        {
          "id": "42", "subject": "Epic: Something", "description": "", "status": "pending",
          "blocks": [], "blockedBy": [],
          "metadata": { "type": "epic", "epic_id": "AM-100" }
        }
        """
        let task = try decodeTask(json)

        XCTAssertEqual(task.metadata.epic?.epicId, "AM-100")
        XCTAssertEqual(task.numberedSubject, "[42] Something")
    }

    // MARK: - Prefix stripping: each variant

    private struct PrefixCase {
        let subject: String
        let expectedRemainder: String
        let label: String
    }

    /// Every documented prefix variant — `TechDebt:`, `Tech Debt:`, `Tech-Debt:`,
    /// `Bug:`, `Story:`, `Epic:`, `Task:` — is stripped for display.
    func testDisplaySubjectStripsEachPrefixVariant() throws {
        let cases: [PrefixCase] = [
            PrefixCase(subject: "TechDebt: OPS-110 code-r", expectedRemainder: "OPS-110 code-r", label: "TechDebt"),
            PrefixCase(subject: "Tech Debt: OPS-110 code-r", expectedRemainder: "OPS-110 code-r", label: "Tech Debt"),
            PrefixCase(subject: "Tech-Debt: OPS-110 code-r", expectedRemainder: "OPS-110 code-r", label: "Tech-Debt"),
            PrefixCase(
                subject: "Bug: /sign-in has no heading", expectedRemainder: "/sign-in has no heading", label: "Bug"
            ),
            PrefixCase(subject: "Story: OPS-114 - Kaja", expectedRemainder: "OPS-114 - Kaja", label: "Story"),
            PrefixCase(
                subject: "Epic: App Shell and Toolbar UI", expectedRemainder: "App Shell and Toolbar UI", label: "Epic"
            ),
            PrefixCase(subject: "Task: Create TreeRowView", expectedRemainder: "Create TreeRowView", label: "Task")
        ]

        for testCase in cases {
            let task = try decodeTask(makeTaskJSON(id: "1", subject: testCase.subject, type: "task"))
            XCTAssertEqual(task.displaySubject, testCase.expectedRemainder, "prefix \(testCase.label)")
            XCTAssertEqual(task.numberedSubject, "[1] \(testCase.expectedRemainder)", "prefix \(testCase.label)")
        }
    }

    // MARK: - Prefix stripping: case-insensitivity

    func testDisplaySubjectStripsPrefixCaseInsensitively() throws {
        let cases: [String] = [
            "techdebt: foo",
            "TECHDEBT: foo",
            "bug: foo",
            "BUG: foo",
            "StOrY: foo",
            "epic: foo",
            "TASK: foo"
        ]

        for subject in cases {
            let task = try decodeTask(makeTaskJSON(id: "5", subject: subject, type: "task"))
            XCTAssertEqual(task.displaySubject, "foo", "subject \(subject)")
        }
    }

    // MARK: - Prefix stripping: no prefix present

    func testDisplaySubjectUnchangedWhenNoPrefixPresent() throws {
        let task = try decodeTask(makeTaskJSON(id: "9", subject: "Some plain subject", type: "task"))

        XCTAssertEqual(task.displaySubject, "Some plain subject")
        XCTAssertEqual(task.numberedSubject, "[9] Some plain subject")
    }

    // MARK: - Prefix stripping: prefix-only fallback

    /// A subject that is nothing but the prefix falls back to the full,
    /// unstripped subject — never an empty display string.
    func testDisplaySubjectFallsBackWhenStrippingWouldLeaveNothing() throws {
        let cases: [String] = ["TechDebt:", "Bug:", "Bug:   "]

        for subject in cases {
            let task = try decodeTask(makeTaskJSON(id: "3", subject: subject, type: "bug"))
            XCTAssertEqual(task.displaySubject, subject, "subject \(subject)")
            XCTAssertFalse(task.displaySubject.isEmpty, "subject \(subject)")
        }
    }

    // MARK: - Prefix stripping: mid-string prefix untouched

    /// A prefix-like word that does not appear at the very start of the subject
    /// is never stripped — only a leading prefix qualifies.
    func testDisplaySubjectLeavesMidStringPrefixUntouched() throws {
        let task = try decodeTask(makeTaskJSON(id: "5", subject: "Fix bug: foo", type: "bug"))

        XCTAssertEqual(task.displaySubject, "Fix bug: foo")
        XCTAssertEqual(task.numberedSubject, "[5] Fix bug: foo")
    }

    // MARK: - Every row type shares the same computed properties

    private struct NumberedSubjectCase {
        let id: String
        let subject: String
        let type: String
        let expected: String
    }

    /// Every row type (epic, story, task, bug, techdebt) shares the same computed
    /// property — no per-type formatting divergence.
    func testNumberedSubjectAcrossAllTaskTypes() throws {
        let cases: [NumberedSubjectCase] = [
            NumberedSubjectCase(id: "1", subject: "Epic: App Shell", type: "epic", expected: "[1] App Shell"),
            NumberedSubjectCase(id: "2", subject: "Story: Tree Sidebar", type: "story", expected: "[2] Tree Sidebar"),
            NumberedSubjectCase(
                id: "3", subject: "Task: Create TreeRowView", type: "task", expected: "[3] Create TreeRowView"
            ),
            NumberedSubjectCase(id: "4", subject: "Bug: Crash on launch", type: "bug", expected: "[4] Crash on launch"),
            NumberedSubjectCase(
                id: "5", subject: "TechDebt: sign-in with Apple ID", type: "techdebt",
                expected: "[5] sign-in with Apple ID"
            )
        ]

        for testCase in cases {
            let task = try decodeTask(makeTaskJSON(id: testCase.id, subject: testCase.subject, type: testCase.type))
            XCTAssertEqual(task.numberedSubject, testCase.expected, "type \(testCase.type)")
        }
    }

    /// AC2 (truncation) is a layout concern, but the underlying string must still
    /// carry the full untruncated subject — truncation is the View's job, not the model's.
    func testNumberedSubjectDoesNotTruncateLongSubjects() throws {
        let longSubject = "TechDebt: sign-in with Apple ID silently fails when the keychain " +
            "item was created by a previous major OS version and needs re-authorization"
        let task = try decodeTask(makeTaskJSON(id: "88", subject: longSubject, type: "techdebt"))

        XCTAssertEqual(task.numberedSubject, "[88] \(task.displaySubject)")
        XCTAssertTrue(task.numberedSubject.hasSuffix("needs re-authorization"))
    }

    /// Empty subject still yields a well-formed, id-led string (no crash, no nil).
    func testNumberedSubjectWithEmptySubject() throws {
        let task = try decodeTask(makeTaskJSON(id: "7", subject: "", type: "task"))

        XCTAssertEqual(task.numberedSubject, "[7] ")
    }

    // MARK: - Sidebar number source: sourceFile stem vs id fallback (task-5, CodeRabbit)

    /// When `sourceFile` is set (post-parse, by `TaskParserService`), its filename
    /// stem wins over `id` — even when `id` differs (e.g. a JSON file whose `"id"`
    /// key doesn't match its own filename).
    func testNumberedSubjectPrefersSourceFileStemOverId() throws {
        var task = try decodeTask(makeTaskJSON(id: "999", subject: "Some task", type: "task"))
        task.sourceFile = "12.json"

        XCTAssertEqual(task.numberedSubject, "[12] Some task")
    }

    /// With no `sourceFile` set (e.g. a task decoded directly in a test, never
    /// routed through `TaskParserService`), `numberedSubject` falls back to `id`.
    func testNumberedSubjectFallsBackToIdWhenNoSourceFile() throws {
        let task = try decodeTask(makeTaskJSON(id: "42", subject: "Some task", type: "task"))

        XCTAssertNil(task.sourceFile)
        XCTAssertEqual(task.numberedSubject, "[42] Some task")
    }

    // MARK: - Accessibility label still conveys the type after stripping

    /// `TreeRowView`'s type icon is hidden from VoiceOver, and its accessibility
    /// label composes `"\(numberedSubject), \(task.type.displayName), ..."` —
    /// appending the task type independently of the (now-stripped) title text.
    /// This test mirrors that composition to prove the type is still conveyed to
    /// screen reader users even though `numberedSubject` no longer embeds it as text.
    func testAccessibilityLabelConveysTypeIndependentlyOfStrippedPrefix() throws {
        let task = try decodeTask(makeTaskJSON(id: "80", subject: "TechDebt: OPS-110 code-r", type: "techdebt"))

        let accessibilityLabel = "\(task.numberedSubject), \(task.type.displayName)"

        XCTAssertEqual(task.numberedSubject, "[80] OPS-110 code-r")
        XCTAssertEqual(accessibilityLabel, "[80] OPS-110 code-r, Tech Debt")
    }
}
