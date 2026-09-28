// swiftlint:disable file_length
import XCTest
@testable import AgileMaestro

// MARK: - TreeViewModelTests

@MainActor
// swiftlint:disable:next type_body_length
final class TreeViewModelTests: XCTestCase {

    // MARK: - Properties

    private var sut: TreeViewModel!

    // MARK: - Setup / Teardown

    override func setUp() async throws {
        try await super.setUp()
        sut = TreeViewModel()
    }

    override func tearDown() async throws {
        sut = nil
        // Remove any UserDefaults keys written by expand-state persistence tests.
        UserDefaults.standard.removeObject(forKey: "expandedNodes_test-session")
        UserDefaults.standard.removeObject(forKey: "expandedNodes_session-A")
        UserDefaults.standard.removeObject(forKey: "expandedNodes_session-B")
        UserDefaults.standard.removeObject(forKey: "expandedNodes_snap-session")
        try await super.tearDown()
    }

    // MARK: - Fixtures

    /// Decodes a `TaskItem` from a minimal JSON string using the `"parent"` key format.
    ///
    /// This format is used by older JSON or manual test data. In real Claude Tasks CLI
    /// files the parent is expressed via display-ID keys (`epic_id`, `story_id`).
    private func makeItem(
        id: String,
        type: String,
        status: String = "pending",
        parentId: String? = nil
    ) throws -> TaskItem {
        let parentField: String
        switch type {
        case "story":
            parentField = parentId.map { "\"parent\": \"\($0)\"," } ?? ""
        case "task", "bug", "techdebt":
            parentField = parentId.map { "\"parent\": \"\($0)\"," } ?? ""
        default:
            parentField = ""
        }

        let json = """
        {
          "id": "\(id)",
          "subject": "Subject \(id)",
          "description": "Description \(id)",
          "status": "\(status)",
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

    /// Decodes a `TaskItem` that uses display-ID parent references (`epic_id` / `story_id`),
    /// matching the format produced by the real Claude Tasks CLI.
    ///
    /// - Parameters:
    ///   - id: The internal numeric task ID (e.g. "123").
    ///   - type: The task type string ("epic", "story", "task", "bug", "techdebt").
    ///   - displayId: The display identifier (e.g. "AM-500", "AM-501-1").
    ///   - parentDisplayId: The display identifier of the parent item (e.g. "AM-500").
    private func makeItemDisplayIdFormat(
        id: String,
        type: String,
        displayId: String? = nil,
        status: String = "pending",
        parentDisplayId: String? = nil
    ) throws -> TaskItem {
        // Build the display-ID and parent fields based on type.
        var extraFields = ""
        if let displayId {
            switch type {
            case "epic":
                extraFields += "\"id\": \"\(displayId)\","
            case "story":
                extraFields += "\"story_id\": \"\(displayId)\","
            default:
                extraFields += "\"task_id\": \"\(displayId)\","
            }
        }
        if let parentDisplayId {
            switch type {
            case "story":
                extraFields += "\"epic_id\": \"\(parentDisplayId)\","
            case "task", "bug", "techdebt":
                extraFields += "\"story_id\": \"\(parentDisplayId)\","
            default:
                break
            }
        }

        let json = """
        {
          "id": "\(id)",
          "subject": "Subject \(id)",
          "description": "Description \(id)",
          "status": "\(status)",
          "blocks": [],
          "blockedBy": [],
          "metadata": {
            "type": "\(type)",
            \(extraFields)
            "priority": "P2",
            "approval": "approved",
            "blocked": false
          }
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try JSONDecoder().decode(TaskItem.self, from: data)
    }

    // MARK: - buildTree: Hierarchy

    func testBuildTreeCreatesCorrectEpicStoryTaskHierarchy() throws {
        let epic = try makeItem(id: "1", type: "epic")
        let story = try makeItem(id: "10", type: "story", parentId: "1")
        let task = try makeItem(id: "100", type: "task", parentId: "10")

        sut.buildTree(from: [epic, story, task])

        XCTAssertEqual(sut.rootNodes.count, 1, "One epic becomes one root node")
        let epicNode = sut.rootNodes[0]
        XCTAssertEqual(epicNode.id, "1")
        XCTAssertEqual(epicNode.children.count, 1, "Epic has one story child")

        let storyNode = epicNode.children[0]
        XCTAssertEqual(storyNode.id, "10")
        XCTAssertEqual(storyNode.children.count, 1, "Story has one task child")
        XCTAssertEqual(storyNode.children[0].id, "100")
    }

    func testBuildTreeWithMultipleEpicsAndStories() throws {
        let epic1 = try makeItem(id: "1", type: "epic")
        let epic2 = try makeItem(id: "2", type: "epic")
        let story1 = try makeItem(id: "10", type: "story", parentId: "1")
        let story2 = try makeItem(id: "11", type: "story", parentId: "2")
        let task1 = try makeItem(id: "100", type: "task", parentId: "10")
        let task2 = try makeItem(id: "101", type: "task", parentId: "11")

        sut.buildTree(from: [epic1, epic2, story1, story2, task1, task2])

        XCTAssertEqual(sut.rootNodes.count, 2)
        XCTAssertEqual(sut.rootNodes[0].children.count, 1)
        XCTAssertEqual(sut.rootNodes[1].children.count, 1)
    }

    func testBuildTreeWithEmptyInputProducesEmptyState() {
        sut.buildTree(from: [])

        XCTAssertTrue(sut.rootNodes.isEmpty)
        XCTAssertTrue(sut.orphanBugNodes.isEmpty)
        XCTAssertTrue(sut.orphanTechDebtNodes.isEmpty)
    }

    // MARK: - buildTree: Orphan Separation

    func testBuildTreeSeparatesOrphanBugsFromRootNodes() throws {
        let epic = try makeItem(id: "1", type: "epic")
        // Bug with a non-existent parent -> orphan
        let orphanBug = try makeItem(id: "99", type: "bug", parentId: "9999")

        sut.buildTree(from: [epic, orphanBug])

        XCTAssertEqual(sut.rootNodes.count, 1, "Only epic appears in rootNodes")
        XCTAssertEqual(sut.orphanBugNodes.count, 1, "Orphan bug appears in orphanBugNodes")
        XCTAssertEqual(sut.orphanBugNodes[0].id, "99")
    }

    func testBuildTreeSeparatesOrphanTechDebtFromRootNodes() throws {
        let epic = try makeItem(id: "1", type: "epic")
        // TechDebt with a non-existent parent -> orphan
        let orphanTD = try makeItem(id: "88", type: "techdebt", parentId: "9999")

        sut.buildTree(from: [epic, orphanTD])

        XCTAssertEqual(sut.rootNodes.count, 1, "Only epic appears in rootNodes")
        XCTAssertEqual(sut.orphanTechDebtNodes.count, 1, "Orphan techdebt appears in orphanTechDebtNodes")
        XCTAssertEqual(sut.orphanTechDebtNodes[0].id, "88")
    }

    func testBuildTreeBugWithValidParentIsNotOrphan() throws {
        let epic = try makeItem(id: "1", type: "epic")
        let story = try makeItem(id: "10", type: "story", parentId: "1")
        // Bug whose parent is a known story -> should NOT appear in orphanBugNodes
        let bug = try makeItem(id: "50", type: "bug", parentId: "10")

        sut.buildTree(from: [epic, story, bug])

        XCTAssertTrue(sut.orphanBugNodes.isEmpty, "Bug with a known story parent is not orphaned")
    }

    func testBuildTreeBugWithNoParentIsOrphan() throws {
        let bug = try makeItem(id: "50", type: "bug")

        sut.buildTree(from: [bug])

        XCTAssertEqual(sut.orphanBugNodes.count, 1)
        XCTAssertTrue(sut.rootNodes.isEmpty)
    }

    /// Regression test for BLOCKER 1: bugs/techdebt with a valid story parent must
    /// appear as story children, not as orphans.
    func testBugAndTechDebtWithValidStoryParentAreNotOrphans() throws {
        let epic = try makeItem(id: "1", type: "epic")
        let story = try makeItem(id: "10", type: "story", parentId: "1")
        let bug = try makeItem(id: "50", type: "bug", parentId: "10")
        let td = try makeItem(id: "60", type: "techdebt", parentId: "10")

        sut.buildTree(from: [epic, story, bug, td])

        // Neither bug nor techdebt should appear as orphans
        XCTAssertTrue(sut.orphanBugNodes.isEmpty, "Bug with a known story parent is not orphaned")
        XCTAssertTrue(sut.orphanTechDebtNodes.isEmpty, "TechDebt with a known story parent is not orphaned")

        // Both should appear as children of the story node
        let storyNode = sut.rootNodes[0].children[0]
        XCTAssertEqual(storyNode.id, "10")
        XCTAssertEqual(storyNode.children.count, 2, "Bug and techdebt are story children")
        let childIDs = Set(storyNode.children.map(\.id))
        XCTAssertTrue(childIDs.contains("50"), "Bug appears under story")
        XCTAssertTrue(childIDs.contains("60"), "TechDebt appears under story")
    }

    // MARK: - buildTree: Epic-Parented Bugs/TechDebt (Bug 1 fix)

    /// Regression test for Bug 1: a bug whose parent is an epic (not a story) must
    /// appear as a child of that epic, after the epic's story children, and must
    /// NOT appear in orphanBugNodes.
    func testEpicParentedBugAppearsUnderEpicAfterStoryChildren() throws {
        let epic = try makeItem(id: "1", type: "epic")
        let story = try makeItem(id: "10", type: "story", parentId: "1")
        let epicBug = try makeItem(id: "80", type: "bug", parentId: "1")

        sut.buildTree(from: [epic, story, epicBug])

        let epicNode = sut.rootNodes[0]
        XCTAssertEqual(epicNode.children.count, 2, "Epic has both the story and the epic-parented bug as children")
        XCTAssertEqual(epicNode.children[0].id, "10", "Story children come first")
        XCTAssertEqual(epicNode.children[1].id, "80", "Epic-parented bug is appended after story children")
        XCTAssertTrue(sut.orphanBugNodes.isEmpty, "Epic-parented bug must not appear in the orphan list")
    }

    /// Regression test for Bug 1: a techdebt item whose parent is an epic must
    /// appear as a child of that epic, after the epic's story children, and must
    /// NOT appear in orphanTechDebtNodes.
    func testEpicParentedTechDebtAppearsUnderEpicAfterStoryChildren() throws {
        let epic = try makeItem(id: "1", type: "epic")
        let story = try makeItem(id: "10", type: "story", parentId: "1")
        let epicTechDebt = try makeItem(id: "90", type: "techdebt", parentId: "1")

        sut.buildTree(from: [epic, story, epicTechDebt])

        let epicNode = sut.rootNodes[0]
        XCTAssertEqual(
            epicNode.children.count, 2, "Epic has both the story and the epic-parented techdebt as children")
        XCTAssertEqual(epicNode.children[0].id, "10", "Story children come first")
        XCTAssertEqual(epicNode.children[1].id, "90", "Epic-parented techdebt is appended after story children")
        XCTAssertTrue(sut.orphanTechDebtNodes.isEmpty, "Epic-parented techdebt must not appear in the orphan list")
    }

    /// Regression test for Bug 1: an epic with ONLY bug/techdebt children (no stories)
    /// still attaches both directly as epic children instead of dropping them.
    func testEpicWithOnlyBugAndTechDebtChildrenAttachesBoth() throws {
        let epic = try makeItem(id: "1", type: "epic")
        let epicBug = try makeItem(id: "80", type: "bug", parentId: "1")
        let epicTechDebt = try makeItem(id: "90", type: "techdebt", parentId: "1")

        sut.buildTree(from: [epic, epicBug, epicTechDebt])

        let epicNode = sut.rootNodes[0]
        XCTAssertEqual(epicNode.children.count, 2, "Epic attaches both epic-parented leaves as children")
        let childIDs = Set(epicNode.children.map(\.id))
        XCTAssertTrue(childIDs.contains("80"), "Epic-parented bug attaches directly to the epic")
        XCTAssertTrue(childIDs.contains("90"), "Epic-parented techdebt attaches directly to the epic")
        XCTAssertTrue(sut.orphanBugNodes.isEmpty, "Epic-parented bug is not orphaned")
        XCTAssertTrue(sut.orphanTechDebtNodes.isEmpty, "Epic-parented techdebt is not orphaned")
    }

    /// Regression test for Bug 1: story-parented and parentless bug/techdebt items are
    /// unaffected by the epic-attach fix — they keep their pre-fix placement.
    func testStoryParentedAndParentlessItemsUnchangedByEpicAttachFix() throws {
        let epic = try makeItem(id: "1", type: "epic")
        let story = try makeItem(id: "10", type: "story", parentId: "1")
        let storyBug = try makeItem(id: "50", type: "bug", parentId: "10")
        let parentlessTechDebt = try makeItem(id: "88", type: "techdebt")

        sut.buildTree(from: [epic, story, storyBug, parentlessTechDebt])

        let epicNode = sut.rootNodes[0]
        XCTAssertEqual(
            epicNode.children.count, 1, "Epic has only its story child — the bug attaches to the story, not the epic")
        let storyNode = epicNode.children[0]
        XCTAssertEqual(storyNode.children.count, 1, "Story keeps its story-parented bug child")
        XCTAssertEqual(storyNode.children[0].id, "50", "Story-parented bug still attaches to its story")
        XCTAssertEqual(sut.orphanTechDebtNodes.count, 1, "Parentless techdebt is still orphaned")
        XCTAssertEqual(sut.orphanTechDebtNodes[0].id, "88")
    }

    /// Regression test for the CodeRabbit perf fix (task-1): epic-linked leaves are
    /// grouped by resolved parent ID once, up front, instead of being resolved
    /// per-epic. Verifies the grouping is correct — each epic receives ONLY its own
    /// leaves, never a sibling epic's — across multiple epics with interleaved
    /// bug/techdebt parentage.
    func testMultipleEpicsEachReceiveOnlyTheirOwnEpicParentedLeaves() throws {
        let epic1 = try makeItem(id: "1", type: "epic")
        let epic2 = try makeItem(id: "2", type: "epic")
        let epic1Bug = try makeItem(id: "80", type: "bug", parentId: "1")
        let epic1TechDebt = try makeItem(id: "81", type: "techdebt", parentId: "1")
        let epic2Bug = try makeItem(id: "90", type: "bug", parentId: "2")

        sut.buildTree(from: [epic1, epic2, epic1Bug, epic1TechDebt, epic2Bug])

        XCTAssertEqual(sut.rootNodes.count, 2)
        let epic1Node = try XCTUnwrap(sut.rootNodes.first { $0.id == "1" })
        let epic2Node = try XCTUnwrap(sut.rootNodes.first { $0.id == "2" })

        XCTAssertEqual(epic1Node.children.map(\.id), ["80", "81"], "Epic 1 gets only its own leaves, in order")
        XCTAssertEqual(epic2Node.children.map(\.id), ["90"], "Epic 2 gets only its own leaf")
        XCTAssertTrue(sut.orphanBugNodes.isEmpty)
        XCTAssertTrue(sut.orphanTechDebtNodes.isEmpty)
    }

    // MARK: - buildTree: Task Count

    func testTaskCountExcludesEpicsAndStories() throws {
        let epic = try makeItem(id: "1", type: "epic")
        let story = try makeItem(id: "10", type: "story", parentId: "1")
        let task = try makeItem(id: "100", type: "task", parentId: "10")
        let bug = try makeItem(id: "99", type: "bug")
        let td = try makeItem(id: "88", type: "techdebt")

        sut.buildTree(from: [epic, story, task, bug, td])

        // taskCount counts only leaf work items (.task, .bug, .techdebt), not epics/stories
        XCTAssertEqual(sut.taskCount, 3)
    }

    func testCompletedTaskCountMatchesCompletedLeafItems() throws {
        let epic = try makeItem(id: "1", type: "epic")
        let completedTask = try makeItem(id: "100", type: "task", status: "completed", parentId: "1")
        let pendingTask = try makeItem(id: "101", type: "task", status: "pending", parentId: "1")

        sut.buildTree(from: [epic, completedTask, pendingTask])

        // completedTaskCount counts only completed leaf items; epic is excluded from total
        XCTAssertEqual(sut.completedTaskCount, 1)
        XCTAssertEqual(sut.taskCountText, "1/2")
    }

    // MARK: - selectNode / clearSelection

    func testSelectNodeUpdatesSelectedNodeIDAndTask() throws {
        let epic = try makeItem(id: "1", type: "epic")
        sut.buildTree(from: [epic])

        let node = sut.rootNodes[0]
        sut.selectNode(node)

        XCTAssertEqual(sut.selectedNodeID, "1")
        XCTAssertEqual(sut.selectedTask, epic)
    }

    func testClearSelectionNilsSelection() throws {
        let epic = try makeItem(id: "1", type: "epic")
        sut.buildTree(from: [epic])

        sut.selectNode(sut.rootNodes[0])
        XCTAssertNotNil(sut.selectedNodeID)

        sut.clearSelection()

        XCTAssertNil(sut.selectedNodeID)
        XCTAssertNil(sut.selectedTask)
    }

    func testInitialSelectionIsNil() {
        XCTAssertNil(sut.selectedNodeID)
        XCTAssertNil(sut.selectedTask)
    }

    // MARK: - buildTree: Stale Selection Clearing (Bug 104)

    /// Regression test for Bug 104: when the task list is replaced with an empty set
    /// after a selection was made, the selection must be cleared so the detail panel
    /// shows the placeholder view instead of stale data.
    func testBuildTreeClearsSelectionWhenSelectedTaskIsRemovedFromTaskSet() throws {
        let epic = try makeItem(id: "1", type: "epic")
        sut.buildTree(from: [epic])
        sut.selectNode(sut.rootNodes[0])

        // Before the fix, selectedTask would remain after rebuilding with an empty set.
        XCTAssertNotNil(sut.selectedTask, "Pre-condition: a task is selected")

        sut.buildTree(from: [])

        XCTAssertNil(sut.selectedNodeID, "selectedNodeID must be nil after navigating to empty directory")
        XCTAssertNil(sut.selectedTask, "selectedTask must be nil after navigating to empty directory")
    }

    /// When a directory switch loads a completely different task set, the previously
    /// selected task (absent from the new set) must be deselected.
    func testBuildTreeClearsSelectionWhenSelectedTaskNotInNewSet() throws {
        let epic1 = try makeItem(id: "1", type: "epic")
        let epic2 = try makeItem(id: "2", type: "epic")

        // Select epic1 from the first session.
        sut.buildTree(from: [epic1])
        sut.selectNode(sut.rootNodes[0])
        XCTAssertEqual(sut.selectedTask?.id, "1", "Pre-condition: epic1 is selected")

        // Switch to a different session containing only epic2.
        sut.buildTree(from: [epic2])

        XCTAssertNil(sut.selectedNodeID, "Selection must clear when selected task is absent from new set")
        XCTAssertNil(sut.selectedTask, "selectedTask must clear when selected task is absent from new set")
    }

    /// When a rebuild includes the currently selected task, the selection must be preserved.
    func testBuildTreePreservesSelectionWhenSelectedTaskRemainsInNewSet() throws {
        let epic = try makeItem(id: "1", type: "epic")
        let story = try makeItem(id: "10", type: "story", parentId: "1")

        sut.buildTree(from: [epic])
        sut.selectNode(sut.rootNodes[0])
        XCTAssertEqual(sut.selectedTask?.id, "1", "Pre-condition: epic is selected")

        // Rebuild with the same epic plus a new story — selection should be preserved.
        sut.buildTree(from: [epic, story])

        XCTAssertEqual(sut.selectedNodeID, "1", "Selection must be preserved when task is still in the new set")
        XCTAssertEqual(sut.selectedTask?.id, "1", "selectedTask must be preserved when task is still in the new set")
    }

    // MARK: - toggleExpand

    func testToggleExpandChangesNodeExpandState() throws {
        let epic = try makeItem(id: "1", type: "epic")
        sut.buildTree(from: [epic])

        let node = sut.rootNodes[0]
        XCTAssertFalse(node.isExpanded, "Node starts collapsed")

        sut.toggleExpand(node: node)
        XCTAssertTrue(node.isExpanded)

        sut.toggleExpand(node: node)
        XCTAssertFalse(node.isExpanded)
    }

    // MARK: - Expand State Persistence (AC4)

    func testExpandedStatePersistedAndRestoredOnRebuild() throws {
        let epic = try makeItem(id: "1", type: "epic")
        let story = try makeItem(id: "10", type: "story", parentId: "1")

        // Build the tree with a session ID and expand the epic node.
        sut.buildTree(from: [epic, story], sessionID: "test-session")
        let epicNode = sut.rootNodes[0]
        sut.toggleExpand(node: epicNode)
        XCTAssertTrue(epicNode.isExpanded)

        // Rebuild the tree (simulating a file-watcher refresh).
        sut.buildTree(from: [epic, story], sessionID: "test-session")

        // Expand state should be restored from UserDefaults.
        let restoredEpicNode = sut.rootNodes[0]
        XCTAssertTrue(restoredEpicNode.isExpanded, "Epic node should remain expanded after rebuild")
    }

    func testExpandStateIsIsolatedToSessionID() throws {
        let epic = try makeItem(id: "1", type: "epic")

        // Expand in session A.
        sut.buildTree(from: [epic], sessionID: "session-A")
        sut.toggleExpand(node: sut.rootNodes[0])

        // Build with a different session ID.
        sut.buildTree(from: [epic], sessionID: "session-B")
        XCTAssertFalse(sut.rootNodes[0].isExpanded, "Different session should not inherit expand state")
    }

    func testEmptySessionIDDoesNotLoadExpandState() throws {
        let epic = try makeItem(id: "1", type: "epic")
        // Build with no session ID — expand state should NOT be loaded.
        sut.buildTree(from: [epic], sessionID: "")
        XCTAssertFalse(sut.rootNodes[0].isExpanded, "No session ID means no persisted state to load")
    }

    // MARK: - Snapshot / Restore Expanded IDs

    func testSnapshotExpandedIDsCapturesExpandedNodes() throws {
        let epic = try makeItem(id: "1", type: "epic")
        let story = try makeItem(id: "10", type: "story", parentId: "1")
        sut.buildTree(from: [epic, story], sessionID: "snap-session")

        // Expand epic and story nodes.
        sut.toggleExpand(node: sut.rootNodes[0])
        let storyNode = sut.rootNodes[0].children[0]
        sut.toggleExpand(node: storyNode)

        let snapshot = sut.snapshotExpandedIDs()
        XCTAssertTrue(snapshot.contains("1"), "Epic ID must be in snapshot")
        XCTAssertTrue(snapshot.contains("10"), "Story ID must be in snapshot")
    }

    func testSnapshotReturnsEmptySetWhenNothingExpanded() throws {
        let epic = try makeItem(id: "1", type: "epic")
        sut.buildTree(from: [epic])
        // No nodes expanded by default.
        XCTAssertTrue(sut.snapshotExpandedIDs().isEmpty)
    }

    func testRestoreExpandedIDsReexpandsMatchingNodes() throws {
        let epic = try makeItem(id: "1", type: "epic")
        let story = try makeItem(id: "10", type: "story", parentId: "1")
        sut.buildTree(from: [epic, story])

        // Expand, then rebuild (simulating live reload).
        let epicNode = sut.rootNodes[0]
        sut.toggleExpand(node: epicNode)
        let snapshot = sut.snapshotExpandedIDs()

        // Rebuild tree — nodes are new objects, start collapsed.
        sut.buildTree(from: [epic, story])
        XCTAssertFalse(sut.rootNodes[0].isExpanded, "Node collapsed after rebuild")

        // Restore and verify.
        sut.restoreExpandedIDs(snapshot)
        XCTAssertTrue(sut.rootNodes[0].isExpanded, "Epic must be re-expanded after restore")
    }

    func testRestoreSkipsNodesThatDisappearedFromTree() throws {
        let epic1 = try makeItem(id: "1", type: "epic")
        let epic2 = try makeItem(id: "2", type: "epic")
        sut.buildTree(from: [epic1, epic2])

        // Expand both, then rebuild with only epic1 remaining.
        sut.toggleExpand(node: sut.rootNodes[0])
        sut.toggleExpand(node: sut.rootNodes[1])
        let snapshot = sut.snapshotExpandedIDs()
        XCTAssertEqual(snapshot.count, 2)

        sut.buildTree(from: [epic1])
        sut.restoreExpandedIDs(snapshot)

        // epic1 exists and must be expanded; epic2 is gone — no crash.
        XCTAssertEqual(sut.rootNodes.count, 1)
        XCTAssertTrue(sut.rootNodes[0].isExpanded, "Surviving epic must be re-expanded")
    }

    func testRestoreExpandedIDsWithEmptySetIsNoOp() throws {
        let epic = try makeItem(id: "1", type: "epic")
        sut.buildTree(from: [epic])
        // Calling restore with empty set must not expand anything.
        sut.restoreExpandedIDs([])
        XCTAssertFalse(sut.rootNodes[0].isExpanded)
    }

    func testRestoreExpandedIDsRestoresOrphanBugNodes() throws {
        let bug = try makeItem(id: "99", type: "bug")
        sut.buildTree(from: [bug])

        // Snapshot with the bug present (orphan bugs are leaf nodes — not normally expanded,
        // but we test that restoreExpandedIDs covers the orphan arrays too).
        // Manually set expanded to simulate a prior state.
        sut.orphanBugNodes[0].isExpanded = true
        let snapshot = sut.snapshotExpandedIDs()
        XCTAssertTrue(snapshot.contains("99"))

        // Rebuild and restore.
        sut.buildTree(from: [bug])
        XCTAssertFalse(sut.orphanBugNodes[0].isExpanded)
        sut.restoreExpandedIDs(snapshot)
        XCTAssertTrue(sut.orphanBugNodes[0].isExpanded, "Orphan bug node must be re-expanded")
    }

    // MARK: - Snapshot / Restore: AM-603 Acceptance Criteria

    /// AC1: Expanded nodes survive a live reload cycle (snapshot before rebuild → restore after).
    ///
    /// Simulates the FileWatcher reload pattern: caller snapshots expanded IDs, calls buildTree
    /// with refreshed data, then restores the snapshot. The user's open/close choices must survive.
    func testExpandedNodesSurviveFullSnapshotRebuildRestoreCycle() throws {
        let epic = try makeItem(id: "1", type: "epic")
        let story = try makeItem(id: "10", type: "story", parentId: "1")
        let task = try makeItem(id: "100", type: "task", parentId: "10")
        sut.buildTree(from: [epic, story, task])

        // Expand epic and story.
        sut.toggleExpand(node: sut.rootNodes[0])
        let storyNode = sut.rootNodes[0].children[0]
        sut.toggleExpand(node: storyNode)

        XCTAssertTrue(sut.rootNodes[0].isExpanded, "Pre-condition: epic expanded")
        XCTAssertTrue(sut.rootNodes[0].children[0].isExpanded, "Pre-condition: story expanded")

        // Full reload cycle: snapshot → rebuild → restore.
        let snapshot = sut.snapshotExpandedIDs()
        sut.buildTree(from: [epic, story, task])
        sut.restoreExpandedIDs(snapshot)

        XCTAssertTrue(sut.rootNodes[0].isExpanded, "Epic must remain expanded after reload cycle")
        XCTAssertTrue(sut.rootNodes[0].children[0].isExpanded, "Story must remain expanded after reload cycle")
    }

    /// AC2: Expanded IDs for items removed from the new task set are silently dropped.
    ///
    /// After rebuild the snapshot may contain IDs that no longer exist. restoreExpandedIDs
    /// must skip those IDs gracefully without crashing or expanding wrong nodes.
    func testExpandedIDsForRemovedNodesAreDroppedGracefully() throws {
        let epic1 = try makeItem(id: "1", type: "epic")
        let epic2 = try makeItem(id: "2", type: "epic")
        sut.buildTree(from: [epic1, epic2])

        sut.toggleExpand(node: sut.rootNodes[0])
        sut.toggleExpand(node: sut.rootNodes[1])
        let snapshot = sut.snapshotExpandedIDs()
        XCTAssertEqual(snapshot, ["1", "2"], "Pre-condition: both IDs captured")

        // Rebuild with epic2 removed.
        sut.buildTree(from: [epic1])
        // Must not crash.
        sut.restoreExpandedIDs(snapshot)

        XCTAssertEqual(sut.rootNodes.count, 1, "Only epic1 remains")
        XCTAssertTrue(sut.rootNodes[0].isExpanded, "Surviving epic1 must be re-expanded")
        // epic2 is gone — no assertion needed, only verifying absence of crash.
    }

    /// AC3: New nodes introduced during a rebuild default to collapsed.
    ///
    /// When a reload brings in a brand-new epic or story not present in the prior snapshot,
    /// that node must start collapsed (the snapshot contains no entry for it).
    func testNewNodeIntroducedDuringRebuildDefaultsToCollapsed() throws {
        let epic1 = try makeItem(id: "1", type: "epic")
        sut.buildTree(from: [epic1])

        // Expand epic1 and snapshot.
        sut.toggleExpand(node: sut.rootNodes[0])
        let snapshot = sut.snapshotExpandedIDs()

        // Rebuild adding a brand-new epic2.
        let epic2 = try makeItem(id: "2", type: "epic")
        sut.buildTree(from: [epic1, epic2])
        sut.restoreExpandedIDs(snapshot)

        // epic1 must be re-expanded; epic2 (new) must be collapsed.
        let node1 = sut.rootNodes.first(where: { $0.id == "1" })
        let node2 = sut.rootNodes.first(where: { $0.id == "2" })
        XCTAssertTrue(node1?.isExpanded == true, "epic1 must remain expanded from snapshot")
        XCTAssertFalse(node2?.isExpanded == true, "New epic2 must default to collapsed")
    }

    // MARK: - Orphan Section Toggles

    func testToggleBugSectionFlipsExpansion() {
        XCTAssertTrue(sut.isBugSectionExpanded, "Starts expanded")
        sut.toggleBugSection()
        XCTAssertFalse(sut.isBugSectionExpanded)
        sut.toggleBugSection()
        XCTAssertTrue(sut.isBugSectionExpanded)
    }

    func testToggleTechDebtSectionFlipsExpansion() {
        XCTAssertTrue(sut.isTechDebtSectionExpanded, "Starts expanded")
        sut.toggleTechDebtSection()
        XCTAssertFalse(sut.isTechDebtSectionExpanded)
        sut.toggleTechDebtSection()
        XCTAssertTrue(sut.isTechDebtSectionExpanded)
    }

    // MARK: - setClaudeTasks / orphanedTasks

    /// Helper that creates a minimal `ClaudeTask` for testing.
    private func makeClaudeTask(
        id: String,
        subject: String = "",
        blockedBy: [String] = []
    ) -> ClaudeTask {
        ClaudeTask(
            id: id,
            subject: subject.isEmpty ? "Task \(id)" : subject,
            description: nil,
            status: nil,
            blocks: [],
            blockedBy: blockedBy,
            rawFields: [:]
        )
    }

    /// Helper that creates a minimal `OrphanedTask` for testing.
    private func makeOrphanedTask(filename: String) -> OrphanedTask {
        OrphanedTask(filename: filename, errorMessage: "parse error", partialFields: [:], rawJSON: "")
    }

    func testSetClaudeTasksStoresPassedValues() {
        let t1 = makeClaudeTask(id: "1")
        let t2 = makeClaudeTask(id: "2")

        sut.setClaudeTasks([t1, t2], orphanedTasks: [])

        XCTAssertEqual(sut.claudeTasks.count, 2)
        XCTAssertTrue(sut.orphanedTasks.isEmpty)
    }

    func testSetOrphanedTasksStoresPassedValues() {
        let o1 = makeOrphanedTask(filename: "broken.json")
        let o2 = makeOrphanedTask(filename: "corrupt.json")

        sut.setClaudeTasks([], orphanedTasks: [o1, o2])

        XCTAssertTrue(sut.claudeTasks.isEmpty)
        XCTAssertEqual(sut.orphanedTasks.count, 2)
        XCTAssertEqual(sut.orphanedTasks[0].filename, "broken.json")
        XCTAssertEqual(sut.orphanedTasks[1].filename, "corrupt.json")
    }

    func testInitialClaudeTasksAndOrphanedTasksAreEmpty() {
        XCTAssertTrue(sut.claudeTasks.isEmpty)
        XCTAssertTrue(sut.orphanedTasks.isEmpty)
    }

    func testSetClaudeTasksAppliesTopologicalSort() {
        // t2 blockedBy t1 — so t1 must appear before t2 in the output.
        let t1 = makeClaudeTask(id: "1")
        let t2 = makeClaudeTask(id: "2", blockedBy: ["1"])

        // Pass in reverse order to verify sorting is applied.
        sut.setClaudeTasks([t2, t1], orphanedTasks: [])

        let ids = sut.claudeTasks.map(\.id)
        guard let t1Idx = ids.firstIndex(of: "1"),
              let t2Idx = ids.firstIndex(of: "2") else {
            XCTFail("Both task IDs must be present in claudeTasks")
            return
        }
        XCTAssertLessThan(t1Idx, t2Idx, "Blocker (t1) must precede dependent (t2) after sort")
    }

    func testSetClaudeTasksWithEmptyArrayClearsCollection() {
        let t1 = makeClaudeTask(id: "1")
        sut.setClaudeTasks([t1], orphanedTasks: [])
        XCTAssertEqual(sut.claudeTasks.count, 1, "Pre-condition: one task set")

        sut.setClaudeTasks([], orphanedTasks: [])

        XCTAssertTrue(sut.claudeTasks.isEmpty, "Setting empty array clears claudeTasks")
    }

    func testSetClaudeTasksReplacesExistingCollection() {
        let t1 = makeClaudeTask(id: "1")
        sut.setClaudeTasks([t1], orphanedTasks: [])

        let t2 = makeClaudeTask(id: "2")
        let t3 = makeClaudeTask(id: "3")
        sut.setClaudeTasks([t2, t3], orphanedTasks: [])

        XCTAssertEqual(sut.claudeTasks.count, 2)
        XCTAssertFalse(sut.claudeTasks.contains(where: { $0.id == "1" }), "Old tasks must be replaced")
        XCTAssertTrue(sut.claudeTasks.contains(where: { $0.id == "2" }))
        XCTAssertTrue(sut.claudeTasks.contains(where: { $0.id == "3" }))
    }

    // MARK: - Display-ID Parent Resolution (Bug 153 regression)

    /// Regression test for Bug 153: Claude Tasks CLI writes `epic_id`/`story_id` display-ID
    /// keys instead of a `"parent"` key. `buildTree` must still build the correct hierarchy.
    func testBuildTreeWithDisplayIdParentBuildsCorrectHierarchy() throws {
        // Epic has a display-ID "AM-500" in its metadata.
        let epic = try makeItemDisplayIdFormat(id: "100", type: "epic", displayId: "AM-500")
        // Story references the epic via "epic_id": "AM-500" — no "parent" key.
        let story = try makeItemDisplayIdFormat(
            id: "101", type: "story", displayId: "AM-501", parentDisplayId: "AM-500"
        )
        // Task references the story via "story_id": "AM-501" — no "parent" key.
        let task = try makeItemDisplayIdFormat(
            id: "102", type: "task", displayId: "AM-501-1", parentDisplayId: "AM-501"
        )

        sut.buildTree(from: [epic, story, task])

        XCTAssertEqual(sut.rootNodes.count, 1, "One epic root node")
        let epicNode = sut.rootNodes[0]
        XCTAssertEqual(epicNode.id, "100", "Epic node ID")
        XCTAssertEqual(epicNode.children.count, 1, "Epic has one story child")

        let storyNode = epicNode.children[0]
        XCTAssertEqual(storyNode.id, "101", "Story node ID")
        XCTAssertEqual(storyNode.children.count, 1, "Story has one task child")
        XCTAssertEqual(storyNode.children[0].id, "102", "Task node ID")

        XCTAssertTrue(sut.orphanTaskNodes.isEmpty, "Task must not be orphaned")
        XCTAssertTrue(sut.orphanBugNodes.isEmpty, "No orphan bugs")
    }

    /// Stories that reference an epic via display ID must NOT appear as orphans.
    func testBuildTreeDisplayIdStoriesAreNotOrphaned() throws {
        let epic = try makeItemDisplayIdFormat(id: "200", type: "epic", displayId: "AM-600")
        let story1 = try makeItemDisplayIdFormat(
            id: "201", type: "story", displayId: "AM-601", parentDisplayId: "AM-600"
        )
        let story2 = try makeItemDisplayIdFormat(
            id: "202", type: "story", displayId: "AM-602", parentDisplayId: "AM-600"
        )

        sut.buildTree(from: [epic, story1, story2])

        XCTAssertEqual(sut.rootNodes.count, 1)
        XCTAssertEqual(sut.rootNodes[0].children.count, 2, "Both stories are children of the epic")
        XCTAssertTrue(sut.orphanTaskNodes.isEmpty)
    }

    /// Selecting a story by ID via revealTask must find it (requires a correctly built tree).
    func testRevealTaskFindsStoryNodeBuiltViaDisplayIdParent() throws {
        let epic = try makeItemDisplayIdFormat(id: "300", type: "epic", displayId: "AM-700")
        let story = try makeItemDisplayIdFormat(
            id: "301", type: "story", displayId: "AM-701", parentDisplayId: "AM-700"
        )

        sut.buildTree(from: [epic, story])
        sut.revealTask("301")

        XCTAssertEqual(sut.selectedNodeID, "301", "Story must be selectable after display-ID-based tree build")
        XCTAssertEqual(sut.selectedTask?.id, "301")
    }
}
