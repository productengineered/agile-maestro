// swiftlint:disable file_length
import XCTest
@testable import AgileMaestro

// MARK: - Column Assignment Test Case

private struct ColumnAssignmentCase {
    let type: String
    let status: String
    let approval: String
    let reviewStage: String?
    let reviewResult: String?
    let expectedColumn: String
}

// MARK: - Type Filter Test Case

private struct TypeFilterCase {
    let filter: KanbanTypeFilter
    let expectedId: String
    let expectedCount: Int
}

// MARK: - KanbanViewModelTests

@MainActor
final class KanbanViewModelTests: XCTestCase {

    // MARK: - Properties

    private var sut: KanbanViewModel!

    // MARK: - Setup / Teardown

    override func setUp() async throws {
        try await super.setUp()
        sut = KanbanViewModel()
    }

    override func tearDown() async throws {
        sut = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    func makeItem(
        id: String,
        type: String,
        status: String = "pending",
        subject: String? = nil,
        parentId: String? = nil,
        approval: String = "pending",
        blocked: Bool = false,
        reviewStage: String? = nil,
        reviewResult: String? = nil,
        lastUpdatedAt: String? = nil
    ) throws -> TaskItem {
        let parentField: String
        if type == "story" || type == "task" || type == "bug" || type == "techdebt",
           let pid = parentId {
            parentField = "\"parent\": \"\(pid)\","
        } else {
            parentField = ""
        }

        let reviewStageField = reviewStage.map { "\"review_stage\": \"\($0)\"," } ?? ""
        let reviewResultField = reviewResult.map { "\"review_result\": \"\($0)\"," } ?? ""
        let lastUpdatedField = lastUpdatedAt.map { "\"last_updated_at\": \"\($0)\"," } ?? ""

        let itemSubject = subject ?? "Subject \(id)"
        let json = """
        {
          "id": "\(id)",
          "subject": "\(itemSubject)",
          "description": "Description \(id)",
          "status": "\(status)",
          "blocks": [],
          "blockedBy": [],
          "metadata": {
            "type": "\(type)",
            \(parentField)
            "priority": "P2",
            "approval": "\(approval)",
            "blocked": \(blocked),
            \(reviewStageField)
            \(reviewResultField)
            \(lastUpdatedField)
            "schema_version": "2.0"
          }
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TaskItem.self, from: data)
    }

    // MARK: - setTasks: Empty Input

    func testSetTasksWithEmptyArrayProducesNoCards() {
        sut.setTasks([])

        XCTAssertTrue(sut.allCards.isEmpty)
    }
}

// MARK: - Blocked-Parent Cascade Tests

@MainActor
extension KanbanViewModelTests {

    func testInProgressTaskWithBlockedParentStoryPlacedInApproved() throws {
        // Given: a story that is blocked and a child task that is in_progress
        let story = try makeItem(
            id: "story-blocked",
            type: "story",
            status: "in_progress",
            approval: "approved",
            blocked: true
        )
        let task = try makeItem(
            id: "task-child",
            type: "task",
            status: "in_progress",
            parentId: "story-blocked",
            approval: "approved"
        )
        sut.setTasks([story, task])

        // Then: the child task card should be in "approved", not "in_dev"
        let taskCard = try XCTUnwrap(sut.allCards.first { $0.id == "task-child" })
        XCTAssertEqual(taskCard.column, "approved",
            "in_progress task whose parent story is blocked must be placed in 'approved'")
    }

    func testInProgressTaskWithUnblockedParentStoryRemainsInDev() throws {
        // Given: a story that is NOT blocked and a child task that is in_progress
        let story = try makeItem(
            id: "story-ok",
            type: "story",
            status: "in_progress",
            approval: "approved",
            blocked: false
        )
        let task = try makeItem(
            id: "task-child",
            type: "task",
            status: "in_progress",
            parentId: "story-ok",
            approval: "approved"
        )
        sut.setTasks([story, task])

        // Then: the child task card should stay in "in_dev"
        let taskCard = try XCTUnwrap(sut.allCards.first { $0.id == "task-child" })
        XCTAssertEqual(taskCard.column, "in_dev",
            "in_progress task whose parent story is not blocked must stay in 'in_dev'")
    }
}

// MARK: - Column Assignment Tests

@MainActor
extension KanbanViewModelTests {

    func testColumnAssignment() throws {
        let cases = [
            ColumnAssignmentCase(type: "task", status: "pending",
                                 approval: "pending", reviewStage: nil,
                                 reviewResult: nil, expectedColumn: "backlog"),
            ColumnAssignmentCase(type: "task", status: "pending",
                                 approval: "approved", reviewStage: nil,
                                 reviewResult: nil, expectedColumn: "approved"),
            ColumnAssignmentCase(type: "task", status: "in_progress",
                                 approval: "approved", reviewStage: nil,
                                 reviewResult: nil, expectedColumn: "in_dev"),
            ColumnAssignmentCase(type: "task", status: "completed",
                                 approval: "approved", reviewStage: nil,
                                 reviewResult: nil, expectedColumn: "done"),
            ColumnAssignmentCase(type: "story", status: "pending",
                                 approval: "approved", reviewStage: "code-review",
                                 reviewResult: "awaiting", expectedColumn: "code_review"),
            ColumnAssignmentCase(type: "story", status: "pending",
                                 approval: "approved", reviewStage: "qa",
                                 reviewResult: "awaiting", expectedColumn: "qa"),
            ColumnAssignmentCase(type: "story", status: "pending",
                                 approval: "approved", reviewStage: "security",
                                 reviewResult: "awaiting", expectedColumn: "security"),
            ColumnAssignmentCase(type: "story", status: "pending",
                                 approval: "approved", reviewStage: "product-review",
                                 reviewResult: "awaiting", expectedColumn: "product_review"),
            ColumnAssignmentCase(type: "epic", status: "pending",
                                 approval: "approved", reviewStage: "agent-uat",
                                 reviewResult: "awaiting", expectedColumn: "agent_uat"),
            ColumnAssignmentCase(type: "story", status: "pending",
                                 approval: "approved", reviewStage: "human-uat",
                                 reviewResult: "awaiting", expectedColumn: "human_uat")
        ]

        for (idx, tc) in cases.enumerated() {
            let item = try makeItem(
                id: "item-\(idx)",
                type: tc.type,
                status: tc.status,
                approval: tc.approval,
                reviewStage: tc.reviewStage,
                reviewResult: tc.reviewResult
            )
            sut.setTasks([item])
            let card = try XCTUnwrap(sut.allCards.first, "No card at index \(idx)")
            XCTAssertEqual(card.column, tc.expectedColumn,
                "Index \(idx): type=\(tc.type) status=\(tc.status) → " +
                "expected \(tc.expectedColumn), got \(card.column)")
        }
    }

    func testReviewStageRequiresAwaitingResult() throws {
        let item = try makeItem(
            id: "r1",
            type: "story",
            status: "pending",
            approval: "approved",
            reviewStage: "code-review",
            reviewResult: "rejected"
        )
        sut.setTasks([item])

        let card = try XCTUnwrap(sut.allCards.first)
        XCTAssertEqual(card.column, "approved",
            "Rejected review stage should not assign review column")
    }

    func testInProgressTaskWithStaleReviewStageGoesToInDev() throws {
        // Regression: an inProgress item that still carries reviewStage + "awaiting"
        // metadata must land in "in_dev", not a review column (FR-4.2).
        let task = try makeItem(
            id: "stale-review",
            type: "story",
            status: "in_progress",
            approval: "approved",
            reviewStage: "code-review",
            reviewResult: "awaiting"
        )
        sut.setTasks([task])

        let card = try XCTUnwrap(sut.allCards.first)
        XCTAssertEqual(card.column, "in_dev",
            "inProgress item with stale reviewStage must be placed in 'in_dev', not 'code_review'")
        XCTAssertTrue(sut.cards(for: "code_review").isEmpty,
            "code_review column must be empty when the only item is inProgress")
    }
}

// MARK: - Epic ID Cascade Tests

@MainActor
extension KanbanViewModelTests {

    func testEpicCardUsesOwnIdAsEpicDisplayId() throws {
        let epic = try makeItem(id: "epic-1", type: "epic")
        sut.setTasks([epic])

        // When no metadata displayId is set, falls back to task.id
        let card = try XCTUnwrap(sut.allCards.first { $0.id == "epic-1" })
        XCTAssertEqual(card.epicDisplayId, "epic-1")
    }

    func testStoryInheritsEpicDisplayIdFromParent() throws {
        let epic = try makeItem(id: "epic-1", type: "epic")
        let story = try makeItem(id: "story-1", type: "story", parentId: "epic-1")
        sut.setTasks([epic, story])

        let card = try XCTUnwrap(sut.allCards.first { $0.id == "story-1" })
        XCTAssertEqual(card.epicDisplayId, "epic-1")
    }

    func testTaskInheritsEpicDisplayIdThroughStory() throws {
        let epic = try makeItem(id: "epic-1", type: "epic")
        let story = try makeItem(id: "story-1", type: "story", parentId: "epic-1")
        let task = try makeItem(id: "task-1", type: "task", parentId: "story-1")
        sut.setTasks([epic, story, task])

        let card = try XCTUnwrap(sut.allCards.first { $0.id == "task-1" })
        XCTAssertEqual(card.epicDisplayId, "epic-1")
    }

    func testOrphanTaskHasNilEpicDisplayId() throws {
        let task = try makeItem(id: "task-orphan", type: "task")
        sut.setTasks([task])

        let card = try XCTUnwrap(sut.allCards.first)
        XCTAssertNil(card.epicDisplayId)
    }

    /// Regression test: availableEpicIDs and epicDisplayId must use the human-readable
    /// display ID (e.g. "AM-400"), NOT the internal task file ID (e.g. "106").
    ///
    /// This guards against a class of bug where resolveEpicId() returns task.id
    /// instead of task.displayId, causing the filter dropdown to show raw integers.
    func testAvailableEpicIDsUsesDisplayIdNotInternalId() throws {
        // Epic with internal file ID "106" but displayId "AM-400" (from metadata.id)
        let epicJson = """
        {
          "id": "106",
          "subject": "Kanban Board Epic",
          "description": "Epic description",
          "status": "in_progress",
          "blocks": [],
          "blockedBy": [],
          "metadata": {
            "type": "epic",
            "id": "AM-400",
            "priority": "P1",
            "approval": "approved",
            "blocked": false,
            "schema_version": "2.0"
          }
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let epicData = try XCTUnwrap(epicJson.data(using: .utf8))
        let epic = try decoder.decode(TaskItem.self, from: epicData)

        let story = try makeItem(id: "107", type: "story", parentId: "106")
        sut.setTasks([epic, story])

        // availableEpicIDs must contain "AM-400" (displayId), not "106" (internal id)
        XCTAssertTrue(sut.availableEpicIDs.contains("AM-400"),
            "availableEpicIDs should use displayId 'AM-400', not internal id '106'")
        XCTAssertFalse(sut.availableEpicIDs.contains("106"),
            "availableEpicIDs must not expose internal task file IDs")

        // Epic card's epicDisplayId must also be "AM-400"
        let epicCard = try XCTUnwrap(sut.allCards.first { $0.id == "106" })
        XCTAssertEqual(epicCard.epicDisplayId, "AM-400",
            "Epic card.epicDisplayId should use displayId 'AM-400'")

        // Story card must inherit "AM-400" through the cascade
        let storyCard = try XCTUnwrap(sut.allCards.first { $0.id == "107" })
        XCTAssertEqual(storyCard.epicDisplayId, "AM-400",
            "Story card.epicDisplayId should inherit 'AM-400' from parent epic")
    }
}

// MARK: - Sorting Tests

@MainActor
extension KanbanViewModelTests {

    func testSortingWithinColumnByTypePriority() throws {
        let task = try makeItem(id: "t1", type: "task")
        let epic = try makeItem(id: "e1", type: "epic")
        let story = try makeItem(id: "s1", type: "story")
        let bug = try makeItem(id: "b1", type: "bug")
        let techdebt = try makeItem(id: "td1", type: "techdebt")
        sut.setTasks([task, bug, techdebt, story, epic])

        let backlogCards = sut.cards(for: "backlog")
        let types = backlogCards.map { $0.type }
        XCTAssertEqual(types, [.epic, .story, .bug, .techdebt, .task])
    }

    func testSortingRejectedItemsFloatToTopWithinType() throws {
        let taskNormal = try makeItem(id: "t-normal", type: "task", subject: "Zebra task")
        let taskRejected = try makeItem(
            id: "t-rejected", type: "task", subject: "Alpha task",
            reviewStage: nil, reviewResult: "rejected"
        )
        sut.setTasks([taskNormal, taskRejected])

        let backlogCards = sut.cards(for: "backlog")
        XCTAssertEqual(backlogCards.first?.id, "t-rejected",
            "Rejected task should float above non-rejected task")
    }

    func testSortingAlphabeticalFallback() throws {
        let taskA = try makeItem(id: "ta", type: "task", subject: "Alpha")
        let taskB = try makeItem(id: "tb", type: "task", subject: "Bravo")
        let taskC = try makeItem(id: "tc", type: "task", subject: "Charlie")
        sut.setTasks([taskC, taskA, taskB])

        let backlogCards = sut.cards(for: "backlog")
        let titles = backlogCards.map { $0.title }
        XCTAssertEqual(titles, ["Alpha", "Bravo", "Charlie"])
    }

    func testDoneColumnSortsByCompletedAtDescending() throws {
        let earlier = try makeItem(
            id: "epic-old",
            type: "epic",
            status: "completed",
            lastUpdatedAt: "2024-01-01T00:00:00Z"
        )
        let later = try makeItem(
            id: "epic-new",
            type: "epic",
            status: "completed",
            lastUpdatedAt: "2025-06-01T00:00:00Z"
        )
        sut.setTasks([earlier, later])

        let doneCards = sut.cards(for: "done")
        XCTAssertEqual(doneCards.count, 2)
        XCTAssertEqual(doneCards.first?.id, "epic-new",
            "Most recently completed card should appear first")
    }

    func testDoneColumnNilCompletedAtSortsToBottom() throws {
        let taskWithDate = try makeItem(
            id: "epic-dated",
            type: "epic",
            status: "completed",
            lastUpdatedAt: "2025-01-01T00:00:00Z"
        )
        let itemNoDate = try makeItem(id: "story-nodated", type: "story", status: "completed")
        sut.setTasks([itemNoDate, taskWithDate])

        let doneCards = sut.cards(for: "done")
        XCTAssertEqual(doneCards.count, 2)
        XCTAssertEqual(doneCards.first?.id, "epic-dated",
            "Card with completedAt should sort above card with nil completedAt")
        XCTAssertEqual(doneCards.last?.id, "story-nodated")
    }

    /// R1.3 / SM-KANBAN-800-T5: agent_uat's column position must fall strictly
    /// between product_review and human_uat in the globally sorted card list.
    func testColumnSortOrderPlacesAgentUatBetweenProductReviewAndHumanUat() throws {
        let productReviewEpic = try makeItem(
            id: "epic-product-review", type: "epic",
            reviewStage: "product-review", reviewResult: "awaiting"
        )
        let agentUatEpic = try makeItem(
            id: "epic-agent-uat", type: "epic",
            reviewStage: "agent-uat", reviewResult: "awaiting"
        )
        let humanUatEpic = try makeItem(
            id: "epic-human-uat", type: "epic",
            reviewStage: "human-uat", reviewResult: "awaiting"
        )
        // Shuffle the input order to prove the ViewModel — not incidental insertion
        // order — is responsible for the resulting sort.
        sut.setTasks([humanUatEpic, agentUatEpic, productReviewEpic])

        let orderedColumns = sut.allCards.map { $0.column }
        let productReviewIndex = try XCTUnwrap(orderedColumns.firstIndex(of: "product_review"))
        let agentUatIndex = try XCTUnwrap(orderedColumns.firstIndex(of: "agent_uat"))
        let humanUatIndex = try XCTUnwrap(orderedColumns.firstIndex(of: "human_uat"))

        XCTAssertLessThan(productReviewIndex, agentUatIndex,
            "agent_uat must sort after product_review")
        XCTAssertLessThan(agentUatIndex, humanUatIndex,
            "agent_uat must sort before human_uat")
    }

    /// Per agent-uat-stage-reference.md, the agent-uat stage never transitions
    /// review_result to "rejected" — a fix-loop round stays at review_result
    /// "awaiting" and must remain in the agent_uat column, not bounce through a
    /// rejected-style column change.
    func testAgentUatFixLoopRoundStaysInAgentUatColumn() throws {
        let firstPass = try makeItem(
            id: "epic-fix-loop", type: "epic",
            reviewStage: "agent-uat", reviewResult: "awaiting"
        )
        sut.setTasks([firstPass])
        let firstCard = try XCTUnwrap(sut.allCards.first { $0.id == "epic-fix-loop" })
        XCTAssertEqual(firstCard.column, "agent_uat")

        // Simulate a subsequent fix-loop round: same task, still agent-uat/awaiting.
        let fixLoopRound = try makeItem(
            id: "epic-fix-loop", type: "epic",
            reviewStage: "agent-uat", reviewResult: "awaiting"
        )
        sut.setTasks([fixLoopRound])
        let fixLoopCard = try XCTUnwrap(sut.allCards.first { $0.id == "epic-fix-loop" })
        XCTAssertEqual(fixLoopCard.column, "agent_uat",
            "Fix-loop round must stay in agent_uat; agent-uat never uses review_result 'rejected'")
    }
}

// MARK: - Filtering Tests

@MainActor
extension KanbanViewModelTests {

    func testTypeFilterAllShowsEveryCard() throws {
        let epic = try makeItem(id: "e1", type: "epic")
        let story = try makeItem(id: "s1", type: "story")
        let task = try makeItem(id: "t1", type: "task")
        sut.setTasks([epic, story, task])
        sut.typeFilter = .all

        XCTAssertEqual(sut.filteredCards.count, 3)
    }

    func testTypeFilterEpicShowsOnlyEpics() throws {
        let epic = try makeItem(id: "e1", type: "epic")
        let story = try makeItem(id: "s1", type: "story")
        let task = try makeItem(id: "t1", type: "task")
        sut.setTasks([epic, story, task])
        sut.typeFilter = .epic

        let filtered = sut.filteredCards
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.id, "e1")
    }

    func testTypeFilterEachCaseMapsCorrectly() throws {
        let epic = try makeItem(id: "e1", type: "epic")
        let story = try makeItem(id: "s1", type: "story")
        let task = try makeItem(id: "t1", type: "task")
        let bug = try makeItem(id: "b1", type: "bug")
        let techdebt = try makeItem(id: "td1", type: "techdebt")
        sut.setTasks([epic, story, task, bug, techdebt])

        let cases = [
            TypeFilterCase(filter: .epic, expectedId: "e1", expectedCount: 1),
            TypeFilterCase(filter: .story, expectedId: "s1", expectedCount: 1),
            TypeFilterCase(filter: .task, expectedId: "t1", expectedCount: 1),
            TypeFilterCase(filter: .bug, expectedId: "b1", expectedCount: 1),
            TypeFilterCase(filter: .techdebt, expectedId: "td1", expectedCount: 1)
        ]
        for tc in cases {
            sut.typeFilter = tc.filter
            let result = sut.filteredCards
            XCTAssertEqual(result.count, tc.expectedCount,
                "Filter \(tc.filter): expected \(tc.expectedCount) card(s)")
            XCTAssertEqual(result.first?.id, tc.expectedId,
                "Filter \(tc.filter): expected card \(tc.expectedId)")
        }
    }

    func testEpicFilterShowsOnlyMatchingEpicId() throws {
        let epic1 = try makeItem(id: "epic-A", type: "epic")
        let epic2 = try makeItem(id: "epic-B", type: "epic")
        let storyA = try makeItem(id: "story-A", type: "story", parentId: "epic-A")
        let storyB = try makeItem(id: "story-B", type: "story", parentId: "epic-B")
        sut.setTasks([epic1, epic2, storyA, storyB])
        sut.epicFilter = "epic-A"

        let ids = Set(sut.filteredCards.map { $0.id })
        XCTAssertTrue(ids.contains("epic-A"), "Epic A should be visible")
        XCTAssertTrue(ids.contains("story-A"), "Story under epic A should be visible")
        XCTAssertFalse(ids.contains("epic-B"), "Epic B should be hidden")
        XCTAssertFalse(ids.contains("story-B"), "Story under epic B should be hidden")
    }

    func testEpicFilterNilShowsAllCards() throws {
        let epic1 = try makeItem(id: "epic-A", type: "epic")
        let epic2 = try makeItem(id: "epic-B", type: "epic")
        sut.setTasks([epic1, epic2])
        sut.epicFilter = nil

        XCTAssertEqual(sut.filteredCards.count, 2)
    }

    func testCombinedTypeAndEpicFilterUsesAndLogic() throws {
        let epic1 = try makeItem(id: "epic-A", type: "epic")
        let epic2 = try makeItem(id: "epic-B", type: "epic")
        let storyA = try makeItem(id: "story-A", type: "story", parentId: "epic-A")
        let taskA = try makeItem(id: "task-A", type: "task", parentId: "story-A")
        sut.setTasks([epic1, epic2, storyA, taskA])

        sut.typeFilter = .story
        sut.epicFilter = "epic-A"

        let filtered = sut.filteredCards
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.id, "story-A",
            "Only story with epicId==epic-A should pass combined filter")
    }

    func testSetTasksClearsStaleEpicFilterOnSessionSwitch() throws {
        // Given: board loaded with epic-A, filter set to it
        let epic1 = try makeItem(id: "epic-A", type: "epic")
        let story1 = try makeItem(id: "story-A", type: "story", parentId: "epic-A")
        sut.setTasks([epic1, story1])
        sut.epicFilter = "epic-A"
        XCTAssertEqual(sut.epicFilter, "epic-A")

        // When: session switch brings a completely different task set (no epic-A)
        let epic2 = try makeItem(id: "epic-B", type: "epic")
        sut.setTasks([epic2])

        // Then: stale epicFilter is cleared to prevent empty board
        XCTAssertNil(sut.epicFilter,
            "epicFilter should be cleared when the filtered epic is no longer present")
    }

    func testSetTasksPreservesEpicFilterWhenEpicStillPresent() throws {
        // Given: board loaded with epic-A, filter set to it
        let epic = try makeItem(id: "epic-A", type: "epic")
        sut.setTasks([epic])
        let filterId = sut.availableEpicIDs.first
        sut.epicFilter = filterId
        XCTAssertNotNil(sut.epicFilter)

        // When: tasks are refreshed and the same epic is still present
        let epicRefreshed = try makeItem(id: "epic-A", type: "epic")
        let story = try makeItem(id: "story-A", type: "story", parentId: "epic-A")
        sut.setTasks([epicRefreshed, story])

        // Then: epicFilter is preserved because the epic still exists
        XCTAssertEqual(sut.epicFilter, filterId,
            "epicFilter should be preserved when the filtered epic is still present")
    }

    func testSetTasksEmptyInputClearsEpicFilter() throws {
        // Given: board loaded with an epic and a filter applied
        let epic = try makeItem(id: "epic-A", type: "epic")
        sut.setTasks([epic])
        sut.epicFilter = "epic-A"

        // When: empty task array (e.g. loading state)
        sut.setTasks([])

        // Then: epicFilter is also cleared
        XCTAssertNil(sut.epicFilter,
            "epicFilter should be cleared when setTasks receives an empty array")
    }

    func testCombinedFilterNoMatchProducesEmpty() throws {
        let epic1 = try makeItem(id: "epic-A", type: "epic")
        let story = try makeItem(id: "story-A", type: "story", parentId: "epic-A")
        sut.setTasks([epic1, story])

        sut.typeFilter = .bug
        sut.epicFilter = "epic-A"

        XCTAssertTrue(sut.filteredCards.isEmpty)
    }
}

// MARK: - Computed Property Tests

@MainActor
extension KanbanViewModelTests {

    func testFilteredCountMatchesFilteredCardsCount() throws {
        let epic = try makeItem(id: "e1", type: "epic")
        let task = try makeItem(id: "t1", type: "task")
        sut.setTasks([epic, task])
        sut.typeFilter = .epic

        XCTAssertEqual(sut.filteredCount, sut.filteredCards.count)
        XCTAssertEqual(sut.filteredCount, 1)
    }

    func testAvailableEpicIDsReturnsUniqueSortedEpicIds() throws {
        let epic1 = try makeItem(id: "epic-A", type: "epic")
        let epic2 = try makeItem(id: "epic-B", type: "epic")
        let story = try makeItem(id: "story-1", type: "story", parentId: "epic-A")
        sut.setTasks([epic2, epic1, story])

        let ids = sut.availableEpicIDs
        XCTAssertEqual(ids, ["epic-A", "epic-B"], "Should be sorted and deduplicated")
    }

    func testCardsForColumnReturnsOnlyMatchingCards() throws {
        let task = try makeItem(id: "t-backlog", type: "task")
        let approved = try makeItem(id: "t-approved", type: "task", approval: "approved")
        sut.setTasks([task, approved])

        XCTAssertEqual(sut.cards(for: "backlog").count, 1)
        XCTAssertEqual(sut.cards(for: "approved").count, 1)
        XCTAssertEqual(sut.cards(for: "done").count, 0)
    }

    func testCardsForColumnRespectsActiveFilters() throws {
        let epic = try makeItem(id: "e1", type: "epic")
        let task = try makeItem(id: "t1", type: "task")
        sut.setTasks([epic, task])
        sut.typeFilter = .epic

        let backlogCards = sut.cards(for: "backlog")
        XCTAssertEqual(backlogCards.count, 1)
        XCTAssertEqual(backlogCards.first?.type, .epic)
    }

    func testEpicProgressCountsCompletedStories() throws {
        let epic = try makeItem(id: "epic-1", type: "epic")
        let storyDone = try makeItem(id: "s-done", type: "story",
                                     status: "completed", parentId: "epic-1")
        let storyPending = try makeItem(id: "s-pending", type: "story", parentId: "epic-1")
        sut.setTasks([epic, storyDone, storyPending])

        let epicCard = try XCTUnwrap(sut.allCards.first { $0.id == "epic-1" })
        let progress = try XCTUnwrap(epicCard.progress)
        XCTAssertEqual(progress.completed, 1)
        XCTAssertEqual(progress.total, 2)
        XCTAssertEqual(progress.unit, "stories")
    }

    func testTaskHasNoProgress() throws {
        let task = try makeItem(id: "t1", type: "task")
        sut.setTasks([task])

        let card = try XCTUnwrap(sut.allCards.first)
        XCTAssertNil(card.progress)
    }
}
