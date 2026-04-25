import XCTest
@testable import AgileMaestro

/// Tests for bug-specific, techdebt-specific, and timestamp field decoding in TaskSpecificMetadata.
///
/// Covers: AM-701 story — verifies all new fields decode correctly from JSON, missing fields
/// degrade gracefully to nil, and regular task items decode with all new fields as nil.
final class TaskSpecificMetadataTests: XCTestCase {

    // MARK: - Helpers

    private let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    /// Decode a full TaskItem from JSON, returning its `task` metadata.
    private func decodeTaskMetadata(_ json: String) throws -> TaskSpecificMetadata {
        let data = Data(json.utf8)
        let item = try decoder.decode(TaskItem.self, from: data)
        let meta = try XCTUnwrap(item.metadata.task, "Expected task metadata for type task/bug/techdebt")
        return meta
    }

    private func makeTaskJSON(type: String, metadata extraFields: String) -> String {
        """
        {
          "id": "999",
          "subject": "Test item",
          "description": "",
          "status": "pending",
          "blocks": [],
          "blockedBy": [],
          "metadata": {
            "type": "\(type)",
            \(extraFields)
          }
        }
        """
    }

    // MARK: - Bug Fields: Full Payload

    func testBugFieldsDecodeFromFullPayload() throws {
        let json = makeTaskJSON(type: "bug", metadata: """
            "severity": "major",
            "steps_to_reproduce": ["Step 1: Open the app", "Step 2: Click Save"],
            "expected_behavior": "Item saved successfully",
            "actual_behavior": "App crashes with EXC_BAD_ACCESS",
            "rca_status": "investigated",
            "discovered_from": "task-42",
            "discovered_by": "qa-agent",
            "affected_files": ["Views/DetailView.swift", "ViewModels/DetailViewModel.swift"],
            "regression": true,
            "environment": {
              "macos_version": "15.4",
              "app_version": "1.2.3"
            }
        """)

        let meta = try decodeTaskMetadata(json)

        XCTAssertEqual(meta.severity, "major")
        XCTAssertEqual(meta.stepsToReproduce, ["Step 1: Open the app", "Step 2: Click Save"])
        XCTAssertEqual(meta.expectedBehavior, "Item saved successfully")
        XCTAssertEqual(meta.actualBehavior, "App crashes with EXC_BAD_ACCESS")
        XCTAssertEqual(meta.rcaStatus, "investigated")
        XCTAssertEqual(meta.discoveredFrom, "task-42")
        XCTAssertEqual(meta.discoveredBy, "qa-agent")
        XCTAssertEqual(meta.affectedFiles, ["Views/DetailView.swift", "ViewModels/DetailViewModel.swift"])
        XCTAssertEqual(meta.regression, true)
        XCTAssertEqual(meta.environment?.macosVersion, "15.4")
        XCTAssertEqual(meta.environment?.appVersion, "1.2.3")
    }

    // MARK: - TechDebt Fields: Full Payload

    func testTechDebtFieldsDecodeFromFullPayload() throws {
        let json = makeTaskJSON(type: "techdebt", metadata: """
            "debt_type": "code-quality",
            "debt_category": "duplication",
            "files_affected": ["Services/SyncService.swift"],
            "regression_risk": "medium",
            "impact_if_deferred": "Increased maintenance cost over time",
            "business_justification": "Required before v2.0 milestone"
        """)

        let meta = try decodeTaskMetadata(json)

        XCTAssertEqual(meta.debtType, "code-quality")
        XCTAssertEqual(meta.debtCategory, "duplication")
        XCTAssertEqual(meta.filesAffected, ["Services/SyncService.swift"])
        XCTAssertEqual(meta.regressionRisk, "medium")
        XCTAssertEqual(meta.impactIfDeferred, "Increased maintenance cost over time")
        XCTAssertEqual(meta.businessJustification, "Required before v2.0 milestone")
    }

    // MARK: - Timestamp Fields

    func testTimestampFieldsDecode() throws {
        let json = makeTaskJSON(type: "task", metadata: """
            "created_at": "2026-01-15T10:00:00Z",
            "last_updated_at": "2026-03-30T12:30:00Z",
            "created_by": "planning-agent"
        """)

        let meta = try decodeTaskMetadata(json)

        XCTAssertNotNil(meta.createdAt)
        XCTAssertNotNil(meta.lastUpdatedAt)
        XCTAssertEqual(meta.createdBy, "planning-agent")

        // Verify createdAt is before lastUpdatedAt
        let createdAt = try XCTUnwrap(meta.createdAt)
        let lastUpdatedAt = try XCTUnwrap(meta.lastUpdatedAt)
        XCTAssertLessThan(createdAt, lastUpdatedAt)
    }

    // MARK: - Missing Fields Degrade Gracefully (Bug)

    func testBugMissingFieldsAreNil() throws {
        let json = makeTaskJSON(type: "bug", metadata: """
            "severity": "minor"
        """)

        let meta = try decodeTaskMetadata(json)

        XCTAssertEqual(meta.severity, "minor")
        XCTAssertNil(meta.stepsToReproduce)
        XCTAssertNil(meta.expectedBehavior)
        XCTAssertNil(meta.actualBehavior)
        XCTAssertNil(meta.rcaStatus)
        XCTAssertNil(meta.discoveredFrom)
        XCTAssertNil(meta.discoveredBy)
        XCTAssertNil(meta.affectedFiles)
        XCTAssertNil(meta.regression)
        XCTAssertNil(meta.environment)
    }

    // MARK: - Missing Fields Degrade Gracefully (TechDebt)

    func testTechDebtMissingFieldsAreNil() throws {
        let json = makeTaskJSON(type: "techdebt", metadata: """
            "debt_type": "architecture"
        """)

        let meta = try decodeTaskMetadata(json)

        XCTAssertEqual(meta.debtType, "architecture")
        XCTAssertNil(meta.debtCategory)
        XCTAssertNil(meta.filesAffected)
        XCTAssertNil(meta.regressionRisk)
        XCTAssertNil(meta.impactIfDeferred)
        XCTAssertNil(meta.businessJustification)
    }

    // MARK: - Regular Task Has All New Fields Nil

    func testRegularTaskHasBugAndTechDebtFieldsAsNil() throws {
        let json = makeTaskJSON(type: "task", metadata: """
            "schema_version": "2.0",
            "priority": "P2",
            "local_checks": ["Check 1", "Check 2"],
            "completion_signal": "Build passes"
        """)

        let meta = try decodeTaskMetadata(json)

        // Bug-specific fields should all be nil
        XCTAssertNil(meta.severity)
        XCTAssertNil(meta.stepsToReproduce)
        XCTAssertNil(meta.expectedBehavior)
        XCTAssertNil(meta.actualBehavior)
        XCTAssertNil(meta.rcaStatus)
        XCTAssertNil(meta.discoveredFrom)
        XCTAssertNil(meta.discoveredBy)
        XCTAssertNil(meta.affectedFiles)
        XCTAssertNil(meta.regression)
        XCTAssertNil(meta.environment)

        // TechDebt-specific fields should all be nil
        XCTAssertNil(meta.debtType)
        XCTAssertNil(meta.debtCategory)
        XCTAssertNil(meta.filesAffected)
        XCTAssertNil(meta.regressionRisk)
        XCTAssertNil(meta.impactIfDeferred)
        XCTAssertNil(meta.businessJustification)

        // Standard task fields still work
        XCTAssertEqual(meta.schemaVersion, "2.0")
        XCTAssertEqual(meta.priority, "P2")
        XCTAssertEqual(meta.localChecks, ["Check 1", "Check 2"])
        XCTAssertEqual(meta.completionSignal, "Build passes")
    }

    // MARK: - BugEnvironment Partial Decoding

    func testBugEnvironmentPartialFieldsDecodeResiliently() throws {
        // Only macosVersion present, appVersion absent
        let json = makeTaskJSON(type: "bug", metadata: """
            "environment": { "macos_version": "15.4" }
        """)

        let meta = try decodeTaskMetadata(json)

        XCTAssertEqual(meta.environment?.macosVersion, "15.4")
        XCTAssertNil(meta.environment?.appVersion)
    }

    // MARK: - Regression Field: Bool and String Forms

    func testRegressionDecodesBoolAndStringForms() throws {
        let cases: [(String, Bool)] = [
            ("true", true),
            ("false", false)
        ]
        for (value, expected) in cases {
            let jsonBool = makeTaskJSON(type: "bug", metadata: "\"regression\": \(value)")
            let metaBool = try decodeTaskMetadata(jsonBool)
            XCTAssertEqual(metaBool.regression, expected, "Bool form '\(value)' should decode to \(expected)")

            let jsonString = makeTaskJSON(type: "bug", metadata: "\"regression\": \"\(value)\"")
            let metaString = try decodeTaskMetadata(jsonString)
            XCTAssertEqual(metaString.regression, expected, "String form '\(value)' should decode to \(expected)")
        }
    }

    // MARK: - Severity Values

    func testSeverityValuesDecodeCorrectly() throws {
        let severities = ["critical", "major", "moderate", "minor"]
        for severity in severities {
            let json = makeTaskJSON(type: "bug", metadata: "\"severity\": \"\(severity)\"")
            let meta = try decodeTaskMetadata(json)
            XCTAssertEqual(meta.severity, severity, "Severity '\(severity)' should decode correctly")
        }
    }

    // MARK: - RCA Status Values

    func testRcaStatusValuesDecodeCorrectly() throws {
        let statuses = ["pending", "investigated", "needs-more-info", "reviewed", "approved"]
        for status in statuses {
            let json = makeTaskJSON(type: "bug", metadata: "\"rca_status\": \"\(status)\"")
            let meta = try decodeTaskMetadata(json)
            XCTAssertEqual(meta.rcaStatus, status, "RCA status '\(status)' should decode correctly")
        }
    }

    // MARK: - Regression Risk Values

    func testRegressionRiskValuesDecodeCorrectly() throws {
        let risks = ["low", "medium", "high"]
        for risk in risks {
            let json = makeTaskJSON(type: "techdebt", metadata: "\"regression_risk\": \"\(risk)\"")
            let meta = try decodeTaskMetadata(json)
            XCTAssertEqual(meta.regressionRisk, risk, "Regression risk '\(risk)' should decode correctly")
        }
    }

    // MARK: - Real-World Task File Format

    /// Mirrors the actual format from ~/.claude/tasks/agile-maestro/157.json
    func testRealWorldBugTaskFormatDecodes() throws {
        let json = """
        {
          "id": "157",
          "subject": "Bug: Overview tab missing metadata fields",
          "description": "## Summary\\nThe Overview tab fails to render v2.0 metadata fields.",
          "owner": "rca-agent",
          "status": "completed",
          "blocks": [],
          "blockedBy": [],
          "metadata": {
            "schema_version": "2.0",
            "type": "bug",
            "severity": "moderate",
            "priority": "P2",
            "approval": "approved",
            "blocked": false,
            "review_stage": null,
            "review_result": null,
            "rca_status": "approved",
            "steps_to_reproduce": [
              "Load a session with tasks that have v2.0 schema metadata",
              "Select task #156 in tree/kanban view",
              "Click the Overview tab in the detail panel"
            ],
            "expected_behavior": "Overview tab displays key metadata fields as visual cards/chips",
            "actual_behavior": "Overview tab shows only P1 badge and CHECKS 10 counter",
            "labels": ["detail-panel", "overview-tab"],
            "claimed_by": "rca-agent",
            "claimed_at": "2026-03-29T00:00:00Z",
            "last_updated_at": "2026-03-29T00:00:00Z"
          }
        }
        """

        let data = Data(json.utf8)
        let item = try decoder.decode(TaskItem.self, from: data)
        let meta = try XCTUnwrap(item.metadata.task)

        XCTAssertEqual(item.id, "157")
        XCTAssertEqual(item.type, .bug)
        XCTAssertEqual(meta.schemaVersion, "2.0")
        XCTAssertEqual(meta.severity, "moderate")
        XCTAssertEqual(meta.rcaStatus, "approved")
        XCTAssertEqual(meta.stepsToReproduce?.count, 3)
        XCTAssertEqual(meta.expectedBehavior, "Overview tab displays key metadata fields as visual cards/chips")
        XCTAssertEqual(meta.actualBehavior, "Overview tab shows only P1 badge and CHECKS 10 counter")
        XCTAssertEqual(meta.claimedBy, "rca-agent")
        XCTAssertNotNil(meta.claimedAt)
        XCTAssertNotNil(meta.lastUpdatedAt)
    }

    // MARK: - Static Empty Sentinel

    func testStaticEmptyHasAllFieldsNil() {
        let empty = TaskSpecificMetadata.empty

        // Bug fields
        XCTAssertNil(empty.severity)
        XCTAssertNil(empty.stepsToReproduce)
        XCTAssertNil(empty.expectedBehavior)
        XCTAssertNil(empty.actualBehavior)
        XCTAssertNil(empty.rcaStatus)
        XCTAssertNil(empty.discoveredFrom)
        XCTAssertNil(empty.discoveredBy)
        XCTAssertNil(empty.affectedFiles)
        XCTAssertNil(empty.regression)
        XCTAssertNil(empty.environment)

        // TechDebt fields
        XCTAssertNil(empty.debtType)
        XCTAssertNil(empty.debtCategory)
        XCTAssertNil(empty.filesAffected)
        XCTAssertNil(empty.regressionRisk)
        XCTAssertNil(empty.impactIfDeferred)
        XCTAssertNil(empty.businessJustification)

        // Timestamp fields
        XCTAssertNil(empty.createdAt)
        XCTAssertNil(empty.lastUpdatedAt)
        XCTAssertNil(empty.createdBy)
    }
}
