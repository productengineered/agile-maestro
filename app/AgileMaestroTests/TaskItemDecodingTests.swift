import XCTest
@testable import AgileMaestro

final class TaskItemDecodingTests: XCTestCase {

    // MARK: - Helpers

    private let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    private func decodeTask(_ json: String) throws -> TaskItem {
        let data = Data(json.utf8)
        return try decoder.decode(TaskItem.self, from: data)
    }

    // MARK: - Epic Decoding

    func testEpicDecoding() throws {
        let json = """
        {
          "id": "41",
          "subject": "Epic: AM-100 - Project Scaffold & Data Layer",
          "description": "Build the core macOS project skeleton.",
          "status": "pending",
          "blocks": [],
          "blockedBy": [],
          "metadata": {
            "type": "epic",
            "schema_version": "2.0",
            "id": "AM-100",
            "epic_id": "AM-100",
            "priority": "P1",
            "approval": "approved",
            "blocked": false
          }
        }
        """
        let task = try decodeTask(json)

        XCTAssertEqual(task.id, "41")
        XCTAssertEqual(task.subject, "Epic: AM-100 - Project Scaffold & Data Layer")
        XCTAssertEqual(task.type, .epic)
        XCTAssertEqual(task.metadata.epic?.epicId, "AM-100")
        XCTAssertEqual(task.metadata.epic?.displayId, "AM-100")
        XCTAssertNil(task.parentId)
        XCTAssertTrue(task.isEpic)
    }

    // MARK: - Polymorphic Metadata Decoding

    func testPolymorphicMetadataDecoding() throws {
        let epicJSON = """
        {
          "id": "1", "subject": "Epic task", "description": "", "status": "pending",
          "blocks": [], "blockedBy": [],
          "metadata": { "type": "epic", "priority": "P1" }
        }
        """
        let storyJSON = """
        {
          "id": "2", "subject": "Story task", "description": "", "status": "pending",
          "blocks": [], "blockedBy": [],
          "metadata": { "type": "story", "parent": "1", "priority": "P2" }
        }
        """
        let taskJSON = """
        {
          "id": "3", "subject": "Leaf task", "description": "", "status": "pending",
          "blocks": [], "blockedBy": [],
          "metadata": { "type": "task", "parent": "2", "priority": "P3" }
        }
        """

        let epic = try decodeTask(epicJSON)
        let story = try decodeTask(storyJSON)
        let task = try decodeTask(taskJSON)

        // Epic: epic metadata populated, story and task nil
        XCTAssertEqual(epic.type, .epic)
        XCTAssertNotNil(epic.metadata.epic)
        XCTAssertNil(epic.metadata.story)
        XCTAssertNil(epic.metadata.task)

        // Story: story metadata populated, epic and task nil
        XCTAssertEqual(story.type, .story)
        XCTAssertNil(story.metadata.epic)
        XCTAssertNotNil(story.metadata.story)
        XCTAssertNil(story.metadata.task)
        XCTAssertEqual(story.parentId, "1")

        // Task: task metadata populated, epic and story nil
        XCTAssertEqual(task.type, .task)
        XCTAssertNil(task.metadata.epic)
        XCTAssertNil(task.metadata.story)
        XCTAssertNotNil(task.metadata.task)
        XCTAssertEqual(task.parentId, "2")
    }

    // MARK: - Resilient Priority Decoding

    func testResilientPriorityDecoding() throws {
        let intPriority = """
        {
          "id": "10", "subject": "Task", "description": "", "status": "pending",
          "blocks": [], "blockedBy": [],
          "metadata": { "type": "task", "priority": 1 }
        }
        """
        let stringPriority = """
        {
          "id": "11", "subject": "Task", "description": "", "status": "pending",
          "blocks": [], "blockedBy": [],
          "metadata": { "type": "task", "priority": "P2" }
        }
        """
        let missingPriority = """
        {
          "id": "12", "subject": "Task", "description": "", "status": "pending",
          "blocks": [], "blockedBy": [],
          "metadata": { "type": "task" }
        }
        """

        let fromInt = try decodeTask(intPriority)
        let fromString = try decodeTask(stringPriority)
        let fromMissing = try decodeTask(missingPriority)

        XCTAssertEqual(fromInt.metadata.priority, "1")
        XCTAssertEqual(fromString.metadata.priority, "P2")
        XCTAssertNil(fromMissing.metadata.priority)
    }

    // MARK: - Resilient Blocked Decoding

    func testResilientBlockedDecoding() throws {
        let boolTrue = """
        {
          "id": "20", "subject": "Task", "description": "", "status": "pending",
          "blocks": [], "blockedBy": [],
          "metadata": { "type": "task", "blocked": true }
        }
        """
        let stringTrue = """
        {
          "id": "21", "subject": "Task", "description": "", "status": "pending",
          "blocks": [], "blockedBy": [],
          "metadata": { "type": "task", "blocked": "true" }
        }
        """
        let missingBlocked = """
        {
          "id": "22", "subject": "Task", "description": "", "status": "pending",
          "blocks": [], "blockedBy": [],
          "metadata": { "type": "task" }
        }
        """

        let fromBool = try decodeTask(boolTrue)
        let fromString = try decodeTask(stringTrue)
        let fromMissing = try decodeTask(missingBlocked)

        XCTAssertEqual(fromBool.metadata.blocked, true)
        XCTAssertEqual(fromString.metadata.blocked, true)
        XCTAssertNil(fromMissing.metadata.blocked)
    }

    // MARK: - Comment Date Format Resilience

    func testCommentDateFormats() throws {
        // Three comments: ISO8601 string, Unix timestamp integer, and null date
        let json = """
        {
          "id": "30",
          "subject": "Task with comments",
          "description": "",
          "status": "pending",
          "blocks": [],
          "blockedBy": [],
          "metadata": {
            "type": "task",
            "comments": [
              {
                "id": "C1",
                "timestamp": "2026-01-15T10:00:00Z",
                "author": "agent",
                "type": "note",
                "content": "ISO8601 date"
              },
              {
                "id": "C2",
                "timestamp": 1705312800,
                "author": "agent",
                "type": "note",
                "content": "Unix timestamp"
              },
              {
                "id": "C3",
                "timestamp": null,
                "author": "agent",
                "type": "note",
                "content": "Null date"
              }
            ]
          }
        }
        """

        // Should not throw even with mixed date formats
        let task = try decodeTask(json)
        let comments = task.comments

        XCTAssertEqual(comments.count, 3)
        // ISO8601 comment has a date
        XCTAssertNotNil(comments[0].timestamp)
        // Unix timestamp comment has a date
        XCTAssertNotNil(comments[1].timestamp)
        // Null date comment has no date
        XCTAssertNil(comments[2].timestamp)
    }

    // MARK: - Resilient Status Decoding

    func testResilientStatusDecoding() throws {
        let cases: [(String, TaskStatus)] = [
            ("pending", .pending),
            ("in_progress", .inProgress),
            ("completed", .completed),
            ("done", .completed),
            ("closed", .completed),
            ("unknown_value", .pending)
        ]

        for (rawStatus, expected) in cases {
            let json = """
            {
              "id": "99", "subject": "Task", "description": "",
              "status": "\(rawStatus)",
              "blocks": [], "blockedBy": [],
              "metadata": { "type": "task" }
            }
            """
            let task = try decodeTask(json)
            XCTAssertEqual(task.status, expected, "Status '\(rawStatus)' should map to \(expected)")
        }
    }

    // MARK: - Missing Optional Fields

    func testMissingOptionalFieldsDoNotThrow() throws {
        // Minimal JSON with only required fields
        let json = """
        {
          "id": "50",
          "subject": "Minimal task",
          "description": "",
          "status": "pending",
          "blocks": [],
          "blockedBy": [],
          "metadata": { "type": "task" }
        }
        """

        let task = try decodeTask(json)

        XCTAssertEqual(task.id, "50")
        XCTAssertNil(task.activeForm)
        XCTAssertEqual(task.blocks, [])
        XCTAssertEqual(task.blockedBy, [])
        XCTAssertNil(task.metadata.labels)
        XCTAssertNil(task.metadata.comments)
        XCTAssertNil(task.metadata.priority)
        XCTAssertNil(task.metadata.approval)
        XCTAssertNil(task.metadata.blocked)
    }

    // MARK: - Bug and TechDebt Types Use TaskSpecificMetadata

    func testBugAndTechdebtUseTaskMetadata() throws {
        let bugJSON = """
        {
          "id": "60", "subject": "Bug", "description": "", "status": "pending",
          "blocks": [], "blockedBy": [],
          "metadata": { "type": "bug", "parent": "10" }
        }
        """
        let techdebtJSON = """
        {
          "id": "61", "subject": "TechDebt", "description": "", "status": "pending",
          "blocks": [], "blockedBy": [],
          "metadata": { "type": "techdebt", "parent": "10" }
        }
        """

        let bug = try decodeTask(bugJSON)
        let techdebt = try decodeTask(techdebtJSON)

        XCTAssertEqual(bug.type, .bug)
        XCTAssertNotNil(bug.metadata.task)
        XCTAssertNil(bug.metadata.epic)
        XCTAssertNil(bug.metadata.story)
        XCTAssertTrue(bug.isTask)

        XCTAssertEqual(techdebt.type, .techdebt)
        XCTAssertNotNil(techdebt.metadata.task)
        XCTAssertTrue(techdebt.isTask)
    }
}
