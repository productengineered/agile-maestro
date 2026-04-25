// swiftlint:disable file_length
import XCTest
import SwiftUI
@testable import AgileMaestro

// MARK: - Shared Decoder

private let overviewTestDecoder: JSONDecoder = {
    let dec = JSONDecoder()
    dec.dateDecodingStrategy = .iso8601
    return dec
}()

// MARK: - OverviewContentRenderingTests
//
// Tests for BugOverviewContent, TechDebtOverviewContent, EpicOverviewContent,
// BlocksCard, and DetailHeaderView rendering gate logic.
// Views requiring @Environment are tested via their data-layer conditions.

final class OverviewContentRenderingTests: XCTestCase {

    // MARK: - Fixture Builders

    private func makeBugItem(
        severity: String? = nil,
        rcaStatus: String? = nil,
        stepsToReproduce: [String]? = nil,
        expectedBehavior: String? = nil,
        actualBehavior: String? = nil,
        discoveredFrom: String? = nil,
        regression: Bool? = nil,
        environment: (macosVersion: String?, appVersion: String?)? = nil
    ) throws -> TaskItem {
        var metadataDict: [String: Any] = [
            "type": "bug",
            "schema_version": "2.0",
            "approval": "approved",
            "blocked": false
        ]
        if let val = severity { metadataDict["severity"] = val }
        if let val = rcaStatus { metadataDict["rca_status"] = val }
        if let val = stepsToReproduce { metadataDict["steps_to_reproduce"] = val }
        if let val = expectedBehavior { metadataDict["expected_behavior"] = val }
        if let val = actualBehavior { metadataDict["actual_behavior"] = val }
        if let val = discoveredFrom { metadataDict["discovered_from"] = val }
        if let val = regression { metadataDict["regression"] = val }
        if let env = environment {
            var envDict: [String: Any] = [:]
            if let mac = env.macosVersion { envDict["macos_version"] = mac }
            if let app = env.appVersion { envDict["app_version"] = app }
            metadataDict["environment"] = envDict
        }

        let json: [String: Any] = [
            "id": UUID().uuidString,
            "subject": "Bug: Test bug item",
            "description": "## Summary\nCrash on save.",
            "status": "in_progress",
            "blocks": [] as [String],
            "blockedBy": [] as [String],
            "metadata": metadataDict
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        return try overviewTestDecoder.decode(TaskItem.self, from: data)
    }

    // MARK: - TechDebtOverviewContent: Instantiation (Internal View)

    /// TechDebtOverviewContent is an internal struct with no @Environment dependencies.
    /// Instantiation must not crash for a fully-populated sample.

    func testTechDebtOverviewContentRendersClassificationFields() throws {
        let task = try makeTechDebtItem(
            debtType: "code-quality",
            debtCategory: "duplication",
            regressionRisk: "high",
            impactIfDeferred: "Increased maintenance cost",
            businessJustification: "Required before v2.0"
        )
        XCTAssertEqual(task.type, .techdebt, "Fixture must be a techdebt task")

        // Verify the data-layer conditions that drive TechDebtOverviewContent card visibility.
        let meta = try XCTUnwrap(task.metadata.task)

        // Classification card guard: debtType != nil || debtCategory != nil
        let shouldShowClassification = meta.debtType != nil || meta.debtCategory != nil
        XCTAssertTrue(shouldShowClassification, "Classification card must appear when debtType or debtCategory is set")
        XCTAssertEqual(meta.debtType, "code-quality")
        XCTAssertEqual(meta.debtCategory, "duplication")

        // Regression risk card guard: regressionRisk != nil
        XCTAssertNotNil(meta.regressionRisk, "Regression risk card must appear when regressionRisk is set")
        XCTAssertEqual(meta.regressionRisk, "high")

        // Impact/justification fields decoded for their respective cards
        XCTAssertEqual(meta.impactIfDeferred, "Increased maintenance cost")
        XCTAssertEqual(meta.businessJustification, "Required before v2.0")
    }

    func testTechDebtOverviewContentAllCardsHiddenWhenFieldsNil() throws {
        let task = try makeTechDebtItem()
        XCTAssertEqual(task.type, .techdebt)

        let meta = try XCTUnwrap(task.metadata.task)

        // With no optional fields, all conditional cards must be hidden.
        let shouldShowClassification = meta.debtType != nil || meta.debtCategory != nil
        XCTAssertFalse(shouldShowClassification,
                       "Classification card must be hidden when debtType and debtCategory are both nil")
        XCTAssertNil(meta.regressionRisk, "Regression risk card must be hidden when regressionRisk is nil")
        XCTAssertNil(meta.impactIfDeferred)
        XCTAssertNil(meta.businessJustification)
    }

    func testTechDebtOverviewContentRegressionRiskColorMapping() throws {
        // regressionRiskColor(_:) in TechDebtOverviewContent drives badge color.
        // Verify via the data values that feed into it — high/medium/low/unknown.
        let cases: [(String, String)] = [
            ("high", "high"),
            ("medium", "medium"),
            ("low", "low")
        ]
        for (risk, expected) in cases {
            let task = try makeTechDebtItem(regressionRisk: risk)
            let meta = try XCTUnwrap(task.metadata.task)
            XCTAssertEqual(meta.regressionRisk, expected,
                           "regressionRisk must decode to '\(expected)' for input '\(risk)'")
        }
    }

    // MARK: - BugOverviewContent: Data-Layer Rendering Guards

    // BugOverviewContent is a private struct requiring environment injection.
    // The tests below verify the data conditions that drive its card visibility.
    // Any model change that breaks these conditions would also break the view.

    func testBugOverviewContent_SeverityRCACardShownWhenSeverityPresent() throws {
        let task = try makeBugItem(severity: "major")
        let meta = try XCTUnwrap(task.metadata.task)

        // BugOverviewContent guard: severity != nil || rcaStatus != nil || regression == true
        let shouldShowSeverityRCACard = meta.severity != nil || meta.rcaStatus != nil || meta.regression == true
        XCTAssertTrue(shouldShowSeverityRCACard,
                      "SeverityRCACard must appear when severity is present")
        XCTAssertEqual(meta.severity, "major")
    }

    func testBugOverviewContent_SeverityRCACardShownWhenRCAStatusPresent() throws {
        let task = try makeBugItem(rcaStatus: "approved")
        let meta = try XCTUnwrap(task.metadata.task)

        let shouldShowSeverityRCACard = meta.severity != nil || meta.rcaStatus != nil || meta.regression == true
        XCTAssertTrue(shouldShowSeverityRCACard,
                      "SeverityRCACard must appear when rcaStatus is present")
    }

    func testBugOverviewContent_SeverityRCACardHiddenWhenNoTriageFields() throws {
        let task = try makeBugItem()
        let meta = try XCTUnwrap(task.metadata.task)

        let shouldShowSeverityRCACard = meta.severity != nil || meta.rcaStatus != nil || meta.regression == true
        XCTAssertFalse(shouldShowSeverityRCACard,
                       "SeverityRCACard must be hidden when severity, rcaStatus, and regression are all absent")
    }

    func testBugOverviewContent_ReproStepsCardShownWhenPresent() throws {
        let steps = ["Step 1: Open the app", "Step 2: Tap Save", "Step 3: Observe crash"]
        let task = try makeBugItem(stepsToReproduce: steps)
        let meta = try XCTUnwrap(task.metadata.task)

        // BugOverviewContent guard: stepsToReproduce != nil && !steps.isEmpty
        let shouldShowReproCard = (meta.stepsToReproduce?.isEmpty == false)
        XCTAssertTrue(shouldShowReproCard,
                      "Repro steps card must appear when stepsToReproduce is a non-empty array")
        XCTAssertEqual(meta.stepsToReproduce?.count, 3)
    }

    func testBugOverviewContent_ReproStepsCardHiddenWhenEmptyArray() throws {
        let task = try makeBugItem(stepsToReproduce: [])
        let meta = try XCTUnwrap(task.metadata.task)

        let shouldShowReproCard = (meta.stepsToReproduce?.isEmpty == false)
        XCTAssertFalse(shouldShowReproCard,
                       "Repro steps card must be hidden when stepsToReproduce is an empty array")
    }

    func testBugOverviewContent_BehaviorHStackShownWhenEitherBehaviorPresent() throws {
        // Case A: only expected behavior
        let taskA = try makeBugItem(expectedBehavior: "Should save correctly")
        let metaA = try XCTUnwrap(taskA.metadata.task)
        let showsA = metaA.expectedBehavior != nil || metaA.actualBehavior != nil
        XCTAssertTrue(showsA, "Behavior HStack must render when only expectedBehavior is present")
        XCTAssertNil(metaA.actualBehavior)

        // Case B: only actual behavior
        let taskB = try makeBugItem(actualBehavior: "Crashes immediately")
        let metaB = try XCTUnwrap(taskB.metadata.task)
        let showsB = metaB.expectedBehavior != nil || metaB.actualBehavior != nil
        XCTAssertTrue(showsB, "Behavior HStack must render when only actualBehavior is present")
        XCTAssertNil(metaB.expectedBehavior)

        // Case C: both present
        let taskC = try makeBugItem(expectedBehavior: "Should save", actualBehavior: "Crashes")
        let metaC = try XCTUnwrap(taskC.metadata.task)
        let showsC = metaC.expectedBehavior != nil || metaC.actualBehavior != nil
        XCTAssertTrue(showsC, "Behavior HStack must render when both behavior fields are present")
    }

    func testBugOverviewContent_BehaviorHStackHiddenWhenBothBehaviorsAbsent() throws {
        let task = try makeBugItem()
        let meta = try XCTUnwrap(task.metadata.task)

        let shows = meta.expectedBehavior != nil || meta.actualBehavior != nil
        XCTAssertFalse(shows, "Behavior HStack must be hidden when both behavior fields are nil")
    }

    func testBugOverviewContent_DiscoveredFromCardShownWhenPresent() throws {
        let task = try makeBugItem(discoveredFrom: "task-100")
        let meta = try XCTUnwrap(task.metadata.task)

        XCTAssertNotNil(meta.discoveredFrom,
                        "Discovered From card must appear when discoveredFrom is non-nil")
        XCTAssertEqual(meta.discoveredFrom, "task-100")
    }

    func testBugOverviewContent_EnvironmentCardShownWhenVersionsPresent() throws {
        let task = try makeBugItem(environment: (macosVersion: "15.4", appVersion: "2.0.1"))
        let meta = try XCTUnwrap(task.metadata.task)

        // BugOverviewContent guard: macosVersion != nil || appVersion != nil
        let shouldShowEnvCard = meta.environment?.macosVersion != nil || meta.environment?.appVersion != nil
        XCTAssertTrue(shouldShowEnvCard, "Environment card must appear when macosVersion or appVersion is present")
        XCTAssertEqual(meta.environment?.macosVersion, "15.4")
        XCTAssertEqual(meta.environment?.appVersion, "2.0.1")
    }

    func testBugOverviewContent_EnvironmentCardHiddenWhenBothVersionsAbsent() throws {
        let task = try makeBugItem()
        let meta = try XCTUnwrap(task.metadata.task)

        let shouldShowEnvCard = meta.environment?.macosVersion != nil || meta.environment?.appVersion != nil
        XCTAssertFalse(shouldShowEnvCard, "Environment card must be hidden when environment is nil")
    }

    func testBugOverviewContent_FullPayloadDecodesForRendering() throws {
        let task = try makeBugItem(
            severity: "critical",
            rcaStatus: "investigated",
            stepsToReproduce: ["Step 1", "Step 2"],
            expectedBehavior: "App launches normally",
            actualBehavior: "App crashes immediately",
            discoveredFrom: "task-42",
            regression: true,
            environment: (macosVersion: "15.4", appVersion: "2.0.0")
        )
        XCTAssertEqual(task.type, .bug)

        let meta = try XCTUnwrap(task.metadata.task)
        // All cards should be visible for this full-payload item
        XCTAssertTrue(meta.severity != nil || meta.rcaStatus != nil || meta.regression == true,
                      "SeverityRCACard visible")
        XCTAssertTrue(meta.stepsToReproduce?.isEmpty == false, "Repro steps card visible")
        XCTAssertTrue(meta.expectedBehavior != nil || meta.actualBehavior != nil, "Behavior HStack visible")
        XCTAssertNotNil(meta.discoveredFrom, "Discovered From card visible")
        XCTAssertTrue(meta.environment?.macosVersion != nil || meta.environment?.appVersion != nil,
                      "Environment card visible")
    }

}

// MARK: - Shared Tech Debt Fixture Builder

private func makeTechDebtItem(
    debtType: String? = nil,
    debtCategory: String? = nil,
    regressionRisk: String? = nil,
    impactIfDeferred: String? = nil,
    businessJustification: String? = nil,
    filesAffected: [String]? = nil,
    completionSignal: String? = nil,
    blocks: [String] = []
) throws -> TaskItem {
    var metadataDict: [String: Any] = [
        "type": "techdebt",
        "schema_version": "2.0",
        "approval": "approved",
        "blocked": false
    ]
    if let val = debtType { metadataDict["debt_type"] = val }
    if let val = debtCategory { metadataDict["debt_category"] = val }
    if let val = regressionRisk { metadataDict["regression_risk"] = val }
    if let val = impactIfDeferred { metadataDict["impact_if_deferred"] = val }
    if let val = businessJustification { metadataDict["business_justification"] = val }
    if let val = filesAffected { metadataDict["files_affected"] = val }
    if let val = completionSignal { metadataDict["completion_signal"] = val }

    let json: [String: Any] = [
        "id": UUID().uuidString,
        "subject": "TechDebt: Test item",
        "description": "",
        "status": "pending",
        "blocks": blocks,
        "blockedBy": [] as [String],
        "metadata": metadataDict
    ]
    let data = try JSONSerialization.data(withJSONObject: json)
    return try overviewTestDecoder.decode(TaskItem.self, from: data)
}

// MARK: - EpicOverviewContentRenderingTests

/// Tests for EpicOverviewContent goal callout, BlocksCard rendering gate,
/// and DetailHeaderView metadata row visibility logic.
final class EpicOverviewContentRenderingTests: XCTestCase {

    private func makeEpicItem(
        goal: String? = nil,
        complexity: String? = nil,
        riskLevel: String? = nil,
        blocks: [String] = []
    ) throws -> TaskItem {
        var metadataDict: [String: Any] = [
            "type": "epic",
            "schema_version": "2.0",
            "approval": "approved",
            "blocked": false
        ]
        if let val = goal { metadataDict["goal"] = val }
        if let val = complexity { metadataDict["complexity"] = val }
        if let val = riskLevel { metadataDict["risk_level"] = val }

        let json: [String: Any] = [
            "id": UUID().uuidString,
            "subject": "Epic: Test epic item",
            "description": "",
            "status": "pending",
            "blocks": blocks,
            "blockedBy": [] as [String],
            "metadata": metadataDict
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        return try overviewTestDecoder.decode(TaskItem.self, from: data)
    }

    // MARK: - EpicOverviewContent: Goal Callout Rendering Guard

    // EpicOverviewContent is a private struct requiring environment injection.
    // The tests below verify the data conditions that drive EpicGoalCallout visibility.

    func testEpicOverviewContent_GoalCalloutShownWhenGoalPresent() throws {
        let task = try makeEpicItem(goal: "Deliver the Team View with roster and health metrics")
        let epic = try XCTUnwrap(task.metadata.epic)

        // EpicOverviewContent guard: if let goal = task.metadata.epic?.goal, !goal.isEmpty
        let shouldShowGoalCallout = epic.goal != nil && !(epic.goal?.isEmpty ?? true)
        XCTAssertTrue(shouldShowGoalCallout, "EpicGoalCallout must appear when goal is non-nil and non-empty")
        XCTAssertEqual(epic.goal, "Deliver the Team View with roster and health metrics")
    }

    func testEpicOverviewContent_GoalCalloutHiddenWhenGoalAbsent() throws {
        let task = try makeEpicItem()
        let epic = try XCTUnwrap(task.metadata.epic)

        let shouldShowGoalCallout = epic.goal != nil && !(epic.goal?.isEmpty ?? true)
        XCTAssertFalse(shouldShowGoalCallout, "EpicGoalCallout must be hidden when goal is nil")
        XCTAssertNil(epic.goal)
    }

    func testEpicOverviewContent_GoalCalloutHiddenWhenGoalIsEmptyString() throws {
        // Build directly via JSON since the fixture builder only sets goal when non-nil
        let json = """
        {
          "id": "empty-goal",
          "subject": "Epic: Empty goal",
          "description": "",
          "status": "pending",
          "blocks": [],
          "blockedBy": [],
          "metadata": {
            "type": "epic",
            "goal": ""
          }
        }
        """
        let item = try overviewTestDecoder.decode(TaskItem.self, from: Data(json.utf8))
        let epic = try XCTUnwrap(item.metadata.epic)

        // Empty string goal must not show the callout
        let shouldShowGoalCallout = epic.goal != nil && !(epic.goal?.isEmpty ?? true)
        XCTAssertFalse(shouldShowGoalCallout, "EpicGoalCallout must be hidden when goal is an empty string")
    }

    func testEpicOverviewContent_ComplexityAndRiskLevelDecodedForStatsBar() throws {
        let task = try makeEpicItem(complexity: "L", riskLevel: "medium")
        let epic = try XCTUnwrap(task.metadata.epic)

        // StatsBarView reads complexity and riskLevel from EpicMetadata for pills
        XCTAssertEqual(epic.complexity, "L", "complexity must be available for stats bar pill")
        XCTAssertEqual(epic.riskLevel, "medium", "riskLevel must be available for stats bar pill")
    }

    func testEpicOverviewContent_GoalWithRealAM700Content() throws {
        // swiftlint:disable:next line_length
        let goal = "Make every metadata field from the task schema visible in the detail panel UI, with dedicated views for bug and techdebt types"
        let task = try makeEpicItem(goal: goal)
        let epic = try XCTUnwrap(task.metadata.epic)

        XCTAssertEqual(epic.goal, goal)
        XCTAssertFalse(goal.isEmpty)
        // EpicGoalCallout will render — no crash should occur from long goal text
    }

    // MARK: - BlocksCard: Data Gate (blocks array)

    // BlocksCard renders only when resolved blocks is non-empty.
    // Since resolvedBlocks requires DetailViewModel environment, we test
    // the upstream model that feeds into it.

    func testBlocksCardRenderingGate_EmptyBlocksArray() throws {
        let task = try makeTechDebtItem(blocks: [])
        XCTAssertTrue(task.blocks.isEmpty,
                      "Blocks array must be empty — BlocksCard must not render")
    }

    func testBlocksCardRenderingGate_NonEmptyBlocksArray() throws {
        let task = try makeTechDebtItem(blocks: ["task-200", "task-201"])
        XCTAssertEqual(task.blocks, ["task-200", "task-201"],
                       "Blocks array non-empty — BlocksCard will render (unresolved entries shown as plain text)")
        XCTAssertFalse(task.blocks.isEmpty)
    }

    func testBlocksCardRenderingGate_AllTaskTypesCanHaveBlocks() throws {
        let types = [("epic", TaskType.epic), ("story", TaskType.story), ("bug", TaskType.bug)]
        for (typeString, _) in types {
            let json = """
            {
              "id": "blocks-\(typeString)",
              "subject": "\(typeString) with blocks",
              "description": "",
              "status": "pending",
              "blocks": ["downstream-1"],
              "blockedBy": [],
              "metadata": { "type": "\(typeString)" }
            }
            """
            let item = try overviewTestDecoder.decode(TaskItem.self, from: Data(json.utf8))
            XCTAssertEqual(item.blocks, ["downstream-1"],
                           "blocks must decode for type=\(typeString)")
        }
    }

}

// MARK: - DetailHeaderMetadataRowTests

/// Tests for DetailHeaderView metadataRow visibility logic, exercised via
/// DetailViewModel resolver methods to avoid duplicating resolution logic in tests.
@MainActor
final class DetailHeaderMetadataRowTests: XCTestCase {

    private var viewModel: DetailViewModel!

    override func setUp() {
        super.setUp()
        viewModel = DetailViewModel()
    }

    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }

    func testHeaderMetadataRow_ShownWhenTimestampsPresent() throws {
        let json = """
        {
          "id": "header-ts-1",
          "subject": "Task: Timestamp test",
          "description": "",
          "status": "in_progress",
          "blocks": [],
          "blockedBy": [],
          "metadata": {
            "type": "task",
            "claimed_by": "macos-developer-agent",
            "claimed_at": "2026-03-30T00:00:00Z",
            "created_at": "2026-03-29T00:00:00Z",
            "last_updated_at": "2026-03-30T00:00:00Z"
          }
        }
        """
        let item = try overviewTestDecoder.decode(TaskItem.self, from: Data(json.utf8))

        let resolvedClaimedBy = viewModel.resolvedClaimedBy(for: item)
        XCTAssertEqual(resolvedClaimedBy, "macos-developer-agent",
                       "resolvedClaimedBy must return task.claimedBy for in_progress task")

        let resolvedLastUpdatedAt = viewModel.resolvedLastUpdatedAt(for: item)
        XCTAssertNotNil(resolvedLastUpdatedAt,
                        "resolvedLastUpdatedAt must be non-nil when last_updated_at is present")

        let resolvedCreatedAt = viewModel.resolvedCreatedAt(for: item)
        XCTAssertNotNil(resolvedCreatedAt,
                        "resolvedCreatedAt must be non-nil when created_at is present")

        let hasAnything = (item.status == .inProgress && resolvedClaimedBy != nil)
            || resolvedLastUpdatedAt != nil
            || resolvedCreatedAt != nil
        XCTAssertTrue(hasAnything, "metadataRow must render when at least one timestamp or claimedBy is present")
    }

    func testHeaderMetadataRow_HiddenWhenNoTimestampsOrClaimedBy() throws {
        let json = """
        {
          "id": "header-empty-1",
          "subject": "Task: No timestamps",
          "description": "",
          "status": "pending",
          "blocks": [],
          "blockedBy": [],
          "metadata": {
            "type": "task",
            "priority": "P3"
          }
        }
        """
        let item = try overviewTestDecoder.decode(TaskItem.self, from: Data(json.utf8))

        let resolvedClaimedBy = viewModel.resolvedClaimedBy(for: item)
        let resolvedLastUpdatedAt = viewModel.resolvedLastUpdatedAt(for: item)
        let resolvedCreatedAt = viewModel.resolvedCreatedAt(for: item)

        let hasAnything = (item.status == .inProgress && resolvedClaimedBy != nil)
            || resolvedLastUpdatedAt != nil
            || resolvedCreatedAt != nil

        XCTAssertFalse(hasAnything, "metadataRow must be hidden when no timestamps or claimedBy are present")
    }

    func testHeaderMetadataRow_ShownForInProgressWithClaimedByOnly() throws {
        let json = """
        {
          "id": "header-claim-1",
          "subject": "Task: In Progress Claimed",
          "description": "",
          "status": "in_progress",
          "blocks": [],
          "blockedBy": [],
          "metadata": {
            "type": "task",
            "claimed_by": "macos-developer-agent"
          }
        }
        """
        let item = try overviewTestDecoder.decode(TaskItem.self, from: Data(json.utf8))

        let resolvedClaimedBy = viewModel.resolvedClaimedBy(for: item)
        let resolvedLastUpdatedAt = viewModel.resolvedLastUpdatedAt(for: item)
        let resolvedCreatedAt = viewModel.resolvedCreatedAt(for: item)

        let hasAnything = (item.status == .inProgress && resolvedClaimedBy != nil)
            || resolvedLastUpdatedAt != nil
            || resolvedCreatedAt != nil

        XCTAssertTrue(hasAnything,
                      "metadataRow must render for in_progress task with claimedBy even if no timestamps")
        XCTAssertEqual(resolvedClaimedBy, "macos-developer-agent")
        XCTAssertNil(resolvedLastUpdatedAt)
        XCTAssertNil(resolvedCreatedAt)
    }

    func testHeaderMetadataRow_ClaimedByNotShownWhenStatusIsNotInProgress() throws {
        // A completed task with claimedBy must NOT show the claimed-by label
        // (DetailHeaderView.metadataRow: only shows claimedBy when task.status == .inProgress)
        let json = """
        {
          "id": "header-completed-1",
          "subject": "Task: Completed with claimedBy",
          "description": "",
          "status": "completed",
          "blocks": [],
          "blockedBy": [],
          "metadata": {
            "type": "task",
            "claimed_by": "macos-developer-agent",
            "last_updated_at": "2026-03-30T00:00:00Z"
          }
        }
        """
        let item = try overviewTestDecoder.decode(TaskItem.self, from: Data(json.utf8))
        XCTAssertEqual(item.status, .completed)

        let resolvedClaimedBy = viewModel.resolvedClaimedBy(for: item)
        XCTAssertNotNil(resolvedClaimedBy, "claimedBy is in metadata")

        // For completed tasks, the condition (status == .inProgress && claimedBy != nil) is false
        let showsClaimedByRow = item.status == .inProgress && resolvedClaimedBy != nil
        XCTAssertFalse(showsClaimedByRow,
                       "claimedBy row must NOT render when task status is completed (only in_progress)")

        // But hasAnything may still be true due to lastUpdatedAt
        let resolvedLastUpdatedAt = viewModel.resolvedLastUpdatedAt(for: item)
        let resolvedCreatedAt = viewModel.resolvedCreatedAt(for: item)
        let hasAnything = showsClaimedByRow || resolvedLastUpdatedAt != nil || resolvedCreatedAt != nil
        XCTAssertTrue(hasAnything, "metadataRow still renders due to lastUpdatedAt")
    }

    func testHeaderMetadataRow_EpicUsesEpicLastUpdatedAt() throws {
        let json = """
        {
          "id": "header-epic-1",
          "subject": "Epic: With last_updated_at",
          "description": "",
          "status": "pending",
          "blocks": [],
          "blockedBy": [],
          "metadata": {
            "type": "epic",
            "last_updated_at": "2026-03-30T00:00:00Z"
          }
        }
        """
        let item = try overviewTestDecoder.decode(TaskItem.self, from: Data(json.utf8))

        let resolvedLastUpdatedAt = viewModel.resolvedLastUpdatedAt(for: item)
        XCTAssertNotNil(resolvedLastUpdatedAt,
                        "resolvedLastUpdatedAt must fall back to epic.lastUpdatedAt for epic type")

        let resolvedCreatedAt = viewModel.resolvedCreatedAt(for: item)
        let hasAnything = (item.status == .inProgress && viewModel.resolvedClaimedBy(for: item) != nil)
            || resolvedLastUpdatedAt != nil
            || resolvedCreatedAt != nil
        XCTAssertTrue(hasAnything, "metadataRow must render for epic with last_updated_at")
    }
}
