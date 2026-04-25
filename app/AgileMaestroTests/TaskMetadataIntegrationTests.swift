import XCTest
@testable import AgileMaestro

// MARK: - TaskMetadataIntegrationTests
//
// Integration tests for end-to-end JSON decoding of all task types through
// the full pipeline: JSON → TaskItem → TaskMetadataContainer → type-specific metadata.
//
// Tests use fixture strings that mirror real task JSON from ~/.claude/tasks/agile-maestro/
// and verify all AM-700 new fields are decoded correctly via polymorphic dispatch in
// TaskMetadataContainer.init(from:).

private let iso8601Decoder: JSONDecoder = {
    let dec = JSONDecoder()
    dec.dateDecodingStrategy = .iso8601
    return dec
}()

private func decodeTaskItem(_ json: String) throws -> TaskItem {
    try iso8601Decoder.decode(TaskItem.self, from: Data(json.utf8))
}

// MARK: - Epic, Story, Task Pipeline Tests

final class TaskMetadataIntegrationTests: XCTestCase {

    // MARK: - Epic: Full Pipeline

    func testEpicGoalComplexityRiskLevelDecode() throws {
        let item = try decodeTaskItem("""
        {
          "id": "999", "subject": "Epic: Test", "description": "",
          "status": "pending", "blocks": [], "blockedBy": [],
          "metadata": { "type": "epic", "goal": "Deliver the feature", "complexity": "M", "risk_level": "low" }
        }
        """)
        let epic = try XCTUnwrap(item.metadata.epic)
        XCTAssertEqual(epic.goal, "Deliver the feature")
        XCTAssertEqual(epic.complexity, "M")
        XCTAssertEqual(epic.riskLevel, "low")
    }

    func testEpicGoalNilWhenAbsent() throws {
        let item = try decodeTaskItem("""
        {
          "id": "999", "subject": "Epic: No Goal", "description": "",
          "status": "pending", "blocks": [], "blockedBy": [],
          "metadata": { "type": "epic" }
        }
        """)
        let epic = try XCTUnwrap(item.metadata.epic)
        XCTAssertNil(epic.goal, "goal must be nil when absent from JSON")
        XCTAssertNil(epic.complexity)
        XCTAssertNil(epic.riskLevel)
    }

    /// Mirrors 158.json (AM-700 epic) — verifies all container fields and AM-700 epic fields.
    func testEpicMetadataDecodesThroughFullPipeline() throws {
        let item = try decodeTaskItem("""
        {
          "id": "158", "subject": "Epic: AM-700", "description": "Problem.",
          "status": "pending", "blocks": [], "blockedBy": [],
          "metadata": {
            "schema_version": "2.0", "id": "AM-700", "type": "epic",
            "phase": "phase-7", "project": "agile-maestro", "priority": "P1",
            "goal": "Make every field visible", "last_updated_at": "2026-03-30T10:00:00Z",
            "story_count": 6, "complexity": "L", "risk_level": "medium", "sprint": 7,
            "approval": "approved", "blocked": false, "review_stage": null, "review_result": null,
            "labels": ["ui", "detail-panel", "metadata"],
            "branch": "epic/AM-700-detail-panel-metadata", "base_branch": "main"
          }
        }
        """)
        XCTAssertEqual(item.id, "158")
        XCTAssertEqual(item.type, .epic)
        XCTAssertNotNil(item.metadata.epic, "type=epic must route to EpicMetadata")
        XCTAssertNil(item.metadata.story)
        XCTAssertNil(item.metadata.task)
        XCTAssertEqual(item.metadata.labels, ["ui", "detail-panel", "metadata"])
        let epic = try XCTUnwrap(item.metadata.epic)
        XCTAssertEqual(epic.displayId, "AM-700")
        XCTAssertEqual(epic.phase, "phase-7")
        XCTAssertEqual(epic.goal, "Make every field visible")
        XCTAssertEqual(epic.complexity, "L")
        XCTAssertEqual(epic.riskLevel, "medium")
        XCTAssertEqual(epic.sprint, 7)
        XCTAssertEqual(epic.storyCount, 6)
        XCTAssertEqual(epic.branch, "epic/AM-700-detail-panel-metadata")
        XCTAssertNotNil(epic.lastUpdatedAt)
    }

    func testTimestampsDecodeForEpicType() throws {
        let item = try decodeTaskItem("""
        {
          "id": "e1", "subject": "Epic: TS", "description": "",
          "status": "pending", "blocks": [], "blockedBy": [],
          "metadata": { "type": "epic", "created_at": "2026-01-15T10:00:00Z",
                        "last_updated_at": "2026-03-30T12:30:00Z" }
        }
        """)
        XCTAssertNotNil(item.metadata.createdAt)
        XCTAssertNotNil(try XCTUnwrap(item.metadata.epic).lastUpdatedAt)
    }

    // MARK: - Story: Full Pipeline

    /// Mirrors story #183 (AM-706).
    func testStoryMetadataDecodesThroughFullPipeline() throws {
        let item = try decodeTaskItem("""
        {
          "id": "183", "subject": "Story: AM-706", "description": "Summary",
          "status": "in_progress", "blocks": [], "blockedBy": [],
          "metadata": {
            "schema_version": "2.0", "type": "story", "epic_id": "AM-700",
            "priority": "P2", "approval": "approved", "blocked": false,
            "sprint": 7, "labels": ["testing", "integration"],
            "claimed_by": "macos-developer-agent",
            "claimed_at": "2026-03-30T00:00:00Z",
            "last_updated_at": "2026-03-30T00:00:00Z"
          }
        }
        """)
        XCTAssertEqual(item.type, .story)
        XCTAssertNil(item.metadata.epic)
        XCTAssertNotNil(item.metadata.story, "type=story must route to StoryMetadata")
        XCTAssertNil(item.metadata.task)
        let story = try XCTUnwrap(item.metadata.story)
        XCTAssertEqual(story.epicId, "AM-700")
        XCTAssertEqual(story.sprint, 7)
        XCTAssertEqual(story.claimedBy, "macos-developer-agent")
        XCTAssertNotNil(story.claimedAt)
        XCTAssertNotNil(story.lastUpdatedAt)
    }

    // MARK: - Task: Full Pipeline

    /// Mirrors task #184.
    func testTaskMetadataDecodesThroughFullPipeline() throws {
        let item = try decodeTaskItem("""
        {
          "id": "184", "subject": "Task: Write integration tests", "description": "What.",
          "status": "in_progress", "blocks": [], "blockedBy": [],
          "metadata": {
            "schema_version": "2.0", "type": "task", "priority": "P2",
            "approval": "approved", "blocked": false,
            "local_checks": ["Check 1", "Check 2", "Check 3"],
            "checklist": ["Step 1", "Step 2"],
            "completion_signal": "Build passes and tests added",
            "validation_hint": "Run xcodebuild test",
            "claimed_by": "macos-developer-agent",
            "claimed_at": "2026-03-30T00:00:00Z",
            "created_at": "2026-03-30T09:00:00Z",
            "last_updated_at": "2026-03-30T10:00:00Z"
          }
        }
        """)
        XCTAssertEqual(item.type, .task)
        XCTAssertNil(item.metadata.epic)
        XCTAssertNil(item.metadata.story)
        XCTAssertNotNil(item.metadata.task, "type=task must route to TaskSpecificMetadata")
        let meta = try XCTUnwrap(item.metadata.task)
        XCTAssertEqual(meta.schemaVersion, "2.0")
        XCTAssertEqual(meta.localChecks, ["Check 1", "Check 2", "Check 3"])
        XCTAssertEqual(meta.checklist, ["Step 1", "Step 2"])
        XCTAssertEqual(meta.completionSignal, "Build passes and tests added")
        XCTAssertEqual(meta.validationHint, "Run xcodebuild test")
        XCTAssertEqual(meta.claimedBy, "macos-developer-agent")
        XCTAssertNotNil(meta.claimedAt)
        let createdAt = try XCTUnwrap(meta.createdAt)
        let lastUpdatedAt = try XCTUnwrap(meta.lastUpdatedAt)
        XCTAssertLessThan(createdAt, lastUpdatedAt)
    }

    // MARK: - Polymorphic Dispatch & Resilient Decoding

    func testPolymorphicDispatchCorrectForAllFiveTypes() throws {
        let cases: [(String, TaskType)] = [
            ("epic", .epic), ("story", .story), ("task", .task), ("bug", .bug), ("techdebt", .techdebt)
        ]
        for (typeString, expectedType) in cases {
            let item = try decodeTaskItem("""
            {
              "id": "d-\(typeString)", "subject": "\(typeString)", "description": "",
              "status": "pending", "blocks": [], "blockedBy": [],
              "metadata": { "type": "\(typeString)" }
            }
            """)
            XCTAssertEqual(item.type, expectedType)
            XCTAssertEqual(item.metadata.type, expectedType)
            switch expectedType {
            case .epic:
                XCTAssertNotNil(item.metadata.epic)
                XCTAssertNil(item.metadata.story)
                XCTAssertNil(item.metadata.task)
            case .story:
                XCTAssertNil(item.metadata.epic)
                XCTAssertNotNil(item.metadata.story)
                XCTAssertNil(item.metadata.task)
            case .task, .bug, .techdebt:
                XCTAssertNil(item.metadata.epic)
                XCTAssertNil(item.metadata.story)
                XCTAssertNotNil(item.metadata.task)
            }
        }
    }

    func testMissingTypeFieldDefaultsToTask() throws {
        let item = try decodeTaskItem("""
        {
          "id": "no-type", "subject": "No type", "description": "",
          "status": "pending", "blocks": [], "blockedBy": [],
          "metadata": { "priority": "P3" }
        }
        """)
        XCTAssertEqual(item.metadata.type, .task)
        XCTAssertNotNil(item.metadata.task)
    }

    func testBlocksAndBlockedByDecodeOnAllTypes() throws {
        let types = [("epic", false), ("story", false), ("task", true), ("bug", true), ("techdebt", true)]
        for (type, expectTask) in types {
            let item = try decodeTaskItem("""
            {
              "id": "c-\(type)", "subject": "\(type)", "description": "",
              "status": "pending", "blocks": ["ref-1","ref-2"],
              "blockedBy": ["parent-10"], "metadata": { "type": "\(type)" }
            }
            """)
            XCTAssertEqual(item.blocks, ["ref-1", "ref-2"], "blocks for type=\(type)")
            XCTAssertEqual(item.blockedBy, ["parent-10"], "blockedBy for type=\(type)")
            if expectTask { XCTAssertNotNil(item.metadata.task) }
        }
    }
}

// MARK: - Bug and TechDebt Pipeline Tests

final class BugTechDebtMetadataIntegrationTests: XCTestCase {

    // MARK: - Bug: Full Pipeline (AM-700 New Fields)

    /// Mirrors 157.json (bug task).
    func testBugMetadataDecodesThroughFullPipeline() throws {
        let item = try decodeTaskItem("""
        {
          "id": "157", "subject": "Bug: Overview tab", "description": "Summary.",
          "owner": "rca-agent", "status": "completed", "blocks": [], "blockedBy": [],
          "metadata": {
            "schema_version": "2.0", "type": "bug", "severity": "moderate",
            "priority": "P2", "approval": "approved", "blocked": false,
            "rca_status": "approved", "found_in": null,
            "steps_to_reproduce": [
              "Load a session with tasks that have v2.0 schema metadata",
              "Select task #156 in tree/kanban view",
              "Click the Overview tab in the detail panel"
            ],
            "expected_behavior": "Overview tab displays key metadata fields as visual cards/chips",
            "actual_behavior": "Overview tab shows only P1 badge and CHECKS 10 counter",
            "labels": ["detail-panel", "overview-tab", "metadata-rendering"],
            "claimed_by": "rca-agent",
            "claimed_at": "2026-03-29T00:00:00Z",
            "last_updated_at": "2026-03-29T00:00:00Z"
          }
        }
        """)
        XCTAssertEqual(item.type, .bug)
        XCTAssertEqual(item.status, .completed)
        XCTAssertNotNil(item.metadata.task, "type=bug must route to TaskSpecificMetadata")
        XCTAssertNil(item.metadata.epic)
        XCTAssertNil(item.metadata.story)
        let meta = try XCTUnwrap(item.metadata.task)
        XCTAssertEqual(meta.severity, "moderate")
        XCTAssertEqual(meta.rcaStatus, "approved")
        XCTAssertEqual(meta.stepsToReproduce?.count, 3)
        XCTAssertEqual(meta.expectedBehavior,
                       "Overview tab displays key metadata fields as visual cards/chips")
        XCTAssertEqual(meta.actualBehavior,
                       "Overview tab shows only P1 badge and CHECKS 10 counter")
        XCTAssertEqual(meta.claimedBy, "rca-agent")
        XCTAssertNotNil(meta.claimedAt)
        XCTAssertNotNil(meta.lastUpdatedAt)
        XCTAssertNil(meta.debtType, "Bug task must not have techdebt fields")
        XCTAssertNil(meta.debtCategory)
        XCTAssertNil(meta.regressionRisk)
        XCTAssertNil(meta.impactIfDeferred)
    }

    func testTimestampsDecodeForBugType() throws {
        let item = try decodeTaskItem("""
        {
          "id": "b1", "subject": "Bug: TS", "description": "",
          "status": "pending", "blocks": [], "blockedBy": [],
          "metadata": { "type": "bug", "created_at": "2026-01-01T00:00:00Z",
                        "last_updated_at": "2026-03-30T00:00:00Z" }
        }
        """)
        let meta = try XCTUnwrap(item.metadata.task)
        let createdAt = try XCTUnwrap(meta.createdAt)
        let lastUpdatedAt = try XCTUnwrap(meta.lastUpdatedAt)
        XCTAssertLessThan(createdAt, lastUpdatedAt)
    }

    // MARK: - TechDebt: Full Pipeline (AM-700 New Fields)

    /// Mirrors 152.json (techdebt task).
    func testTechDebtMetadataDecodesThroughFullPipeline() throws {
        let item = try decodeTaskItem("""
        {
          "id": "152", "subject": "TechDebt: Generate app icon", "description": "State.",
          "status": "pending", "blocks": [], "blockedBy": [],
          "metadata": {
            "schema_version": "2.0", "type": "techdebt", "priority": "P3",
            "approval": "pending", "blocked": false,
            "local_checks": ["All icon sizes", "Contents.json correct", "App builds"],
            "completion_signal": "Build succeeds and app icon visible in Dock on launch",
            "labels": ["design", "app-icon", "tech-debt"],
            "debt_type": "quality", "debt_category": "missing-asset",
            "files_affected": ["app/AgileMaestro/AgileMaestro/Assets.xcassets/AppIcon.appiconset/"],
            "regression_risk": "low",
            "impact_if_deferred": "App shows default Xcode placeholder icon instead of branded icon",
            "business_justification": "App needs branded identity for Dock and app switcher"
          }
        }
        """)
        XCTAssertEqual(item.type, .techdebt)
        XCTAssertNotNil(item.metadata.task, "type=techdebt must route to TaskSpecificMetadata")
        XCTAssertNil(item.metadata.epic)
        XCTAssertNil(item.metadata.story)
        let meta = try XCTUnwrap(item.metadata.task)
        XCTAssertEqual(meta.debtType, "quality")
        XCTAssertEqual(meta.debtCategory, "missing-asset")
        XCTAssertEqual(meta.regressionRisk, "low")
        XCTAssertEqual(meta.impactIfDeferred,
                       "App shows default Xcode placeholder icon instead of branded icon")
        XCTAssertEqual(meta.businessJustification,
                       "App needs branded identity for Dock and app switcher")
        XCTAssertEqual(meta.filesAffected,
                       ["app/AgileMaestro/AgileMaestro/Assets.xcassets/AppIcon.appiconset/"])
        XCTAssertEqual(meta.completionSignal, "Build succeeds and app icon visible in Dock on launch")
        XCTAssertEqual(meta.localChecks?.count, 3)
        XCTAssertNil(meta.severity, "TechDebt task must not have bug fields")
        XCTAssertNil(meta.stepsToReproduce)
        XCTAssertNil(meta.rcaStatus)
    }

    func testTimestampsDecodeForTechDebtType() throws {
        let item = try decodeTaskItem("""
        {
          "id": "t1", "subject": "TechDebt: TS", "description": "",
          "status": "pending", "blocks": [], "blockedBy": [],
          "metadata": { "type": "techdebt", "created_at": "2026-02-01T00:00:00Z",
                        "last_updated_at": "2026-03-30T00:00:00Z" }
        }
        """)
        let meta = try XCTUnwrap(item.metadata.task)
        XCTAssertNotNil(meta.createdAt)
        XCTAssertNotNil(meta.lastUpdatedAt)
    }

    // MARK: - Field Isolation: Bug/TechDebt Fields Don't Leak Into Story/Epic Containers

    func testBugFieldsNotPresentInStoryContainer() throws {
        let item = try decodeTaskItem("""
        {
          "id": "s1", "subject": "Story: No bug fields", "description": "",
          "status": "pending", "blocks": [], "blockedBy": [],
          "metadata": { "type": "story", "severity": "critical", "rca_status": "approved" }
        }
        """)
        XCTAssertEqual(item.type, .story)
        XCTAssertNil(item.metadata.task, "Bug fields must not cause task metadata for story type")
        XCTAssertNotNil(item.metadata.story)
    }

    func testTechDebtFieldsNotPresentInEpicContainer() throws {
        let item = try decodeTaskItem("""
        {
          "id": "e1", "subject": "Epic: No techdebt fields", "description": "",
          "status": "pending", "blocks": [], "blockedBy": [],
          "metadata": { "type": "epic", "debt_type": "architecture", "regression_risk": "high" }
        }
        """)
        XCTAssertEqual(item.type, .epic)
        XCTAssertNil(item.metadata.task, "TechDebt fields must not cause task metadata for epic type")
        XCTAssertNotNil(item.metadata.epic)
    }
}
