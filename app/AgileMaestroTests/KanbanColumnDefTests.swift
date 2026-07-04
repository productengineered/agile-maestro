import XCTest
@testable import AgileMaestro

// MARK: - KanbanColumnDefTests

/// Covers R1.1/R1.2 (SM-KANBAN-800-T1/T2): the `agent_uat` column definition and its
/// epic-gated visibility via `KanbanColumnDef.visibleColumns(hasEpicCards:)`.
final class KanbanColumnDefTests: XCTestCase {

    // MARK: - allColumns Ordering

    func testAllColumnsHasTenEntriesWithAgentUatBetweenProductReviewAndHumanUat() {
        let columns = KanbanColumnDef.allColumns
        XCTAssertEqual(columns.count, 10, "allColumns should have 10 entries after adding agent_uat")

        let ids = columns.map { $0.id }
        guard let productReviewIndex = ids.firstIndex(of: "product_review"),
              let agentUatIndex = ids.firstIndex(of: "agent_uat"),
              let humanUatIndex = ids.firstIndex(of: "human_uat") else {
            XCTFail("Expected product_review, agent_uat, and human_uat columns to exist")
            return
        }
        XCTAssertEqual(agentUatIndex, productReviewIndex + 1,
            "agent_uat should immediately follow product_review")
        XCTAssertEqual(humanUatIndex, agentUatIndex + 1,
            "human_uat should immediately follow agent_uat")
    }

    func testAgentUatColumnUsesDistinctTealDotColor() throws {
        let agentUat = try XCTUnwrap(KanbanColumnDef.allColumns.first { $0.id == "agent_uat" })
        XCTAssertEqual(agentUat.dotColor, "teal")

        let humanUat = try XCTUnwrap(KanbanColumnDef.allColumns.first { $0.id == "human_uat" })
        XCTAssertNotEqual(agentUat.dotColor, humanUat.dotColor,
            "agent_uat's teal dot must be distinct from human_uat's pink dot")
    }

    // MARK: - Epic-Gated Visibility (SM-KANBAN-800-T1/T2)

    func testVisibleColumnsHidesAgentUatWithoutEpicCards() {
        let visible = KanbanColumnDef.visibleColumns(hasEpicCards: false)
        let ids = Set(visible.map { $0.id })

        XCTAssertFalse(ids.contains("agent_uat"), "agent_uat must be hidden when no epic cards exist")
        XCTAssertFalse(ids.contains("security"), "security must be hidden when no epic cards exist")
        XCTAssertFalse(ids.contains("human_uat"), "human_uat must be hidden when no epic cards exist")
        XCTAssertEqual(visible.count, 7, "Only the 7 default columns should be visible without epic cards")
    }

    func testVisibleColumnsShowsAgentUatWithEpicCards() {
        let visible = KanbanColumnDef.visibleColumns(hasEpicCards: true)
        let ids = visible.map { $0.id }

        XCTAssertTrue(ids.contains("agent_uat"), "agent_uat must be visible when epic cards exist")
        XCTAssertEqual(visible.count, 10, "All 10 columns should be visible with epic cards present")

        // Position check: agent_uat still sits between product_review and human_uat
        guard let productReviewIndex = ids.firstIndex(of: "product_review"),
              let agentUatIndex = ids.firstIndex(of: "agent_uat"),
              let humanUatIndex = ids.firstIndex(of: "human_uat") else {
            XCTFail("Expected product_review, agent_uat, and human_uat in visible columns")
            return
        }
        XCTAssertEqual(agentUatIndex, productReviewIndex + 1)
        XCTAssertEqual(humanUatIndex, agentUatIndex + 1)
    }
}
