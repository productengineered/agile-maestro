import SwiftUI

// MARK: - TaskTreeView

/// Root tree sidebar view.
///
/// Displays epics + stories + tasks in a collapsible hierarchy, followed by
/// optional orphan Bugs, Tech Debt, Claude Tasks, and Orphaned Tasks collapsible sections.
/// Contained in the sidebar column of `NavigationSplitView` via `TreeDetailView`.
///
/// Data source: `TreeViewModel` (environment). Selection and expand state are
/// both owned by `TreeViewModel`; views call ViewModel methods to mutate state.
struct TaskTreeView: View {

    // MARK: - Environment

    @Environment(TreeViewModel.self) private var treeViewModel

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader

            Divider()
                .padding(.bottom, 4)

            if treeViewModel.rootNodes.isEmpty
                && treeViewModel.orphanBugNodes.isEmpty
                && treeViewModel.orphanTechDebtNodes.isEmpty
                && treeViewModel.orphanTaskNodes.isEmpty
                && treeViewModel.claudeTasks.isEmpty
                && treeViewModel.orphanedTasks.isEmpty {
                emptyContent
            } else {
                treeContent
            }
        }
        .onKeyPress(.rightArrow) {
            treeViewModel.expandSelectedNode()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            treeViewModel.collapseSelectedNode()
            return .handled
        }
    }

    // MARK: - Section Header

    private var sectionHeader: some View {
        HStack(spacing: 8) {
            Text("Task Tree")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(1.2)

            Spacer()

            // Completed/total count badge e.g. "5/12"
            Text(treeViewModel.taskCountText)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // MARK: - Empty Content

    private var emptyContent: some View {
        ContentUnavailableView(
            "No Tasks",
            systemImage: "checklist",
            description: Text("Open a task directory or select a session to load tasks.")
        )
        .frame(maxHeight: .infinity)
    }

    // MARK: - Tree Content

    private var treeContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Main hierarchy: epic root nodes (recursive)
                ForEach(treeViewModel.rootNodes) { node in
                    TreeNodeView(node: node, indentLevel: 0)
                }

                // Orphan tasks section (only when non-empty)
                if !treeViewModel.orphanTaskNodes.isEmpty {
                    if !treeViewModel.rootNodes.isEmpty {
                        Divider()
                            .padding(.vertical, 4)
                    }

                    CollapsibleSectionView(
                        title: "Tasks",
                        count: treeViewModel.orphanTaskNodes.count,
                        isExpanded: treeViewModel.isTaskSectionExpanded,
                        onToggle: { treeViewModel.toggleTaskSection() },
                        content: {
                        ForEach(treeViewModel.orphanTaskNodes) { node in
                            TreeRowView(
                                node: node,
                                indentLevel: 0,
                                isSelected: treeViewModel.selectedNodeID == node.id,
                                onSelect: { treeViewModel.selectNode(node) },
                                onToggleExpand: nil
                            )
                        }
                    })
                }

                // Orphan bugs section (only when non-empty)
                if !treeViewModel.orphanBugNodes.isEmpty {
                    Divider()
                        .padding(.vertical, 4)

                    CollapsibleSectionView(
                        title: "Bugs",
                        count: treeViewModel.orphanBugNodes.count,
                        isExpanded: treeViewModel.isBugSectionExpanded,
                        onToggle: { treeViewModel.toggleBugSection() },
                        content: {
                        ForEach(treeViewModel.orphanBugNodes) { node in
                            TreeRowView(
                                node: node,
                                indentLevel: 0,
                                isSelected: treeViewModel.selectedNodeID == node.id,
                                onSelect: { treeViewModel.selectNode(node) },
                                onToggleExpand: nil
                            )
                        }
                    })
                }

                // Orphan tech debt section (only when non-empty)
                if !treeViewModel.orphanTechDebtNodes.isEmpty {
                    Divider()
                        .padding(.vertical, 4)

                    CollapsibleSectionView(
                        title: "Tech Debt",
                        count: treeViewModel.orphanTechDebtNodes.count,
                        isExpanded: treeViewModel.isTechDebtSectionExpanded,
                        onToggle: { treeViewModel.toggleTechDebtSection() },
                        content: {
                        ForEach(treeViewModel.orphanTechDebtNodes) { node in
                            TreeRowView(
                                node: node,
                                indentLevel: 0,
                                isSelected: treeViewModel.selectedNodeID == node.id,
                                onSelect: { treeViewModel.selectNode(node) },
                                onToggleExpand: nil
                            )
                        }
                    })
                }

                // Claude Tasks section (only when non-empty)
                if !treeViewModel.claudeTasks.isEmpty {
                    Divider()
                        .padding(.vertical, 4)

                    CollapsibleSectionView(
                        title: "Claude Tasks",
                        count: treeViewModel.claudeTasks.count,
                        isExpanded: treeViewModel.isClaudeTaskSectionExpanded,
                        onToggle: { treeViewModel.toggleClaudeTaskSection() },
                        content: {
                        ForEach(treeViewModel.claudeTasks) { task in
                            ClaudeTaskRowView(
                                task: task,
                                isSelected: treeViewModel.selectedClaudeTaskID == task.id,
                                onSelect: { treeViewModel.selectClaudeTask(task) }
                            )
                        }
                    })
                }

                // Orphaned Tasks section (only when non-empty)
                if !treeViewModel.orphanedTasks.isEmpty {
                    Divider()
                        .padding(.vertical, 4)

                    CollapsibleSectionView(
                        title: "Orphaned Tasks",
                        count: treeViewModel.orphanedTasks.count,
                        isExpanded: treeViewModel.isOrphanedTaskSectionExpanded,
                        badgeColor: .orange,
                        onToggle: { treeViewModel.toggleOrphanedTaskSection() },
                        content: {
                        ForEach(treeViewModel.orphanedTasks) { task in
                            OrphanedTaskRowView(
                                task: task,
                                isSelected: treeViewModel.selectedOrphanedTaskID == task.id,
                                onSelect: { treeViewModel.selectOrphanedTask(task) }
                            )
                        }
                    })
                }

                // Bottom breathing room
                Spacer(minLength: 16)
            }
            .padding(.horizontal, 4)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
    }
}

// MARK: - ClaudeTaskRowView

/// A single row in the Claude Tasks sidebar section.
///
/// Renders a status dot and the task subject text, with selection highlight.
/// Tap to select; selection detail is wired in task 228.
private struct ClaudeTaskRowView: View {

    // MARK: - Properties

    let task: ClaudeTask
    let isSelected: Bool
    let onSelect: () -> Void

    // MARK: - Body

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                // Aligns with TreeRowView indentLevel-0 text x-position:
                // TreeRowView: 8pt padding + 24pt chevron + 6pt gap + 11pt TypeIconView + 6pt gap = 55pt to text.
                // Here: 8pt padding + 28pt spacer + 6pt gap + 7pt circle + 6pt gap = 55pt to text.
                Spacer()
                    .frame(width: 28)

                // Status dot derived from raw status string
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                    .accessibilityLabel(task.status ?? "Unknown")

                Text(task.subject.isEmpty ? task.id : task.subject)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.15)
                    : Color.clear
            )
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(task.subject.isEmpty ? "Task \(task.id)" : task.subject)
        .accessibilityHint("Claude Task, \(task.status ?? "unknown status")")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Status Color

    private var statusColor: Color {
        switch task.status {
        case "in_progress": return .blue
        case "completed":   return .green
        default:            return .gray   // pending, nil, or unknown
        }
    }
}

// MARK: - OrphanedTaskRowView

/// A single row in the Orphaned Tasks sidebar section.
///
/// Renders a warning SF Symbol and the filename (the subject may be missing since
/// orphaned tasks could not be fully parsed). Tap to select; selection detail is
/// wired via the detail panel router in task 228.
private struct OrphanedTaskRowView: View {

    // MARK: - Properties

    let task: OrphanedTask
    let isSelected: Bool
    let onSelect: () -> Void

    // MARK: - Body

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                // Same 28pt leading spacer as ClaudeTaskRowView to match TreeRowView
                // indentLevel-0 text x-position: 8pt padding + 28pt spacer + 6gap + ~10pt icon + 6gap = 58pt.
                // (OrphanedTask icon is ~10pt vs 7pt circle; close enough for visual alignment.)
                Spacer()
                    .frame(width: 28)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)

                Text(task.filename)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.15)
                    : Color.clear
            )
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Orphaned file: \(task.filename)")
        .accessibilityHint(task.errorMessage.isEmpty ? "Could not be parsed" : task.errorMessage)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - TreeNodeView (Recursive)

/// Recursive wrapper that renders a `TreeRowView` and, if expanded, its children.
///
/// Recursion terminates at leaf nodes (`hasChildren == false`). Indent level
/// caps at 3 (epic=0, story=1, task=2) since the data model does not support
/// deeper nesting. Children appear with a spring animation driven by `node.isExpanded`.
private struct TreeNodeView: View {

    // MARK: - Environment

    @Environment(TreeViewModel.self) private var treeViewModel

    // MARK: - Properties

    let node: TreeNode
    let indentLevel: Int

    // MARK: - Body

    var body: some View {
        let isSelected = treeViewModel.selectedNodeID == node.id

        VStack(alignment: .leading, spacing: 0) {
            TreeRowView(
                node: node,
                indentLevel: indentLevel,
                isSelected: isSelected,
                onSelect: {
                    treeViewModel.selectNode(node)
                },
                onToggleExpand: {
                    treeViewModel.toggleExpand(node: node)
                }
            )

            // Expanded children with spring animation
            if node.isExpanded && node.hasChildren {
                ForEach(node.children) { child in
                    TreeNodeView(
                        node: child,
                        // Indent level capped at 3: epic=0, story=1, task=2
                        indentLevel: min(indentLevel + 1, 3)
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0, anchor: .top)))
                }
                .animation(
                    .spring(response: 0.3, dampingFraction: 0.85),
                    value: node.isExpanded
                )
            }
        }
    }
}

// MARK: - Preview

#Preview("TaskTreeView — Populated") {
    let treeVM = TreeViewModel()

    let epicJSON = """
    {
      "id": "e1", "subject": "Epic: App Shell", "description": "",
      "status": "in_progress", "blocks": [], "blockedBy": [],
      "metadata": { "type": "epic", "priority": "P1", "approval": "approved", "blocked": false }
    }
    """
    let storyJSON = """
    {
      "id": "s1", "subject": "Story: Tree Sidebar", "description": "",
      "status": "pending", "blocks": [], "blockedBy": [],
      "metadata": { "type": "story", "priority": "P2", "approval": "approved", "blocked": false }
    }
    """
    let taskJSON = """
    {
      "id": "t1", "subject": "Task: Create TreeRowView", "description": "",
      "status": "completed", "blocks": [], "blockedBy": [],
      "metadata": { "type": "task", "priority": "P2", "approval": "approved", "blocked": false }
    }
    """
    let bugJSON = """
    {
      "id": "b1", "subject": "Bug: Crash on launch", "description": "",
      "status": "pending", "blocks": [], "blockedBy": [],
      "metadata": { "type": "bug", "priority": "P0", "approval": "approved", "blocked": false }
    }
    """

    let decode: (String) -> TaskItem? = { json in
        try? JSONDecoder().decode(TaskItem.self, from: Data(json.utf8))
    }

    if let epicItem = decode(epicJSON),
       let storyItem = decode(storyJSON),
       let taskItem = decode(taskJSON),
       let bugItem = decode(bugJSON) {
        let taskNode = TreeNode(task: taskItem)
        let storyNode = TreeNode(task: storyItem, children: [taskNode])
        storyNode.isExpanded = true
        let epicNode = TreeNode(task: epicItem, children: [storyNode])
        epicNode.isExpanded = true

        treeVM.buildTree(
            from: [epicItem, storyItem, taskItem, bugItem],
            sessionID: "preview"
        )
    }

    return TaskTreeView()
        .environment(treeVM)
        .frame(width: 260, height: 500)
}

#Preview("TaskTreeView — Empty") {
    TaskTreeView()
        .environment(TreeViewModel())
        .frame(width: 260, height: 400)
}
