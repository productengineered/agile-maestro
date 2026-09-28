import Foundation

/// Node-building helpers for `TreeViewModel.buildTree(from:sessionID:)`.
///
/// Split out of `TreeViewModel.swift` to keep that file under the project's
/// SwiftLint file-length threshold. These methods only need read access to
/// `TreeViewModel.allTasks` (via `resolvedParentId(in:)`) from the primary
/// class file — no other cross-file state is required.
extension TreeViewModel {

    /// Shared lookup tables for a single `buildTree` pass, computed once by
    /// `makeBuildContext` and threaded through the node-builder methods instead
    /// of a long, repeated parameter list.
    struct TreeBuildContext {
        let epicIDSet: Set<String>
        let storyIDSet: Set<String>
        let bugTechDebtIDSet: Set<String>
        /// Tasks grouped by their resolved bug/techdebt parent ID.
        let tasksByParent: [String: [TaskItem]]
        let expandedIDs: Set<String>
    }

    /// Builds the lookup tables shared by every node builder for a single
    /// `buildTree` pass — epic/story/bug/techdebt ID sets and the resolved
    /// bug/techdebt → child-task grouping. Bundled into one `TreeBuildContext`
    /// value (together with the caller-supplied `expandedIDs`) so builder
    /// methods take a single parameter instead of a long, repeated list.
    func makeBuildContext(
        epics: [TaskItem],
        stories: [TaskItem],
        leafItems: [TaskItem],
        expandedIDs: Set<String>
    ) -> TreeBuildContext {
        let epicIDSet = Set(epics.map(\.id))
        let storyIDSet = Set(stories.map(\.id))
        let bugTechDebtIDSet = Set(
            leafItems.filter { $0.type == .bug || $0.type == .techdebt }.map(\.id))

        // Resolve each task's parent ID ONCE, up front, and group tasks parented
        // to a bug/techdebt item by that parent ID. Reused by every call site that
        // builds a bug/techdebt node's children (story-attached, epic-attached, or
        // orphaned) via O(1) dictionary reads instead of a per-node scan — same
        // approach as `leavesByResolvedParent` in `buildEpicNodes`.
        var tasksByParent: [String: [TaskItem]] = [:]
        for task in leafItems where task.type == .task {
            guard let parentId = task.resolvedParentId(in: allTasks),
                  bugTechDebtIDSet.contains(parentId) else { continue }
            tasksByParent[parentId, default: []].append(task)
        }

        return TreeBuildContext(
            epicIDSet: epicIDSet,
            storyIDSet: storyIDSet,
            bugTechDebtIDSet: bugTechDebtIDSet,
            tasksByParent: tasksByParent,
            expandedIDs: expandedIDs
        )
    }

    func buildStoryNodes(
        stories: [TaskItem],
        leafItems: [TaskItem],
        context: TreeBuildContext
    ) -> [String: TreeNode] {
        var storyNodes: [String: TreeNode] = [:]
        for story in stories {
            let children: [TreeNode] = leafItems
                .filter {
                    guard $0.type == .task || $0.type == .bug || $0.type == .techdebt else { return false }
                    return $0.resolvedParentId(in: allTasks) == story.id
                }
                .map { makeNode($0, context: context) }
            let node = TreeNode(task: story, children: children)
            node.isExpanded = context.expandedIDs.contains(story.id)
            storyNodes[story.id] = node
        }
        return storyNodes
    }

    func buildEpicNodes(
        epics: [TaskItem],
        stories: [TaskItem],
        storyNodes: [String: TreeNode],
        leafItems: [TaskItem],
        context: TreeBuildContext
    ) -> [TreeNode] {
        // Resolve each epic-linkable leaf's (bug/techdebt) parent ID ONCE, up
        // front, instead of re-resolving it inside the per-epic `.filter` below
        // (which was an O(epics * leaves * tasks) linear-scan fallback inside
        // `resolvedParentId(in:)` for every epic × leaf pair). Grouping by
        // resolved parent ID makes the per-epic lookup an O(1) dictionary read.
        let epicLinkedLeaves = leafItems.filter { $0.type == .bug || $0.type == .techdebt }
        var leavesByResolvedParent: [String: [TaskItem]] = [:]
        for leaf in epicLinkedLeaves {
            guard let parentId = leaf.resolvedParentId(in: allTasks) else { continue }
            leavesByResolvedParent[parentId, default: []].append(leaf)
        }

        return epics.map { epic in
            let storyChildren = stories
                .filter { $0.resolvedParentId(in: allTasks) == epic.id }
                .compactMap { storyNodes[$0.id] }
            // Bugs/techdebt parented directly to this epic render as epic children
            // too, appended AFTER the story children so existing ordering
            // assumptions (epic.children[0] == first story) keep holding. Leaf
            // order within the group matches `epicLinkedLeaves`'s original order
            // (dictionary values preserve insertion order per key).
            let leafChildren = (leavesByResolvedParent[epic.id] ?? [])
                .map { makeNode($0, context: context) }
            let node = TreeNode(task: epic, children: storyChildren + leafChildren)
            node.isExpanded = context.expandedIDs.contains(epic.id)
            return node
        }
    }

    func buildOrphanNodes(
        taskType: TaskType,
        leafItems: [TaskItem],
        context: TreeBuildContext
    ) -> [TreeNode] {
        // Tasks (.task type) have stories as their valid parents, not epics.
        // A task whose resolved parent matches an epic ID is therefore orphaned.
        // Tasks parented to a bug/techdebt ID are also valid — that task nests
        // under the bug/techdebt node (wherever it renders) instead of appearing
        // here, so `bugTechDebtIDSet` is folded into the task type's valid parents.
        // Bugs and techdebt treat both epic and story IDs as valid parents because
        // buildEpicNodes and buildStoryNodes both attach them directly as children
        // of a matching epic or story; this filter only needs to exclude those
        // already-attached items from the orphan sections below.
        let validParentIDs: Set<String> = taskType == .task
            ? context.storyIDSet.union(context.bugTechDebtIDSet)
            : context.epicIDSet.union(context.storyIDSet)

        return leafItems
            .filter { item in
                guard item.type == taskType else { return false }
                guard let parentId = item.resolvedParentId(in: allTasks) else { return true }
                return !validParentIDs.contains(parentId)
            }
            .map { makeNode($0, context: context) }
    }

    /// Builds a leaf `TreeNode` for a task/bug/techdebt item. Bug and techdebt
    /// items additionally attach their own child tasks (looked up in
    /// `context.tasksByParent`, grouped once in `makeBuildContext`) — this runs
    /// regardless of where the bug/techdebt node itself renders (under a story,
    /// under an epic, or in the loose Bugs/Tech Debt sections).
    func makeNode(_ item: TaskItem, context: TreeBuildContext) -> TreeNode {
        let children: [TreeNode]
        if item.type == .bug || item.type == .techdebt {
            children = (context.tasksByParent[item.id] ?? [])
                .map { makeNode($0, context: context) }
        } else {
            children = []
        }
        let node = TreeNode(task: item, children: children)
        node.isExpanded = context.expandedIDs.contains(item.id)
        return node
    }
}
