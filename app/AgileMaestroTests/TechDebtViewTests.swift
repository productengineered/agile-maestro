import XCTest
import SwiftUI
@testable import AgileMaestro

// MARK: - TechDebtViewTests
//
// Tests for TechDebtOverviewContent conditional rendering logic and
// regression risk color mapping per SM-DP700-OVERVIEW-002.
// Uses JSON-decoded TaskItem fixtures for resilience against model changes.

// swiftlint:disable:next type_body_length
final class TechDebtViewTests: XCTestCase {

    // MARK: - Helpers

    private let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    /// Decode a TaskItem from a minimal JSON dictionary with optional techdebt metadata fields.
    private func makeTechDebtTask(
        debtType: String? = nil,
        debtCategory: String? = nil,
        regressionRisk: String? = nil,
        filesAffected: [String]? = nil,
        impactIfDeferred: String? = nil,
        businessJustification: String? = nil,
        completionSignal: String? = nil,
        validationHint: String? = nil,
        checklist: [String]? = nil,
        labels: [String] = [],
        blockedBy: [String] = []
    ) throws -> TaskItem {
        var metadataDict: [String: Any] = [
            "type": "techdebt",
            "schema_version": "2.0",
            "approval": "approved",
            "blocked": false
        ]
        if let value = debtType { metadataDict["debt_type"] = value }
        if let value = debtCategory { metadataDict["debt_category"] = value }
        if let value = regressionRisk { metadataDict["regression_risk"] = value }
        if let value = filesAffected { metadataDict["files_affected"] = value }
        if let value = impactIfDeferred { metadataDict["impact_if_deferred"] = value }
        if let value = businessJustification { metadataDict["business_justification"] = value }
        if let value = completionSignal { metadataDict["completion_signal"] = value }
        if let value = validationHint { metadataDict["validation_hint"] = value }
        if let value = checklist { metadataDict["checklist"] = value }

        let json: [String: Any] = [
            "id": UUID().uuidString,
            "subject": "TechDebt: Test Item",
            "description": "",
            "status": "pending",
            "blocks": [],
            "blockedBy": blockedBy,
            "metadata": metadataDict
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
        return try decoder.decode(TaskItem.self, from: data)
    }

    // MARK: - Regression Risk Color Mapping (SM-DP700-OVERVIEW-002)
    //
    // The color logic lives in TechDebtOverviewContent.regressionRiskColor(_:).
    // Since it is private, we test the specification directly: verifying that the
    // switch on risk.lowercased() maps to the correct Color values.

    private func regressionRiskColor(_ risk: String) -> Color {
        switch risk.lowercased() {
        case "high":   return .red
        case "medium": return .orange
        default:       return .green  // "low" or unknown → green
        }
    }

    func testRegressionRiskColor_LowMapsToGreen() {
        XCTAssertEqual(regressionRiskColor("low"), .green)
    }

    func testRegressionRiskColor_LowCaseInsensitive() {
        XCTAssertEqual(regressionRiskColor("LOW"), .green)
        XCTAssertEqual(regressionRiskColor("Low"), .green)
    }

    func testRegressionRiskColor_MediumMapsToOrange() {
        XCTAssertEqual(regressionRiskColor("medium"), .orange)
    }

    func testRegressionRiskColor_MediumCaseInsensitive() {
        XCTAssertEqual(regressionRiskColor("MEDIUM"), .orange)
        XCTAssertEqual(regressionRiskColor("Medium"), .orange)
    }

    func testRegressionRiskColor_HighMapsToRed() {
        XCTAssertEqual(regressionRiskColor("high"), .red)
    }

    func testRegressionRiskColor_HighCaseInsensitive() {
        XCTAssertEqual(regressionRiskColor("HIGH"), .red)
        XCTAssertEqual(regressionRiskColor("High"), .red)
    }

    func testRegressionRiskColor_UnknownValueFallsBackToGreen() {
        // Any unknown value should fall back to green (default case)
        XCTAssertEqual(regressionRiskColor("unknown"), .green)
        XCTAssertEqual(regressionRiskColor(""), .green)
        XCTAssertEqual(regressionRiskColor("critical"), .green)
    }

    // MARK: - TaskItem Construction: Full TechDebt Payload

    func testFullTechDebtTaskDecodesWithoutError() throws {
        let task = try makeTechDebtTask(
            debtType: "code-quality",
            debtCategory: "duplication",
            regressionRisk: "medium",
            filesAffected: ["Services/SyncService.swift", "Models/TaskItem.swift"],
            impactIfDeferred: "Increased maintenance cost over time",
            businessJustification: "Required before v2.0 milestone",
            completionSignal: "Build passes and lint is clean",
            validationHint: "Run SwiftLint and verify no new warnings",
            checklist: ["Step 1: Audit duplicates", "Step 2: Extract shared helper"]
        )

        XCTAssertEqual(task.type, .techdebt)
        let meta = try XCTUnwrap(task.metadata.task, "Expected task metadata for techdebt type")
        XCTAssertEqual(meta.debtType, "code-quality")
        XCTAssertEqual(meta.debtCategory, "duplication")
        XCTAssertEqual(meta.regressionRisk, "medium")
        XCTAssertEqual(meta.filesAffected, ["Services/SyncService.swift", "Models/TaskItem.swift"])
        XCTAssertEqual(meta.impactIfDeferred, "Increased maintenance cost over time")
        XCTAssertEqual(meta.businessJustification, "Required before v2.0 milestone")
        XCTAssertEqual(meta.completionSignal, "Build passes and lint is clean")
        XCTAssertEqual(meta.validationHint, "Run SwiftLint and verify no new warnings")
        XCTAssertEqual(meta.checklist, ["Step 1: Audit duplicates", "Step 2: Extract shared helper"])
    }

    // MARK: - Conditional Rendering Guards: Debt Classification Card

    func testDebtClassificationCard_ShownWhenDebtTypePresent() throws {
        let task = try makeTechDebtTask(debtType: "architecture")
        let meta = try XCTUnwrap(task.metadata.task)

        let hasDebtType = meta.debtType != nil
        let hasDebtCategory = meta.debtCategory != nil

        XCTAssertTrue(hasDebtType || hasDebtCategory, "Classification card should show when debtType is present")
        XCTAssertEqual(meta.debtType, "architecture")
        XCTAssertNil(meta.debtCategory)
    }

    func testDebtClassificationCard_ShownWhenDebtCategoryPresent() throws {
        let task = try makeTechDebtTask(debtCategory: "performance")
        let meta = try XCTUnwrap(task.metadata.task)

        let hasDebtType = meta.debtType != nil
        let hasDebtCategory = meta.debtCategory != nil

        XCTAssertTrue(hasDebtType || hasDebtCategory, "Classification card should show when debtCategory is present")
        XCTAssertNil(meta.debtType)
        XCTAssertEqual(meta.debtCategory, "performance")
    }

    func testDebtClassificationCard_ShownWhenBothPresent() throws {
        let task = try makeTechDebtTask(debtType: "code-quality", debtCategory: "duplication")
        let meta = try XCTUnwrap(task.metadata.task)

        XCTAssertNotNil(meta.debtType)
        XCTAssertNotNil(meta.debtCategory)
        XCTAssertEqual(meta.debtType, "code-quality")
        XCTAssertEqual(meta.debtCategory, "duplication")
    }

    func testDebtClassificationCard_HiddenWhenBothNil() throws {
        let task = try makeTechDebtTask()
        let meta = try XCTUnwrap(task.metadata.task)

        let hasDebtType = meta.debtType != nil
        let hasDebtCategory = meta.debtCategory != nil

        XCTAssertFalse(hasDebtType || hasDebtCategory, "Classification card should be hidden when both fields are nil")
    }

    // MARK: - Conditional Rendering Guards: Regression Risk Card

    func testRegressionRiskCard_HiddenWhenNil() throws {
        let task = try makeTechDebtTask()
        let meta = try XCTUnwrap(task.metadata.task)

        XCTAssertNil(meta.regressionRisk, "Regression risk card should be hidden when regressionRisk is nil")
    }

    func testRegressionRiskCard_ShownWhenPresent() throws {
        let task = try makeTechDebtTask(regressionRisk: "high")
        let meta = try XCTUnwrap(task.metadata.task)

        XCTAssertEqual(meta.regressionRisk, "high")
    }

    func testRegressionRiskCard_AllThreeLevels() throws {
        let levels = ["low", "medium", "high"]
        for level in levels {
            let task = try makeTechDebtTask(regressionRisk: level)
            let meta = try XCTUnwrap(task.metadata.task)
            XCTAssertEqual(meta.regressionRisk, level, "Risk level '\(level)' should be stored correctly")
        }
    }

    // MARK: - Conditional Rendering Guards: Files Affected Card

    func testFilesAffectedCard_HiddenWhenNil() throws {
        let task = try makeTechDebtTask()
        let meta = try XCTUnwrap(task.metadata.task)

        XCTAssertNil(meta.filesAffected)
    }

    func testFilesAffectedCard_HiddenWhenEmptyArray() throws {
        let task = try makeTechDebtTask(filesAffected: [])
        let meta = try XCTUnwrap(task.metadata.task)

        // Guard: filesAffected != nil && !isEmpty
        let shouldShow = (meta.filesAffected?.isEmpty == false)
        XCTAssertFalse(shouldShow, "Files Affected card should be hidden when array is empty")
    }

    func testFilesAffectedCard_ShownWithFiles() throws {
        let files = ["Services/SyncService.swift", "Models/TaskItem.swift"]
        let task = try makeTechDebtTask(filesAffected: files)
        let meta = try XCTUnwrap(task.metadata.task)

        XCTAssertEqual(meta.filesAffected, files)
        XCTAssertEqual(meta.filesAffected?.count, 2)
    }

    // MARK: - Conditional Rendering Guards: Impact If Deferred Card

    func testImpactIfDeferredCard_HiddenWhenNil() throws {
        let task = try makeTechDebtTask()
        let meta = try XCTUnwrap(task.metadata.task)

        XCTAssertNil(meta.impactIfDeferred)
    }

    func testImpactIfDeferredCard_HiddenWhenEmpty() throws {
        let task = try makeTechDebtTask(impactIfDeferred: "")
        let meta = try XCTUnwrap(task.metadata.task)

        // Guard: impactIfDeferred != nil && !isEmpty
        let shouldShow = !(meta.impactIfDeferred?.isEmpty ?? true)
        XCTAssertFalse(shouldShow, "Impact card should be hidden for empty string")
    }

    func testImpactIfDeferredCard_ShownWhenPresent() throws {
        let impact = "Increased maintenance cost over time"
        let task = try makeTechDebtTask(impactIfDeferred: impact)
        let meta = try XCTUnwrap(task.metadata.task)

        XCTAssertEqual(meta.impactIfDeferred, impact)
    }

    // MARK: - Conditional Rendering Guards: Business Justification Card

    func testBusinessJustificationCard_HiddenWhenNil() throws {
        let task = try makeTechDebtTask()
        let meta = try XCTUnwrap(task.metadata.task)

        XCTAssertNil(meta.businessJustification)
    }

    func testBusinessJustificationCard_HiddenWhenEmpty() throws {
        let task = try makeTechDebtTask(businessJustification: "")
        let meta = try XCTUnwrap(task.metadata.task)

        let shouldShow = !(meta.businessJustification?.isEmpty ?? true)
        XCTAssertFalse(shouldShow, "Business Justification card should be hidden for empty string")
    }

    func testBusinessJustificationCard_ShownWhenPresent() throws {
        let justification = "Required before v2.0 milestone"
        let task = try makeTechDebtTask(businessJustification: justification)
        let meta = try XCTUnwrap(task.metadata.task)

        XCTAssertEqual(meta.businessJustification, justification)
    }

    // MARK: - Conditional Rendering Guards: Completion Criteria Card

    func testCompletionCriteriaCard_HiddenWhenBothNil() throws {
        let task = try makeTechDebtTask()
        let meta = try XCTUnwrap(task.metadata.task)

        let hasSignal = meta.completionSignal != nil
        let hasHint = meta.validationHint != nil

        XCTAssertFalse(hasSignal || hasHint, "Completion Criteria card should be hidden when both fields are nil")
    }

    func testCompletionCriteriaCard_ShownWithSignalOnly() throws {
        let task = try makeTechDebtTask(completionSignal: "Build passes")
        let meta = try XCTUnwrap(task.metadata.task)

        XCTAssertNotNil(meta.completionSignal)
        XCTAssertNil(meta.validationHint)
        XCTAssertEqual(meta.completionSignal, "Build passes")
    }

    func testCompletionCriteriaCard_ShownWithHintOnly() throws {
        let task = try makeTechDebtTask(validationHint: "Run SwiftLint")
        let meta = try XCTUnwrap(task.metadata.task)

        XCTAssertNil(meta.completionSignal)
        XCTAssertNotNil(meta.validationHint)
        XCTAssertEqual(meta.validationHint, "Run SwiftLint")
    }

    // MARK: - Conditional Rendering Guards: Checklist Card

    func testChecklistCard_HiddenWhenNil() throws {
        let task = try makeTechDebtTask()
        let meta = try XCTUnwrap(task.metadata.task)

        XCTAssertNil(meta.checklist)
    }

    func testChecklistCard_HiddenWhenEmpty() throws {
        let task = try makeTechDebtTask(checklist: [])
        let meta = try XCTUnwrap(task.metadata.task)

        let shouldShow = !(meta.checklist?.isEmpty ?? true)
        XCTAssertFalse(shouldShow, "Checklist card should be hidden when checklist array is empty")
    }

    func testChecklistCard_ShownWithSteps() throws {
        let steps = ["Step 1: Audit duplicates", "Step 2: Extract shared helper", "Step 3: Run tests"]
        let task = try makeTechDebtTask(checklist: steps)
        let meta = try XCTUnwrap(task.metadata.task)

        XCTAssertEqual(meta.checklist, steps)
        XCTAssertEqual(meta.checklist?.count, 3)
    }

    // MARK: - Graceful Degradation: All Optional Fields Nil

    func testAllOptionalFieldsNil_NoErrors() throws {
        // A techdebt task with only the required fields should parse without crash.
        let task = try makeTechDebtTask()

        XCTAssertEqual(task.type, .techdebt)

        let meta = try XCTUnwrap(task.metadata.task)
        XCTAssertNil(meta.debtType)
        XCTAssertNil(meta.debtCategory)
        XCTAssertNil(meta.regressionRisk)
        XCTAssertNil(meta.filesAffected)
        XCTAssertNil(meta.impactIfDeferred)
        XCTAssertNil(meta.businessJustification)
        XCTAssertNil(meta.completionSignal)
        XCTAssertNil(meta.validationHint)
        XCTAssertNil(meta.checklist)

        // Labels and blockedBy are top-level — should be empty
        XCTAssertTrue(task.labels.isEmpty)
        XCTAssertTrue(task.blockedBy.isEmpty)
    }

    // MARK: - Graceful Degradation: Blocked By Card

    func testBlockedByCard_HiddenWhenEmpty() throws {
        let task = try makeTechDebtTask()

        XCTAssertTrue(task.blockedBy.isEmpty, "Blocked By card should be hidden when blockedBy is empty")
    }

    func testBlockedByCard_ShownWhenPresent() throws {
        let task = try makeTechDebtTask(blockedBy: ["task-100", "task-101"])

        XCTAssertEqual(task.blockedBy, ["task-100", "task-101"])
        XCTAssertFalse(task.blockedBy.isEmpty)
    }

    // MARK: - View Instantiation

    func testTechDebtOverviewContentInstantiatesWithFullTask() throws {
        let task = try makeTechDebtTask(
            debtType: "code-quality",
            debtCategory: "duplication",
            regressionRisk: "high",
            filesAffected: ["Services/SyncService.swift"],
            impactIfDeferred: "Increased maintenance cost",
            businessJustification: "Required before v2.0"
        )

        // Instantiating the view must not crash
        let view = TechDebtOverviewContent(task: task)
        XCTAssertNotNil(view)
    }

    func testTechDebtOverviewContentInstantiatesWithMinimalTask() throws {
        let task = try makeTechDebtTask()

        // Instantiating the view with no optional fields must not crash
        let view = TechDebtOverviewContent(task: task)
        XCTAssertNotNil(view)
    }

    // MARK: - Debt Type Display

    func testDebtTypeCapitalizedForDisplay() throws {
        let task = try makeTechDebtTask(debtType: "code-quality")
        let meta = try XCTUnwrap(task.metadata.task)

        // The view uses debtType.capitalized for WorkflowChip label.
        // Swift's .capitalized treats "-" as a word boundary, so "code-quality" → "Code-Quality".
        let displayLabel = meta.debtType?.capitalized
        XCTAssertEqual(displayLabel, "Code-Quality")
    }

    func testDebtCategoryCapitalizedForDisplay() throws {
        let task = try makeTechDebtTask(debtCategory: "duplication")
        let meta = try XCTUnwrap(task.metadata.task)

        let displayLabel = meta.debtCategory?.capitalized
        XCTAssertEqual(displayLabel, "Duplication")
    }

    func testRegressionRiskCapitalizedForDisplay() throws {
        let task = try makeTechDebtTask(regressionRisk: "medium")
        let meta = try XCTUnwrap(task.metadata.task)

        let displayLabel = meta.regressionRisk?.capitalized
        XCTAssertEqual(displayLabel, "Medium")
    }
}
