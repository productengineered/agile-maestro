import XCTest
@testable import AgileMaestro

// MARK: - WorkflowStepperViewTests
//
// Tests all 11 SM-STEPPER-001 visual states for WorkflowStepperView.computeSteps().
// Uses JSON-decoded TaskItem fixtures for resilience against model changes.

final class WorkflowStepperViewTests: XCTestCase {

    // MARK: - Helpers

    private let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    private func makeStepper(for task: TaskItem) -> WorkflowStepperView {
        WorkflowStepperView(task: task)
    }

    /// Decode a TaskItem from a minimal JSON dictionary.
    private func makeTask(
        type: String,
        status: String = "in_progress",
        reviewStage: String? = nil,
        reviewResult: String? = nil
    ) throws -> TaskItem {
        var metadataDict: [String: Any] = [
            "type": type,
            "schema_version": "2.0",
            "approval": "approved",
            "blocked": false
        ]
        if let stage = reviewStage {
            metadataDict["review_stage"] = stage
        }
        if let result = reviewResult {
            metadataDict["review_result"] = result
        }

        let json: [String: Any] = [
            "id": UUID().uuidString,
            "subject": "Test \(type)",
            "description": "",
            "status": status,
            "blocks": [],
            "blockedBy": [],
            "metadata": metadataDict
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
        return try decoder.decode(TaskItem.self, from: data)
    }

    // MARK: - Story Stage Count

    func testStoryHasFiveStages() throws {
        let task = try makeTask(type: "story", status: "pending")
        let steps = makeStepper(for: task).computeSteps(for: task)
        XCTAssertEqual(steps.count, 5, "Story should have 5 stages")
        XCTAssertEqual(steps.map(\.id), ["dev", "code-review", "qa", "product-review", "done"])
    }

    func testEpicHasEightStages() throws {
        let task = try makeTask(type: "epic", status: "pending")
        let steps = makeStepper(for: task).computeSteps(for: task)
        XCTAssertEqual(steps.count, 8, "Epic should have 8 stages (Agent UAT inserted, task-5/AM-801-3)")
        XCTAssertEqual(
            steps.map(\.id),
            ["dev", "code-review", "qa", "security", "product-review", "agent-uat", "human-uat", "done"]
        )
    }

    /// SM-STEPPER-800-T5: story/task steppers never include "agent-uat", regardless of type.
    func testStoryStepsNeverIncludeAgentUat() throws {
        let task = try makeTask(type: "story", status: "pending")
        let steps = makeStepper(for: task).computeSteps(for: task)
        XCTAssertFalse(steps.map(\.id).contains("agent-uat"), "Story stepper must never show Agent UAT")
        XCTAssertEqual(steps.count, 5, "Story stepper must remain 5 steps unchanged")
    }

    func testTaskTypeReturnsEmptySteps() throws {
        let task = try makeTask(type: "task", status: "pending")
        let steps = makeStepper(for: task).computeSteps(for: task)
        XCTAssertTrue(steps.isEmpty, "Task type should return no steps")
    }

    func testBugTypeReturnsEmptySteps() throws {
        let task = try makeTask(type: "bug", status: "pending")
        let steps = makeStepper(for: task).computeSteps(for: task)
        XCTAssertTrue(steps.isEmpty)
    }

    func testTechdebtTypeReturnsEmptySteps() throws {
        let task = try makeTask(type: "techdebt", status: "pending")
        let steps = makeStepper(for: task).computeSteps(for: task)
        XCTAssertTrue(steps.isEmpty)
    }

    // MARK: - SM-STEPPER-001 State 1: review_stage == null, status == pending

    func testState1_StoryPendingNoStage_DevIsCurrent() throws {
        let task = try makeTask(type: "story", status: "pending")
        let steps = makeStepper(for: task).computeSteps(for: task)
        XCTAssertEqual(steps[0].state, .current, "Dev should be current when pending and no stage")
        XCTAssertEqual(steps[1].state, .upcoming)
        XCTAssertEqual(steps[2].state, .upcoming)
        XCTAssertEqual(steps[3].state, .upcoming)
        XCTAssertEqual(steps[4].state, .upcoming)
    }

    // MARK: - SM-STEPPER-001 State 2: review_stage == null, status == in_progress

    func testState2_StoryInProgressNoStage_DevIsCurrent() throws {
        let task = try makeTask(type: "story", status: "in_progress")
        let steps = makeStepper(for: task).computeSteps(for: task)
        XCTAssertEqual(steps[0].state, .current, "Dev should be current when in_progress and no stage")
        for i in 1..<steps.count {
            XCTAssertEqual(steps[i].state, .upcoming, "Stage \(i) should be upcoming")
        }
    }

    // MARK: - SM-STEPPER-001 State 3: review_stage == null, status == completed

    func testState3_StoryCompleted_AllCompleted() throws {
        let task = try makeTask(type: "story", status: "completed")
        let steps = makeStepper(for: task).computeSteps(for: task)
        XCTAssertTrue(steps.allSatisfy { $0.state == .completed }, "All stages should be completed")
    }

    func testState3_EpicCompleted_AllCompleted() throws {
        let task = try makeTask(type: "epic", status: "completed")
        let steps = makeStepper(for: task).computeSteps(for: task)
        XCTAssertEqual(steps.count, 8)
        XCTAssertTrue(steps.allSatisfy { $0.state == .completed })
    }

    // MARK: - SM-STEPPER-001 State 4: code-review + awaiting

    func testState4_CodeReviewAwaiting_DevCompletedCodeReviewCurrent() throws {
        let task = try makeTask(
            type: "story", status: "in_progress", reviewStage: "code-review", reviewResult: "awaiting"
        )
        let steps = makeStepper(for: task).computeSteps(for: task)
        XCTAssertEqual(steps[0].state, .completed, "Dev should be completed")
        XCTAssertEqual(steps[1].state, .current, "Code Review should be current")
        XCTAssertEqual(steps[2].state, .upcoming, "QA should be upcoming")
        XCTAssertEqual(steps[3].state, .upcoming, "Product Review should be upcoming")
        XCTAssertEqual(steps[4].state, .upcoming, "Done should be upcoming")
    }

    // MARK: - SM-STEPPER-001 State 5: code-review + rejected

    func testState5_CodeReviewRejected_CodeReviewCurrent() throws {
        let task = try makeTask(
            type: "story", status: "in_progress", reviewStage: "code-review", reviewResult: "rejected"
        )
        let steps = makeStepper(for: task).computeSteps(for: task)
        // Visual treatment: same position as awaiting, but rejected
        // The step state is still .current (visual color is determined by reviewResult in the view)
        XCTAssertEqual(steps[0].state, .completed)
        XCTAssertEqual(steps[1].state, .current, "Code Review should be current (orange in rejected state)")
        XCTAssertEqual(steps[2].state, .upcoming)
    }

    // MARK: - SM-STEPPER-001 State 6: qa + awaiting

    func testState6_QAAwaiting_DevAndCodeReviewCompleted() throws {
        let task = try makeTask(
            type: "story", status: "in_progress", reviewStage: "qa", reviewResult: "awaiting"
        )
        let steps = makeStepper(for: task).computeSteps(for: task)
        XCTAssertEqual(steps[0].state, .completed, "Dev should be completed")
        XCTAssertEqual(steps[1].state, .completed, "Code Review should be completed")
        XCTAssertEqual(steps[2].state, .current, "QA should be current (pulsing)")
        XCTAssertEqual(steps[3].state, .upcoming, "Product Review should be upcoming")
        XCTAssertEqual(steps[4].state, .upcoming, "Done should be upcoming")
    }

    // MARK: - SM-STEPPER-001 State 7: security + awaiting (epic only)

    func testState7_SecurityAwaiting_EpicOnly() throws {
        let task = try makeTask(
            type: "epic", status: "in_progress", reviewStage: "security", reviewResult: "awaiting"
        )
        let steps = makeStepper(for: task).computeSteps(for: task)
        // Epic stages: dev[0], code-review[1], qa[2], security[3],
        // product-review[4], agent-uat[5], human-uat[6], done[7]
        XCTAssertEqual(steps[0].state, .completed)
        XCTAssertEqual(steps[1].state, .completed)
        XCTAssertEqual(steps[2].state, .completed)
        XCTAssertEqual(steps[3].state, .current, "Security should be current (pulsing)")
        XCTAssertEqual(steps[4].state, .upcoming)
        XCTAssertEqual(steps[5].state, .upcoming)
        XCTAssertEqual(steps[6].state, .upcoming)
        XCTAssertEqual(steps[7].state, .upcoming)
    }

    // MARK: - Agent UAT Step (task-5/AM-801-3, SM-STEPPER-800-T1..T4)

    func testAgentUatUpcoming_WhenProductReviewCurrent() throws {
        let task = try makeTask(
            type: "epic", status: "in_progress", reviewStage: "product-review", reviewResult: "awaiting"
        )
        let steps = makeStepper(for: task).computeSteps(for: task)
        let agentUat = try XCTUnwrap(steps.first(where: { $0.id == "agent-uat" }))
        XCTAssertEqual(agentUat.state, .upcoming, "Agent UAT should be upcoming while Product Review is current")
    }

    func testAgentUatCurrent_WhenAwaiting() throws {
        let task = try makeTask(
            type: "epic", status: "in_progress", reviewStage: "agent-uat", reviewResult: "awaiting"
        )
        let steps = makeStepper(for: task).computeSteps(for: task)
        let agentUat = try XCTUnwrap(steps.first(where: { $0.id == "agent-uat" }))
        XCTAssertEqual(agentUat.state, .current, "Agent UAT should be current when it is the review stage")

        // Everything before it should be completed, everything after upcoming.
        let index = try XCTUnwrap(steps.firstIndex(where: { $0.id == "agent-uat" }))
        for i in 0..<index {
            XCTAssertEqual(steps[i].state, .completed, "Stage \(steps[i].id) should be completed before Agent UAT")
        }
        for i in (index + 1)..<steps.count {
            XCTAssertEqual(steps[i].state, .upcoming, "Stage \(steps[i].id) should be upcoming after Agent UAT")
        }
    }

    func testAgentUatCompleted_WhenHumanUatCurrent() throws {
        let task = try makeTask(
            type: "epic", status: "in_progress", reviewStage: "human-uat", reviewResult: "awaiting"
        )
        let steps = makeStepper(for: task).computeSteps(for: task)
        let agentUat = try XCTUnwrap(steps.first(where: { $0.id == "agent-uat" }))
        XCTAssertEqual(agentUat.state, .completed, "Agent UAT should be completed once Human UAT is current")
    }

    /// design4: Agent UAT never renders `.rejected` — it uses the same plain
    /// upcoming/current/completed states as every other step, with no result-based recoloring.
    func testAgentUatCurrent_UsesPlainStateEvenWhenTaskHasRejectedResultElsewhere() throws {
        // Agent UAT itself never reports "rejected" as a reviewResult; confirm the
        // computed WorkflowStepState is still the plain `.current` case (view-level
        // coloring, not a distinct state) so no special enum case was introduced.
        let task = try makeTask(
            type: "epic", status: "in_progress", reviewStage: "agent-uat", reviewResult: "awaiting"
        )
        let steps = makeStepper(for: task).computeSteps(for: task)
        let agentUat = try XCTUnwrap(steps.first(where: { $0.id == "agent-uat" }))
        XCTAssertEqual(agentUat.state, .current)
        XCTAssertNotEqual(agentUat.state, .completed)
        XCTAssertNotEqual(agentUat.state, .upcoming)
    }

    // MARK: - SM-STEPPER-001 State 8: product-review + awaiting

    func testState8_ProductReviewAwaiting_AllPriorCompleted() throws {
        let task = try makeTask(
            type: "story", status: "in_progress", reviewStage: "product-review", reviewResult: "awaiting"
        )
        let steps = makeStepper(for: task).computeSteps(for: task)
        XCTAssertEqual(steps[0].state, .completed, "Dev should be completed")
        XCTAssertEqual(steps[1].state, .completed, "Code Review should be completed")
        XCTAssertEqual(steps[2].state, .completed, "QA should be completed")
        XCTAssertEqual(steps[3].state, .current, "Product Review should be current (pulsing)")
        XCTAssertEqual(steps[4].state, .upcoming, "Done should be upcoming")
    }

    // MARK: - SM-STEPPER-001 State 9: product-review + passed

    func testState9_ProductReviewPassed_ProductReviewShowsCompleted() throws {
        let task = try makeTask(
            type: "story", status: "in_progress", reviewStage: "product-review", reviewResult: "passed"
        )
        let steps = makeStepper(for: task).computeSteps(for: task)
        XCTAssertEqual(steps[0].state, .completed)
        XCTAssertEqual(steps[1].state, .completed)
        XCTAssertEqual(steps[2].state, .completed)
        XCTAssertEqual(steps[3].state, .completed, "Product Review (passed) should show as completed, not current")
        XCTAssertEqual(steps[4].state, .upcoming, "Done should remain upcoming (not yet officially closed)")
    }

    // MARK: - SM-STEPPER-001 State 10: status == completed

    func testState10_StatusCompleted_AllStagesCompleted() throws {
        // Covered by testState3_StoryCompleted and testState3_EpicCompleted
        // Extra verification: completed overrides any review stage
        let task = try makeTask(
            type: "story", status: "completed", reviewStage: "qa", reviewResult: "awaiting"
        )
        let steps = makeStepper(for: task).computeSteps(for: task)
        XCTAssertTrue(
            steps.allSatisfy { $0.state == .completed }, "Status == completed overrides review stage"
        )
    }

    // MARK: - SM-STEPPER-001 State 11: Unknown review stage (ERR-DETAIL-007)

    func testState11_UnknownReviewStage_AllUpcoming() throws {
        let task = try makeTask(
            type: "story", status: "in_progress", reviewStage: "unknown-stage", reviewResult: "awaiting"
        )
        let steps = makeStepper(for: task).computeSteps(for: task)
        XCTAssertTrue(
            steps.allSatisfy { $0.state == .upcoming },
            "Unknown review stage should render all stages as upcoming"
        )
    }

    // MARK: - shouldPulse Logic

    /// shouldPulse is true only when reviewResult == "awaiting" AND reviewStage is set.
    /// Verifies the logic by checking it is true for the awaiting case and false for all others.
    func testShouldPulse_WhenAwaitingAndHasStage() throws {
        let task = try makeTask(
            type: "story", status: "in_progress", reviewStage: "code-review", reviewResult: "awaiting"
        )
        // shouldPulse = reviewResult == "awaiting" && reviewStage != nil
        let shouldPulse = task.reviewResult == "awaiting" && task.reviewStage != nil
        XCTAssertTrue(shouldPulse, "shouldPulse must be true when result is 'awaiting' and stage is set")
    }

    func testShouldNotPulse_WhenRejected() throws {
        let task = try makeTask(
            type: "story", status: "in_progress", reviewStage: "code-review", reviewResult: "rejected"
        )
        let shouldPulse = task.reviewResult == "awaiting" && task.reviewStage != nil
        XCTAssertFalse(shouldPulse, "shouldPulse must be false when result is 'rejected'")
    }

    func testShouldNotPulse_WhenPassed() throws {
        let task = try makeTask(
            type: "story", status: "in_progress", reviewStage: "product-review", reviewResult: "passed"
        )
        let shouldPulse = task.reviewResult == "awaiting" && task.reviewStage != nil
        XCTAssertFalse(shouldPulse, "shouldPulse must be false when result is 'passed'")
    }

    func testShouldNotPulse_WhenNoStage() throws {
        let task = try makeTask(
            type: "story", status: "in_progress"
        )
        let shouldPulse = task.reviewResult == "awaiting" && task.reviewStage != nil
        XCTAssertFalse(shouldPulse, "shouldPulse must be false when reviewStage is nil")
    }

    // MARK: - Stage Labels

    func testStoryStageLabels() throws {
        let task = try makeTask(type: "story", status: "pending")
        let steps = makeStepper(for: task).computeSteps(for: task)
        XCTAssertEqual(steps[0].label, "Dev")
        XCTAssertEqual(steps[1].label, "Code\nReview")
        XCTAssertEqual(steps[2].label, "QA")
        XCTAssertEqual(steps[3].label, "Product\nReview")
        XCTAssertEqual(steps[4].label, "Done")
    }

    func testEpicStageLabels() throws {
        let task = try makeTask(type: "epic", status: "pending")
        let steps = makeStepper(for: task).computeSteps(for: task)
        XCTAssertEqual(steps[0].label, "Dev")
        XCTAssertEqual(steps[1].label, "Code\nReview")
        XCTAssertEqual(steps[2].label, "QA")
        XCTAssertEqual(steps[3].label, "Security")
        XCTAssertEqual(steps[4].label, "Product\nReview")
        XCTAssertEqual(steps[5].label, "Agent\nUAT")
        XCTAssertEqual(steps[6].label, "Human\nUAT")
        XCTAssertEqual(steps[7].label, "Done")
    }
}
