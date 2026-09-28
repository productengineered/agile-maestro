import Foundation
import Observation
import os

/// ViewModel that builds and maintains a hierarchical task tree from a flat
/// `[TaskItem]` array produced by `TaskParserService`.
///
/// Responsibilities:
/// - Groups epics as root nodes, attaches stories to matching epic parents,
///   attaches tasks to matching story parents, and attaches bugs/techdebt to
///   matching story OR epic parents (bugs/techdebt attached to an epic render
///   as epic children, after the epic's story children).
/// - Nests tasks whose parent is a bug or tech debt item as children of that
///   bug/techdebt node, wherever it renders (under a story, under an epic, or
///   in the loose Bugs/Tech Debt sections) — those tasks are excluded from the
///   loose Tasks section. Node-builder methods live in
///   `TreeViewModel+NodeBuilding.swift`.
/// - Separates orphan bugs and techdebt (items whose parent doesn't match any
///   epic in the current set) into dedicated sections.
/// - Tracks `selectedNodeID` and `selectedTask` for sidebar selection.
/// - Persists per-node expand state to UserDefaults keyed by session ID.
/// - Exposes `taskCountText` for the sidebar header badge.
@Observable
@MainActor
final class TreeViewModel {

    // MARK: - UserDefaults Keys

    private enum UserDefaultsKey {
        static let claudeTaskSectionExpanded = "taskTree.claudeTaskSectionExpanded"
        static let orphanedTaskSectionExpanded = "taskTree.orphanedTaskSectionExpanded"
    }

    // MARK: - Public State

    /// Top-level nodes (epics, and tasks/stories with no matching parent).
    private(set) var rootNodes: [TreeNode] = []

    /// Bugs whose `parentId` does not match any epic ID in the current set.
    private(set) var orphanBugNodes: [TreeNode] = []

    /// Tech debt items whose `parentId` does not match any epic ID in the current set.
    private(set) var orphanTechDebtNodes: [TreeNode] = []

    /// Tasks (type == .task) whose `parentId` does not match any story ID in the current set.
    private(set) var orphanTaskNodes: [TreeNode] = []

    /// ID of the currently selected node. Nil when nothing is selected.
    private(set) var selectedNodeID: String?

    /// The selected task item. Nil when nothing is selected.
    private(set) var selectedTask: TaskItem?

    /// ID of the currently selected Claude Task. Nil when nothing is selected.
    private(set) var selectedClaudeTaskID: String?

    /// The selected Claude Task. Nil when nothing is selected.
    private(set) var selectedClaudeTask: ClaudeTask?

    /// Whether the Bugs orphan section is expanded. Default true.
    var isBugSectionExpanded: Bool = true

    /// Whether the Tech Debt orphan section is expanded. Default true.
    var isTechDebtSectionExpanded: Bool = true

    /// Whether the Tasks orphan section is expanded. Default true.
    var isTaskSectionExpanded: Bool = true

    /// Whether the Claude Tasks section is expanded. Persisted across launches via UserDefaults.
    var isClaudeTaskSectionExpanded: Bool =
        UserDefaults.standard.object(forKey: UserDefaultsKey.claudeTaskSectionExpanded) as? Bool ?? true {
        didSet { UserDefaults.standard.set(
            isClaudeTaskSectionExpanded, forKey: UserDefaultsKey.claudeTaskSectionExpanded) }
    }

    /// Whether the Orphaned Tasks section is expanded. Persisted across launches via UserDefaults.
    var isOrphanedTaskSectionExpanded: Bool =
        UserDefaults.standard.object(forKey: UserDefaultsKey.orphanedTaskSectionExpanded) as? Bool ?? true {
        didSet { UserDefaults.standard.set(
            isOrphanedTaskSectionExpanded, forKey: UserDefaultsKey.orphanedTaskSectionExpanded) }
    }

    /// ID of the currently selected orphaned task. Nil when nothing is selected.
    private(set) var selectedOrphanedTaskID: String?

    /// The selected orphaned task. Nil when nothing is selected.
    private(set) var selectedOrphanedTask: OrphanedTask?

    /// Claude Code task files parsed as `ClaudeTask` values, sorted in dependency
    /// order (tasks that block others appear before the tasks they block).
    ///
    /// Populated via `setClaudeTasks(_:orphanedTasks:)`. Empty until that method
    /// is called.
    private(set) var claudeTasks: [ClaudeTask] = []

    /// Task files that could not be fully parsed, preserved for user inspection.
    ///
    /// Populated via `setClaudeTasks(_:orphanedTasks:)`. Empty until that method
    /// is called.
    private(set) var orphanedTasks: [OrphanedTask] = []

    // MARK: - Private State

    /// Session ID used to key UserDefaults expand state.
    private var sessionID: String = ""

    /// Flat list of all task items in the current session. Read (not written)
    /// by the node-builder methods in `TreeViewModel+NodeBuilding.swift`.
    private(set) var allTasks: [TaskItem] = []

    // MARK: - Computed Properties

    /// Total number of leaf items (type == .task, .bug, or .techdebt) in the session.
    /// Excludes epics and stories, which are container types, not work items.
    var taskCount: Int {
        allTasks.filter { isLeafType($0.type) }.count
    }

    /// Number of completed leaf items (type == .task, .bug, or .techdebt) in the session.
    var completedTaskCount: Int {
        allTasks.filter { isLeafType($0.type) && $0.status == .completed }.count
    }

    /// Returns true for leaf task types (task, bug, techdebt) — i.e. work items, not containers.
    private func isLeafType(_ type: TaskType) -> Bool {
        type == .task || type == .bug || type == .techdebt
    }

    /// Badge text for the sidebar header, e.g. "5/12".
    var taskCountText: String {
        "\(completedTaskCount)/\(taskCount)"
    }

    // MARK: - Logger

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.agilemaestro",
        category: "TreeViewModel"
    )

    // MARK: - Init

    init() {}

    // MARK: - Public Methods

    /// Rebuilds the tree from a flat array of `TaskItem` values.
    ///
    /// Call this whenever the session's tasks change (e.g., on file-watcher events
    /// or after a manual refresh). The method restores previously persisted expand
    /// state from UserDefaults so the user's open/close choices survive rebuilds.
    ///
    /// - Parameters:
    ///   - tasks: The flat list of tasks loaded from a session directory.
    ///   - sessionID: The identifier of the current session (used as a UserDefaults key prefix).
    func buildTree(from tasks: [TaskItem], sessionID: String = "") {
        self.sessionID = sessionID
        self.allTasks = tasks

        let epics = tasks.filter { $0.type == .epic }
        let stories = tasks.filter { $0.type == .story }
        let leafItems = tasks.filter { $0.type == .task || $0.type == .bug || $0.type == .techdebt }
        let context = makeBuildContext(
            epics: epics, stories: stories, leafItems: leafItems, expandedIDs: loadExpandedIDs())

        let storyNodes = buildStoryNodes(stories: stories, leafItems: leafItems, context: context)
        let epicNodes = buildEpicNodes(
            epics: epics, stories: stories, storyNodes: storyNodes, leafItems: leafItems, context: context)

        rootNodes = epicNodes
        orphanBugNodes = buildOrphanNodes(taskType: .bug, leafItems: leafItems, context: context)
        orphanTechDebtNodes = buildOrphanNodes(taskType: .techdebt, leafItems: leafItems, context: context)
        orphanTaskNodes = buildOrphanNodes(taskType: .task, leafItems: leafItems, context: context)

        // Clear the selection when the selected task no longer exists in the new
        // task set — e.g. when navigating to an empty directory.
        if let selectedID = selectedNodeID,
           !tasks.contains(where: { $0.id == selectedID }) {
            selectedNodeID = nil
            selectedTask = nil
            logger.debug("buildTree: cleared stale selection '\(selectedID)' — task not in new task set")
        }

        let bugCount = orphanBugNodes.count
        let tdCount = orphanTechDebtNodes.count
        let epicCount = epicNodes.count
        let storyCount = stories.count
        logger.info("buildTree: \(epicCount) epics, \(storyCount) stories, \(bugCount) bugs, \(tdCount) techdebt")
    }

    /// Updates the Claude Tasks and Orphaned Tasks collections exposed by this
    /// view-model.
    ///
    /// `claudeTasks` are sorted into dependency order using
    /// `ClaudeTask.sortedByDependencyOrder(_:)` before being stored, so consumers
    /// always receive tasks in a predictable "blocked-after-blocker" sequence.
    /// `orphanedTasks` are stored as-is because they have no dependency metadata.
    ///
    /// Call this from `syncViewModels` (in `MainWindowView`) whenever
    /// `SessionViewModel` produces a new parse result.
    ///
    /// - Parameters:
    ///   - claudeTasks: Raw, unsorted Claude Code task values from the parser.
    ///   - orphanedTasks: Task files that could not be parsed.
    func setClaudeTasks(_ claudeTasks: [ClaudeTask], orphanedTasks: [OrphanedTask]) {
        self.claudeTasks = ClaudeTask.sortedByDependencyOrder(claudeTasks)
        self.orphanedTasks = orphanedTasks

        // Clear stale selections: if the selected task is no longer in the new
        // arrays, reset it to avoid dangling references after a session change.
        let newClaudeIDs = Set(self.claudeTasks.map(\.id))
        if let selectedID = selectedClaudeTaskID, !newClaudeIDs.contains(selectedID) {
            selectedClaudeTaskID = nil
            selectedClaudeTask = nil
        }
        let newOrphanFilenames = Set(self.orphanedTasks.map(\.id))
        if let selectedFilename = selectedOrphanedTaskID, !newOrphanFilenames.contains(selectedFilename) {
            selectedOrphanedTaskID = nil
            selectedOrphanedTask = nil
        }

        let claudeCount = self.claudeTasks.count
        let orphanCount = self.orphanedTasks.count
        logger.info("setClaudeTasks: \(claudeCount) claude tasks, \(orphanCount) orphaned tasks")
    }

    /// Selects the given node, updating `selectedNodeID` and `selectedTask`.
    ///
    /// Selecting the already-selected node is a no-op.
    func selectNode(_ node: TreeNode) {
        selectedNodeID = node.id
        selectedTask = node.task
        selectedClaudeTaskID = nil
        selectedClaudeTask = nil
        selectedOrphanedTaskID = nil
        selectedOrphanedTask = nil
    }

    /// Selects the given Claude Task, updating `selectedClaudeTaskID` and `selectedClaudeTask`.
    ///
    /// Clears any tree-node selection so only one item is selected at a time.
    func selectClaudeTask(_ task: ClaudeTask) {
        selectedClaudeTaskID = task.id
        selectedClaudeTask = task
        selectedNodeID = nil
        selectedTask = nil
        selectedOrphanedTaskID = nil
        selectedOrphanedTask = nil
    }

    /// Selects the given orphaned task, updating `selectedOrphanedTaskID` and `selectedOrphanedTask`.
    ///
    /// Clears any tree-node or Claude Task selection so only one item is selected at a time.
    func selectOrphanedTask(_ task: OrphanedTask) {
        selectedOrphanedTaskID = task.id
        selectedOrphanedTask = task
        selectedNodeID = nil
        selectedTask = nil
        selectedClaudeTaskID = nil
        selectedClaudeTask = nil
    }

    /// Clears the current selection.
    func clearSelection() {
        selectedNodeID = nil
        selectedTask = nil
        selectedClaudeTaskID = nil
        selectedClaudeTask = nil
        selectedOrphanedTaskID = nil
        selectedOrphanedTask = nil
    }

    /// Reveals the node with the given ID in the sidebar by expanding all of its ancestors
    /// and updating the selection to that node.
    ///
    /// Used by breadcrumb navigation in `DetailHeaderView` (IS-BREADCRUMB-001) so that
    /// tapping a parent breadcrumb segment also updates the sidebar selection.
    ///
    /// - Parameter taskID: The ID of the task to reveal. No-op if not found in the tree.
    func revealTask(_ taskID: String) {
        // Find and expand ancestor chain, then select the target node.
        if let node = findNode(id: taskID) {
            expandAncestors(of: taskID)
            clearSelection()
            selectedNodeID = node.id
            selectedTask = node.task
            persistExpandedIDs()
        }
    }

    /// Expands all ancestor nodes of the task with the given ID.
    @discardableResult
    private func expandAncestors(of taskID: String) -> Bool {
        if rootNodes.contains(where: { expandAncestors(of: taskID, in: $0) }) { return true }
        // Orphan nodes are direct children — no ancestors to expand, just confirm presence.
        if orphanBugNodes.contains(where: { $0.id == taskID }) { return true }
        if orphanTechDebtNodes.contains(where: { $0.id == taskID }) { return true }
        if orphanTaskNodes.contains(where: { $0.id == taskID }) { return true }
        return false
    }

    /// Recursively expands ancestors. Returns `true` if the target was found in this subtree.
    private func expandAncestors(of taskID: String, in node: TreeNode) -> Bool {
        if node.id == taskID { return true }
        let foundInChild = node.children.contains { child in
            expandAncestors(of: taskID, in: child)
        }
        if foundInChild {
            node.isExpanded = true
        }
        return foundInChild
    }

    /// Toggles the expand state of a node and persists the new state to UserDefaults.
    ///
    /// - Parameter node: The node to expand or collapse.
    func toggleExpand(node: TreeNode) {
        node.isExpanded.toggle()
        persistExpandedIDs()
    }

    /// Expands the currently selected node (Right arrow). No-op if no selection or node is a leaf.
    func expandSelectedNode() {
        guard let nodeID = selectedNodeID else { return }
        guard let node = findNode(id: nodeID) else { return }
        guard node.hasChildren, !node.isExpanded else { return }
        node.isExpanded = true
        persistExpandedIDs()
    }

    /// Collapses the currently selected node (Left arrow). No-op if no selection or node is already collapsed.
    func collapseSelectedNode() {
        guard let nodeID = selectedNodeID else { return }
        guard let node = findNode(id: nodeID) else { return }
        guard node.hasChildren, node.isExpanded else { return }
        node.isExpanded = false
        persistExpandedIDs()
    }

    /// Toggles the bug orphan section expand state.
    func toggleBugSection() {
        isBugSectionExpanded.toggle()
    }

    /// Toggles the tech debt orphan section expand state.
    func toggleTechDebtSection() {
        isTechDebtSectionExpanded.toggle()
    }

    /// Toggles the tasks orphan section expand state.
    func toggleTaskSection() {
        isTaskSectionExpanded.toggle()
    }

    /// Toggles the Claude Tasks section expand state.
    func toggleClaudeTaskSection() {
        isClaudeTaskSectionExpanded.toggle()
    }

    /// Toggles the Orphaned Tasks section expand state.
    func toggleOrphanedTaskSection() {
        isOrphanedTaskSectionExpanded.toggle()
    }

    // MARK: - Node Lookup

    /// Recursively searches the tree for a node with the given ID.
    private func findNode(id: String) -> TreeNode? {
        for node in rootNodes {
            if let found = findNode(id: id, in: node) { return found }
        }
        for node in orphanBugNodes where node.id == id { return node }
        for node in orphanTechDebtNodes where node.id == id { return node }
        for node in orphanTaskNodes where node.id == id { return node }
        return nil
    }

    private func findNode(id: String, in node: TreeNode) -> TreeNode? {
        if node.id == id { return node }
        for child in node.children {
            if let found = findNode(id: id, in: child) { return found }
        }
        return nil
    }

    // MARK: - Snapshot / Restore

    /// Returns the set of node IDs that are currently expanded across the entire tree.
    ///
    /// Call this *before* rebuilding the tree (e.g. before `buildTree`) to capture
    /// the user's current expand state. Pass the result to `restoreExpandedIDs(_:)`
    /// after the rebuild to make the reload transparent to the user.
    ///
    /// - Returns: A `Set<String>` of expanded node IDs.
    func snapshotExpandedIDs() -> Set<String> {
        collectExpandedIDs()
    }

    /// Restores expand state for nodes that are present in the rebuilt tree.
    ///
    /// Call this *after* `buildTree` completes with the set returned by a prior
    /// `snapshotExpandedIDs()` call. Nodes that no longer exist in the tree are
    /// silently skipped; new nodes that were not in the snapshot remain collapsed.
    ///
    /// - Parameter ids: The set of node IDs to re-expand.
    func restoreExpandedIDs(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        for node in rootNodes {
            restoreExpandedIDs(ids, in: node)
        }
        for node in orphanBugNodes where ids.contains(node.id) {
            node.isExpanded = true
        }
        for node in orphanTechDebtNodes where ids.contains(node.id) {
            node.isExpanded = true
        }
        for node in orphanTaskNodes where ids.contains(node.id) {
            node.isExpanded = true
        }
        logger.debug("restoreExpandedIDs: requested \\(ids.count) IDs restored across rebuilt tree")
    }

    /// Recursively restores expand state for nodes within a subtree.
    private func restoreExpandedIDs(_ ids: Set<String>, in node: TreeNode) {
        if ids.contains(node.id) {
            node.isExpanded = true
        }
        for child in node.children {
            restoreExpandedIDs(ids, in: child)
        }
    }

    // MARK: - UserDefaults Persistence

    /// Returns the UserDefaults key for the current session's expand state.
    private var userDefaultsKey: String {
        "expandedNodes_\(sessionID)"
    }

    /// Saves the IDs of all currently expanded nodes to UserDefaults.
    private func persistExpandedIDs() {
        let expandedIDs = collectExpandedIDs()
        UserDefaults.standard.set(Array(expandedIDs), forKey: userDefaultsKey)
        let count = expandedIDs.count
        logger.debug("Persisted \(count) expanded node IDs for session '\(self.sessionID)'")
    }

    /// Loads the set of expanded node IDs from UserDefaults.
    private func loadExpandedIDs() -> Set<String> {
        guard !sessionID.isEmpty,
              let stored = UserDefaults.standard.array(forKey: userDefaultsKey) as? [String] else {
            return []
        }
        return Set(stored)
    }

    /// Collects the IDs of all currently expanded nodes across the entire tree.
    private func collectExpandedIDs() -> Set<String> {
        var ids: Set<String> = []
        for node in rootNodes {
            collectExpandedIDs(from: node, into: &ids)
        }
        for node in orphanBugNodes where node.isExpanded {
            ids.insert(node.id)
        }
        for node in orphanTechDebtNodes where node.isExpanded {
            ids.insert(node.id)
        }
        for node in orphanTaskNodes where node.isExpanded {
            ids.insert(node.id)
        }
        return ids
    }

    /// Recursively collects expanded IDs starting from `node`.
    private func collectExpandedIDs(from node: TreeNode, into ids: inout Set<String>) {
        if node.isExpanded {
            ids.insert(node.id)
        }
        for child in node.children {
            collectExpandedIDs(from: child, into: &ids)
        }
    }
}
