import XCTest
@testable import AgileMaestro

// MARK: - DetailViewModelTests

@MainActor
final class DetailViewModelTests: XCTestCase {

    // MARK: - Properties

    private var sut: DetailViewModel!

    // MARK: - Setup / Teardown

    override func setUp() async throws {
        try await super.setUp()
        sut = DetailViewModel()
    }

    override func tearDown() async throws {
        sut = nil
        try await super.tearDown()
    }

    // MARK: - Fixtures

    /// Decodes a `TaskItem` from a minimal JSON string.
    ///
    /// Supports epic, story, task, bug, and techdebt types.
    /// For story, task, bug, techdebt a `parentId` can be set.
    private func makeItem(
        id: String,
        type: String,
        subject: String? = nil,
        parentId: String? = nil
    ) throws -> TaskItem {
        let resolvedSubject = subject ?? "Subject \(id)"

        let parentField: String
        switch type {
        case "story", "task", "bug", "techdebt":
            parentField = parentId.map { "\"parent\": \"\($0)\"," } ?? ""
        default:
            parentField = ""
        }

        let json = """
        {
          "id": "\(id)",
          "subject": "\(resolvedSubject)",
          "description": "Description \(id)",
          "status": "pending",
          "blocks": [],
          "blockedBy": [],
          "metadata": {
            "type": "\(type)",
            \(parentField)
            "priority": "P2",
            "approval": "approved",
            "blocked": false
          }
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try JSONDecoder().decode(TaskItem.self, from: data)
    }

    // MARK: - Initial State

    func testInitialState() {
        XCTAssertNil(sut.selectedTask)
        XCTAssertEqual(sut.activeTab, .overview)
        XCTAssertTrue(sut.sessionTasks.isEmpty)
    }

    // MARK: - setTask: Tab Auto-Reset (SM-DETAIL-001)

    /// When the new task type does not support the current tab, activeTab resets to .overview.
    func testSetTaskResetsTabWhenNewTypeDoesNotSupportCurrentTab() throws {
        // Start with a task type that has .checklist tab (task type only)
        let taskItem = try makeItem(id: "t1", type: "task")
        sut.setTask(taskItem)
        sut.activeTab = .checklist

        // Switch to a bug — bug has only [overview, description, comments]
        let bugItem = try makeItem(id: "b1", type: "bug")
        sut.setTask(bugItem)

        XCTAssertEqual(sut.activeTab, .overview,
                       "Tab should reset to .overview when current tab is not valid for new type")
    }

    /// When the new task type still supports the current tab, activeTab is preserved.
    func testSetTaskPreservesTabWhenItRemainsValidForNewType() throws {
        // .description is available for all types
        let epic = try makeItem(id: "e1", type: "epic")
        sut.setTask(epic)
        sut.activeTab = .description

        let story = try makeItem(id: "s1", type: "story")
        sut.setTask(story)

        XCTAssertEqual(sut.activeTab, .description,
                       "Tab should be preserved when it remains valid after a type change")
    }

    /// .comments is available for all task types — switching across all types keeps it.
    func testSetTaskPreservesCommentsTabForAllTypes() throws {
        let types: [(String, String)] = [
            ("e1", "epic"),
            ("s1", "story"),
            ("t1", "task"),
            ("b1", "bug"),
            ("td1", "techdebt")
        ]
        // Build all items upfront
        let items = try types.map { id, type in try makeItem(id: id, type: type) }

        // Start from the first item with .comments selected, then switch to each subsequent type
        sut.setTask(items[0])
        sut.activeTab = .comments

        for index in 1..<items.count {
            let nextItem = items[index]
            sut.setTask(nextItem)
            XCTAssertEqual(sut.activeTab, .comments,
                           ".comments should be preserved when switching to type '\(types[index].1)'")
            // Re-select .comments so the next switch also starts from .comments
            sut.activeTab = .comments
        }
    }

    /// Switching from epic (.planning tab) to a task (.planning not available) resets tab.
    func testSetTaskResetsFromPlanningTabWhenSwitchingToTask() throws {
        let epic = try makeItem(id: "e1", type: "epic")
        sut.setTask(epic)
        sut.activeTab = .planning

        let task = try makeItem(id: "t1", type: "task")
        sut.setTask(task)

        XCTAssertEqual(sut.activeTab, .overview,
                       ".planning is not available for task — should reset to .overview")
    }

    /// When setTask is called with nil, selectedTask becomes nil and activeTab is unchanged.
    func testSetTaskWithNilClearsSelectedTaskWithoutChangingTab() throws {
        let epic = try makeItem(id: "e1", type: "epic")
        sut.setTask(epic)
        sut.activeTab = .description

        sut.setTask(nil)

        XCTAssertNil(sut.selectedTask)
        XCTAssertEqual(sut.activeTab, .description,
                       "Tab should not change when setTask is called with nil")
    }

    // MARK: - setTask: sessionTasks update

    func testSetTaskUpdatessessionTasksWhenProvided() throws {
        let item = try makeItem(id: "t1", type: "task")
        let tasks = [item]

        sut.setTask(item, tasks: tasks)

        XCTAssertEqual(sut.sessionTasks.count, 1)
        XCTAssertEqual(sut.sessionTasks.first?.id, "t1")
    }

    func testSetTaskPreservesExistingSessionTasksWhenNilPassed() throws {
        let item = try makeItem(id: "t1", type: "task")
        let item2 = try makeItem(id: "t2", type: "task")
        sut.setTask(item, tasks: [item, item2])

        // Call without tasks — existing sessionTasks should be preserved
        sut.setTask(item)

        XCTAssertEqual(sut.sessionTasks.count, 2,
                       "sessionTasks should not be cleared when tasks parameter is nil")
    }

    // MARK: - breadcrumbSegments: Parent Chain

    /// An epic with no parent returns a single segment containing itself.
    func testBreadcrumbSegmentsOrphanTaskReturnsSingleSegment() throws {
        let epic = try makeItem(id: "e1", type: "epic", subject: "Root Epic")
        sut.setTask(epic, tasks: [epic])

        let segments = sut.breadcrumbSegments(for: epic)

        XCTAssertEqual(segments.count, 1, "Orphan task should return exactly one segment")
        XCTAssertEqual(segments[0].taskItem.id, "e1")
    }

    /// Epic > Story produces two segments in root-first order.
    func testBreadcrumbSegmentsEpicStoryProducesTwoSegments() throws {
        let epic = try makeItem(id: "e1", type: "epic", subject: "My Epic")
        let story = try makeItem(id: "s1", type: "story", subject: "My Story", parentId: "e1")
        sut.setTask(story, tasks: [epic, story])

        let segments = sut.breadcrumbSegments(for: story)

        XCTAssertEqual(segments.count, 2, "Epic > Story should produce 2 segments")
        XCTAssertEqual(segments[0].taskItem.id, "e1", "First segment should be the root epic")
        XCTAssertEqual(segments[1].taskItem.id, "s1", "Second segment should be the story")
    }

    /// Epic > Story > Task produces three segments in root-first order.
    func testBreadcrumbSegmentsFullChainProducesThreeSegments() throws {
        let epic = try makeItem(id: "e1", type: "epic")
        let story = try makeItem(id: "s1", type: "story", parentId: "e1")
        let task = try makeItem(id: "t1", type: "task", parentId: "s1")
        sut.setTask(task, tasks: [epic, story, task])

        let segments = sut.breadcrumbSegments(for: task)

        XCTAssertEqual(segments.count, 3, "Epic > Story > Task chain should produce 3 segments")
        XCTAssertEqual(segments[0].taskItem.id, "e1")
        XCTAssertEqual(segments[1].taskItem.id, "s1")
        XCTAssertEqual(segments[2].taskItem.id, "t1")
    }

    /// A task whose parent is not in sessionTasks is treated as an orphan.
    func testBreadcrumbSegmentsTaskWithMissingParentReturnsSingleSegment() throws {
        // task has parentId "s-missing" but that item is not in sessionTasks
        let task = try makeItem(id: "t1", type: "task", parentId: "s-missing")
        sut.setTask(task, tasks: [task])

        let segments = sut.breadcrumbSegments(for: task)

        XCTAssertEqual(segments.count, 1,
                       "Task whose parent is not in sessionTasks should return a single segment")
        XCTAssertEqual(segments[0].taskItem.id, "t1")
    }

    // MARK: - breadcrumbSegments: Cycle Guard

    /// Two tasks pointing to each other as parents must not cause an infinite loop.
    func testBreadcrumbSegmentsCycleGuardPreventsInfiniteLoop() throws {
        // Manually build items that reference each other as parents.
        // We do this by decoding normally, then the cycle is "a -> b -> a".
        // Since parentId can't be set to the other's ID via makeItem (it's one-directional),
        // we construct both items separately with parentId set to each other.
        let jsonA = """
        {
          "id": "a",
          "subject": "Task A",
          "description": "",
          "status": "pending",
          "blocks": [],
          "blockedBy": [],
          "metadata": {
            "type": "task",
            "parent": "b",
            "priority": "P2",
            "approval": "approved",
            "blocked": false
          }
        }
        """
        let jsonB = """
        {
          "id": "b",
          "subject": "Task B",
          "description": "",
          "status": "pending",
          "blocks": [],
          "blockedBy": [],
          "metadata": {
            "type": "task",
            "parent": "a",
            "priority": "P2",
            "approval": "approved",
            "blocked": false
          }
        }
        """
        let itemA = try JSONDecoder().decode(TaskItem.self, from: XCTUnwrap(jsonA.data(using: .utf8)))
        let itemB = try JSONDecoder().decode(TaskItem.self, from: XCTUnwrap(jsonB.data(using: .utf8)))

        sut.setTask(itemA, tasks: [itemA, itemB])

        // This must return without hanging and produce a finite result.
        let segments = sut.breadcrumbSegments(for: itemA)

        XCTAssertFalse(segments.isEmpty, "Cycle guard must still produce at least one segment")
        XCTAssertLessThanOrEqual(segments.count, 2,
                                 "Cycle guard should stop traversal at the repeated node")
    }

    // MARK: - navigate(to:)

    /// navigate(to:) is an alias for setTask and should update selectedTask.
    func testNavigateToUpdatesSelectedTask() throws {
        let epic = try makeItem(id: "e1", type: "epic")
        sut.setTask(epic, tasks: [epic])

        let story = try makeItem(id: "s1", type: "story", parentId: "e1")
        sut.sessionTasks = [epic, story]
        sut.navigate(to: story)

        XCTAssertEqual(sut.selectedTask?.id, "s1",
                       "navigate(to:) should update selectedTask to the target item")
    }

    // MARK: - Selected Task Preservation Across Refresh (AM-603 AC4-5)

    /// AC4: When `setTask` is called again with the same task that is still present in the
    /// refreshed task list, `selectedTask` remains set and `activeTab` is preserved.
    ///
    /// This models the coordinator pattern: after a live-reload the coordinator checks whether
    /// the previously selected task ID still exists in the new task set, and if so re-calls
    /// `setTask` with the updated task object.
    func testSelectedTaskSurvivesRefreshWhenTaskStillExists() throws {
        let epic = try makeItem(id: "e1", type: "epic")
        let story = try makeItem(id: "s1", type: "story", parentId: "e1")

        // Set initial selection.
        sut.setTask(story, tasks: [epic, story])
        sut.activeTab = .description

        // Simulate a live reload: same tasks, same selected task still present.
        sut.setTask(story, tasks: [epic, story])

        XCTAssertEqual(sut.selectedTask?.id, "s1",
                       "selectedTask must be preserved when the task still exists after refresh")
        XCTAssertEqual(sut.activeTab, .description,
                       "activeTab must be preserved when switching to the same task type")
    }

    /// AC5: When the selected task is not found in the new task list, the coordinator calls
    /// `setTask(nil, tasks: newTasks)` and `selectedTask` becomes nil.
    ///
    /// This models the coordinator pattern: after a live-reload the coordinator finds the
    /// previously selected task ID is absent from the new set and clears the selection.
    func testSelectedTaskClearsWhenTaskDeletedFromNewData() throws {
        let epic = try makeItem(id: "e1", type: "epic")
        let story = try makeItem(id: "s1", type: "story", parentId: "e1")

        // Set initial selection on story.
        sut.setTask(story, tasks: [epic, story])
        XCTAssertEqual(sut.selectedTask?.id, "s1", "Pre-condition: story is selected")

        // Simulate reload where story no longer exists — coordinator passes nil.
        sut.setTask(nil, tasks: [epic])

        XCTAssertNil(sut.selectedTask, "selectedTask must clear when task is deleted from new data")
        XCTAssertEqual(sut.sessionTasks.count, 1,
                       "sessionTasks must be updated to the new set that excludes the deleted task")
    }

    // MARK: - DetailTab.availableTabs Matrix

    /// Verifies the full availability matrix from SM-DETAIL-001.
    func testAvailableTabsMatrix() {
        let cases: [(TaskType, Set<DetailTab>)] = [
            (.epic, [.overview, .description, .criteria, .planning, .comments]),
            (.story, [.overview, .description, .criteria, .constraints, .comments]),
            (.task, [.overview, .description, .checklist, .verification, .comments]),
            (.bug, [.overview, .description, .comments]),
            (.techdebt, [.overview, .description, .comments])
        ]
        for (type, expected) in cases {
            let available = Set(DetailTab.availableTabs(for: type))
            XCTAssertEqual(available, expected,
                           "availableTabs mismatch for type '\(type.rawValue)'")
        }
    }

    // MARK: - linkedItems(of:): Epic-Parented Bugs/TechDebt (TechDebt-2 fix)

    /// Regression test for TechDebt 2: a bug parented directly to an epic must be surfaced
    /// by `linkedItems(of:)` so the Epic Overview tab does not silently hide it.
    func testLinkedItemsIncludesEpicParentedBug() throws {
        let epic = try makeItem(id: "1", type: "epic")
        let epicBug = try makeItem(id: "80", type: "bug", parentId: "1")
        sut.setTask(epic, tasks: [epic, epicBug])

        let linked = sut.linkedItems(of: epic)

        XCTAssertEqual(linked.map(\.id), ["80"], "Epic-parented bug is surfaced as a linked item")
    }

    /// Regression test for TechDebt 2: a techdebt item parented directly to an epic must be
    /// surfaced by `linkedItems(of:)`.
    func testLinkedItemsIncludesEpicParentedTechDebt() throws {
        let epic = try makeItem(id: "1", type: "epic")
        let epicTechDebt = try makeItem(id: "90", type: "techdebt", parentId: "1")
        sut.setTask(epic, tasks: [epic, epicTechDebt])

        let linked = sut.linkedItems(of: epic)

        XCTAssertEqual(linked.map(\.id), ["90"], "Epic-parented techdebt is surfaced as a linked item")
    }

    /// Regression test for TechDebt 2: bugs/techdebt parented to a child STORY (not the epic
    /// itself) must NOT appear in `linkedItems(of:)` — they belong to the story's task table.
    func testLinkedItemsExcludesStoryParentedItems() throws {
        let epic = try makeItem(id: "1", type: "epic")
        let story = try makeItem(id: "10", type: "story", parentId: "1")
        let storyBug = try makeItem(id: "50", type: "bug", parentId: "10")
        sut.setTask(epic, tasks: [epic, story, storyBug])

        let linked = sut.linkedItems(of: epic)

        XCTAssertTrue(linked.isEmpty, "Story-parented bug must not appear as an epic-linked item")
    }

    /// Regression test for TechDebt 2: `linkedItems(of:)` must not include child stories or
    /// their descendant tasks — only bug/techdebt items parented directly to the epic.
    func testLinkedItemsExcludesStoriesAndTasks() throws {
        let epic = try makeItem(id: "1", type: "epic")
        let story = try makeItem(id: "10", type: "story", parentId: "1")
        let epicTask = try makeItem(id: "20", type: "task", parentId: "1")
        let epicBug = try makeItem(id: "80", type: "bug", parentId: "1")
        sut.setTask(epic, tasks: [epic, story, epicTask, epicBug])

        let linked = sut.linkedItems(of: epic)

        XCTAssertEqual(linked.map(\.id), ["80"],
                       "Only the epic-parented bug qualifies — story and task types are excluded")
    }

    /// An epic with no directly-parented bug/techdebt returns an empty array.
    func testLinkedItemsEmptyWhenNoneParentedToEpic() throws {
        let epic = try makeItem(id: "1", type: "epic")
        let story = try makeItem(id: "10", type: "story", parentId: "1")
        sut.setTask(epic, tasks: [epic, story])

        XCTAssertTrue(sut.linkedItems(of: epic).isEmpty)
    }
}
