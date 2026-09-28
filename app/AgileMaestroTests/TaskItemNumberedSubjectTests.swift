import XCTest
@testable import AgileMaestro

/// Tests for `TaskItem.numberedSubject` — the sidebar row's leading-number display
/// string (task-5: lead every sidebar row with the item number). This is the single
/// source `TreeRowView` uses both for its visual number label and its accessibility
/// label, so covering it here covers both AC1 (row display string) and AC3
/// (accessibility label includes the number).
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

    // MARK: - AC1: "<id> - <subject>" format, id matches the .json filename stem

    func testNumberedSubjectFormatsIdAndSubject() throws {
        let task = try decodeTask(makeTaskJSON(id: "88", subject: "TechDebt: sign-in with Apple ID", type: "techdebt"))

        XCTAssertEqual(task.numberedSubject, "88 - TechDebt: sign-in with Apple ID")
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
        XCTAssertEqual(task.numberedSubject, "42 - Epic: Something")
    }

    private struct NumberedSubjectCase {
        let id: String
        let subject: String
        let type: String
    }

    /// Every row type (epic, story, task, bug, techdebt) shares the same computed
    /// property — no per-type formatting divergence.
    func testNumberedSubjectAcrossAllTaskTypes() throws {
        let cases: [NumberedSubjectCase] = [
            NumberedSubjectCase(id: "1", subject: "Epic: App Shell", type: "epic"),
            NumberedSubjectCase(id: "2", subject: "Story: Tree Sidebar", type: "story"),
            NumberedSubjectCase(id: "3", subject: "Task: Create TreeRowView", type: "task"),
            NumberedSubjectCase(id: "4", subject: "Bug: Crash on launch", type: "bug"),
            NumberedSubjectCase(id: "5", subject: "TechDebt: sign-in with Apple ID", type: "techdebt")
        ]

        for testCase in cases {
            let task = try decodeTask(makeTaskJSON(id: testCase.id, subject: testCase.subject, type: testCase.type))
            XCTAssertEqual(
                task.numberedSubject,
                "\(testCase.id) - \(testCase.subject)",
                "type \(testCase.type) should format as '<id> - <subject>'"
            )
        }
    }

    /// AC2 (truncation) is a layout concern, but the underlying string must still
    /// carry the full untruncated subject — truncation is the View's job, not the model's.
    func testNumberedSubjectDoesNotTruncateLongSubjects() throws {
        let longSubject = "TechDebt: sign-in with Apple ID silently fails when the keychain " +
            "item was created by a previous major OS version and needs re-authorization"
        let task = try decodeTask(makeTaskJSON(id: "88", subject: longSubject, type: "techdebt"))

        XCTAssertEqual(task.numberedSubject, "88 - \(longSubject)")
    }

    /// Empty subject still yields a well-formed, id-led string (no crash, no nil).
    func testNumberedSubjectWithEmptySubject() throws {
        let task = try decodeTask(makeTaskJSON(id: "7", subject: "", type: "task"))

        XCTAssertEqual(task.numberedSubject, "7 - ")
    }
}
