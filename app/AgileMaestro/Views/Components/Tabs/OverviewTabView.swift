// swiftlint:disable file_length
import SwiftUI

// MARK: - OverviewTabView

/// Dispatches to type-specific overview content based on the task type.
///
/// Tab content area provides 16pt horizontal padding (set by TaskDetailView container)
/// and 24pt bottom padding. Implements all content variants from the design spec:
/// - Epic: stories table (IS-STORY-NAV-001), references/dependencies, git branch
/// - Story: review progress card, AI context card, dependencies card
/// - Task/Bug/TechDebt: affected files card, files card, blocked-by + assignment cards
///
/// Note: StatsBarView is rendered by TaskDetailView above the tab pills — not here.
struct OverviewTabView: View {
    @Environment(DetailViewModel.self) private var viewModel
    @Environment(TreeViewModel.self) private var treeViewModel
    let task: TaskItem

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            switch task.type {
            case .epic:
                EpicOverviewContent(task: task)
            case .story:
                StoryOverviewContent(task: task)
            case .bug:
                BugOverviewContent(task: task)
            case .techdebt:
                TechDebtOverviewContent(task: task)
            case .task:
                TaskOverviewContent(task: task)
            }
        }
    }
}

// MARK: - EpicOverviewContent

/// Epic overview: stat pills row + stories table + references/dependencies side-by-side + git branch.
private struct EpicOverviewContent: View {
    @Environment(DetailViewModel.self) private var viewModel
    @Environment(TreeViewModel.self) private var treeViewModel
    let task: TaskItem

    // Children stories resolved from session
    private var childStories: [TaskItem] { viewModel.childStories(of: task) }

    // Bugs/techdebt parented directly to this epic (not via a story)
    private var linkedItems: [TaskItem] { viewModel.linkedItems(of: task) }

    var body: some View {
        // Goal hero card (first — highest-leverage orientation element)
        if let goal = task.metadata.epic?.goal, !goal.isEmpty {
            EpicGoalCallout(goal: goal)
        }

        // Status & Workflow card (approval, blocked)
        StatusWorkflowCard(task: task)

        // Labels chip row
        if !task.labels.isEmpty {
            LabelsChipRow(labels: task.labels)
        }

        // Stories table card
        CardView(title: "Stories", icon: "doc.text", iconColor: .blue) {
            if childStories.isEmpty {
                ContentUnavailableView(
                    "No Stories",
                    systemImage: "doc.text",
                    description: Text("No child stories found for this epic.")
                )
                .padding(.top, 8)
            } else {
                VStack(spacing: 0) {
                    // Table header
                    storiesTableHeader
                        .padding(.bottom, 8)

                    Divider()

                    // Story rows (sorted: in-progress first, pending, completed last)
                    ForEach(sortedStories) { story in
                        StoryTableRow(story: story) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.navigate(to: story)
                                treeViewModel.revealTask(story.id)
                            }
                        }
                    }
                }
            }
        }

        // Linked Items card — bugs/techdebt parented directly to this epic (not via a story)
        if !linkedItems.isEmpty {
            CardView(title: "Linked Items", icon: "link.badge.plus", iconColor: .orange) {
                VStack(spacing: 0) {
                    linkedItemsTableHeader
                        .padding(.bottom, 8)

                    Divider()

                    ForEach(sortedLinkedItems) { item in
                        TaskTableRow(taskItem: item) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.navigate(to: item)
                                treeViewModel.revealTask(item.id)
                            }
                        }
                    }
                }
            }
        }

        // References & Dependencies (side-by-side if both exist)
        let refs = task.metadata.epic?.references
        let hasReferences = refs != nil && (
            !(refs?.prdStories?.isEmpty ?? true) ||
            !(refs?.techSpecSections?.isEmpty ?? true) ||
            !(refs?.dataSchemaSection?.isEmpty ?? true) ||
            !(refs?.uiSpecSections?.isEmpty ?? true) ||
            !(refs?.notes?.isEmpty ?? true)
        )
        let hasDeps = !(task.metadata.epic?.allExternalDeps.isEmpty ?? true) ||
                      !(task.metadata.epic?.allBlocksEpics.isEmpty ?? true)

        if hasReferences || hasDeps {
            HStack(alignment: .top, spacing: 12) {
                if let refs = task.metadata.epic?.references {
                    EpicReferencesCard(references: refs)
                }
                if hasDeps {
                    EpicDependenciesCard(task: task)
                }
            }
        }

        // Git branch
        if let branch = task.metadata.epic?.branch {
            CardView(title: "Branch", icon: "arrow.branch", iconColor: .secondary) {
                Text(branch)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }

        // Blocks card — downstream epics/items this epic unblocks (SM-DP700-BLOCKS-006)
        BlocksCard(task: task)
    }

    private var storiesTableHeader: some View {
        HStack(spacing: 0) {
            Text("STATUS")
                .frame(width: 60, alignment: .leading)
            Text("STORY")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("PTS")
                .frame(width: 36, alignment: .trailing)
            Text("TASKS")
                .frame(width: 44, alignment: .trailing)
            Text("PROGRESS")
                .frame(width: 70, alignment: .trailing)
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(.tertiary)
        .textCase(.uppercase)
        .tracking(0.5)
    }

    private var sortedStories: [TaskItem] {
        // in-progress first, pending second (orange dot), completed last
        childStories.sorted { $0.status.sortRank < $1.status.sortRank }
    }

    private var linkedItemsTableHeader: some View {
        HStack(spacing: 0) {
            Text("STATUS")
                .frame(width: 60, alignment: .leading)
            Text("ITEM")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("TYPE")
                .frame(width: 60, alignment: .trailing)
            Text("PRIORITY")
                .frame(width: 60, alignment: .trailing)
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(.tertiary)
        .textCase(.uppercase)
        .tracking(0.5)
    }

    private var sortedLinkedItems: [TaskItem] {
        // in-progress first, pending second, completed last
        linkedItems.sorted { $0.status.sortRank < $1.status.sortRank }
    }
}

// MARK: - EpicGoalCallout

/// Hero card that surfaces the epic's goal field as the first element in EpicOverviewContent.
/// Renders an accent-color bar on the left side (ui-design-audit 4b pattern).
private struct EpicGoalCallout: View {
    let goal: String

    var body: some View {
        CardView(title: "Goal", icon: "target", iconColor: .accentColor) {
            HStack(alignment: .top, spacing: 12) {
                // Accent bar — 3pt wide per design audit pattern 4b
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 1.5))

                Text(goal)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Goal: \(goal)")
    }
}

// MARK: - StoryTableRow

/// Single row in the epic's stories table. Full-row tappable (IS-STORY-NAV-001).
private struct StoryTableRow: View {
    @Environment(DetailViewModel.self) private var viewModel
    let story: TaskItem
    let onTap: () -> Void

    @State private var isHovered = false

    // Progress: completed tasks / total tasks for this story
    private var progressInfo: (completed: Int, total: Int) {
        viewModel.taskProgress(for: story)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Status dot
            statusDot
                .frame(width: 60, alignment: .leading)

            // Story title
            Text(story.subject)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)

            // Points
            if let points = story.metadata.story?.points {
                Text("\(points)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 36, alignment: .trailing)
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 36, alignment: .trailing)
            }

            // Task count
            Text("\(progressInfo.total)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)

            // Progress bar + percentage
            let pct = progressInfo.total > 0
                ? Double(progressInfo.completed) / Double(progressInfo.total)
                : 0.0
            VStack(alignment: .trailing, spacing: 2) {
                ProgressBarView(value: pct)
                    .frame(width: 60)
                Text("\(Int(pct * 100))%")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.secondary.opacity(0.05) : Color.clear)
                .animation(.easeInOut(duration: 0.12), value: isHovered)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { hovered in
            isHovered = hovered
            if hovered {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onDisappear {
            if isHovered {
                NSCursor.pop()
                isHovered = false
            }
        }
        // IS-STORY-NAV-001 accessibility
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(story.subject), \(progressInfo.completed) of \(progressInfo.total) tasks complete"
        )
        .accessibilityHint("Navigate to this story")
    }

    private var statusDot: some View {
        Circle()
            .fill(storyStatusColor)
            .frame(width: 8, height: 8)
    }

    private var storyStatusColor: Color {
        // Stories table uses orange for pending (not gray) per design spec Section 5.2
        switch story.status {
        case .completed:  return .green
        case .inProgress: return .blue
        case .pending:    return .orange
        }
    }
}

// MARK: - EpicReferencesCard

private struct EpicReferencesCard: View {
    let references: References

    var body: some View {
        CardView(title: "References", icon: "link", iconColor: .secondary) {
            VStack(alignment: .leading, spacing: 4) {
                if let prd = references.prdStories, !prd.isEmpty {
                    referenceGroup(label: "PRD", items: prd)
                }
                if let tech = references.techSpecSections, !tech.isEmpty {
                    referenceGroup(label: "Tech Spec", items: tech)
                }
                if let data = references.dataSchemaSection, !data.isEmpty {
                    referenceGroup(label: "Data Schema", items: data)
                }
                if let ui = references.uiSpecSections, !ui.isEmpty {
                    referenceGroup(label: "UI Spec", items: ui)
                }
                if let notes = references.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notes")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        Text(notes)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func referenceGroup(label: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            ForEach(items, id: \.self) { item in
                Text("• \(item)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

// MARK: - EpicDependenciesCard

private struct EpicDependenciesCard: View {
    let task: TaskItem

    var body: some View {
        CardView(title: "Dependencies", icon: "arrow.triangle.branch", iconColor: .secondary) {
            VStack(alignment: .leading, spacing: 4) {
                let blocksEpics = task.metadata.epic?.allBlocksEpics ?? []
                if !blocksEpics.isEmpty {
                    dependencyGroup(label: "Blocks Epics", items: blocksEpics, color: .orange)
                }
                let externalDeps = task.metadata.epic?.allExternalDeps ?? []
                if !externalDeps.isEmpty {
                    dependencyGroup(label: "External", items: externalDeps, color: .blue)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func dependencyGroup(label: String, items: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(color)
            ForEach(items, id: \.self) { item in
                Text("• \(item)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

// MARK: - StoryOverviewContent

/// Story overview: stats pills + tasks table + review progress card + AI context card + dependencies.
private struct StoryOverviewContent: View {
    @Environment(DetailViewModel.self) private var viewModel
    @Environment(TreeViewModel.self) private var treeViewModel
    let task: TaskItem

    private var childTasks: [TaskItem] { viewModel.childTasks(of: task) }

    var body: some View {
        // Status & Workflow card (approval, blocked)
        StatusWorkflowCard(task: task)

        // Labels chip row
        if !task.labels.isEmpty {
            LabelsChipRow(labels: task.labels)
        }

        // Tasks table card
        CardView(title: "Tasks", icon: "checklist", iconColor: .blue) {
            if childTasks.isEmpty {
                ContentUnavailableView(
                    "No Tasks",
                    systemImage: "checklist",
                    description: Text("No child tasks found for this story.")
                )
                .padding(.top, 8)
            } else {
                VStack(spacing: 0) {
                    // Table header
                    tasksTableHeader
                        .padding(.bottom, 8)

                    Divider()

                    // Task rows (sorted: in-progress first, pending, completed last)
                    ForEach(sortedTasks) { taskItem in
                        TaskTableRow(taskItem: taskItem) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.navigate(to: taskItem)
                                treeViewModel.revealTask(taskItem.id)
                            }
                        }
                    }
                }
            }
        }

        // Review progress card (always shown for stories)
        ReviewProgressCard(task: task)

        // AI Context card
        if let aiContext = task.metadata.story?.aiContext, !aiContext.isEmpty {
            CardView(title: "AI Context", icon: "sparkles", iconColor: .purple) {
                Text(aiContext)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        // Dependencies card (blockedBy)
        if !task.blockedBy.isEmpty {
            CardView(title: "Dependencies", icon: "arrow.triangle.branch", iconColor: .orange) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(task.blockedBy, id: \.self) { dep in
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                            Text(dep)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }

        // Blocks card — downstream items this story unblocks (SM-DP700-BLOCKS-006)
        BlocksCard(task: task)
    }

    private var tasksTableHeader: some View {
        HStack(spacing: 0) {
            Text("STATUS")
                .frame(width: 60, alignment: .leading)
            Text("TASK")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("TYPE")
                .frame(width: 60, alignment: .trailing)
            Text("PRIORITY")
                .frame(width: 60, alignment: .trailing)
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(.tertiary)
        .textCase(.uppercase)
        .tracking(0.5)
    }

    private var sortedTasks: [TaskItem] {
        // in-progress first, pending second, completed last
        childTasks.sorted { $0.status.sortRank < $1.status.sortRank }
    }
}

// MARK: - ReviewProgressCard

private struct ReviewProgressCard: View {
    let task: TaskItem

    var body: some View {
        CardView(title: "Review Progress", icon: "checkmark.shield", iconColor: .accentColor) {
            VStack(alignment: .leading, spacing: 8) {
                if let reviewStage = task.reviewStage {
                    HStack {
                        Text("Current Stage:")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text(reviewStage.replacingOccurrences(of: "-", with: " ").capitalized)
                            .font(.callout)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                    }
                }

                if let reviewResult = task.reviewResult {
                    HStack {
                        Text("Result:")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text(reviewResult.capitalized)
                            .font(.callout)
                            .fontWeight(.medium)
                            .foregroundStyle(reviewResult == "rejected" ? .red : .primary)
                    }
                }

                if let assignee = task.assignee {
                    HStack(spacing: 6) {
                        Text("Assignee:")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        AgentAvatarView(author: assignee, size: 18)
                        Text(assignee)
                            .font(.callout)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                    }
                }

                if task.reviewStage == nil && task.reviewResult == nil && task.assignee == nil {
                    Text("No review data available.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

// MARK: - TaskOverviewContent

/// Task/Bug/TechDebt overview: stats pills + workflow/status card + labels + parent context +
/// completion signal + checklist + affected files card + files card + blocked-by & assignment.
private struct TaskOverviewContent: View {
    let task: TaskItem

    var body: some View {
        // Status & Workflow card (approval, blocked, review_stage, review_result)
        StatusWorkflowCard(task: task)

        // Labels chip row
        if !task.labels.isEmpty {
            LabelsChipRow(labels: task.labels)
        }

        // Parent context (epic_id / story_id)
        if let storyId = task.metadata.task?.storyId {
            CardView(title: "Parent Story", icon: "doc.text", iconColor: .blue) {
                Text(storyId)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.accentColor)
                    .textSelection(.enabled)
            }
        }

        // Completion Signal & Validation Hint
        let hasSignal = task.metadata.task?.completionSignal != nil
        let hasHint = task.metadata.task?.validationHint != nil
        if hasSignal || hasHint {
            CardView(title: "Completion Criteria", icon: "checkmark.seal", iconColor: .green) {
                VStack(alignment: .leading, spacing: 8) {
                    if let signal = task.metadata.task?.completionSignal {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Done when", systemImage: "flag.checkered")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                            Text(signal)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let hint = task.metadata.task?.validationHint {
                        if hasSignal { Divider() }
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Verify by", systemImage: "magnifyingglass")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                            Text(hint)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }

        // Checklist card (implementation steps)
        if let checklist = task.metadata.task?.checklist, !checklist.isEmpty {
            CardView(title: "Checklist", icon: "checklist", iconColor: .accentColor) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(checklist.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1).")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 20, alignment: .trailing)
                            Text(step)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }

        // AI execution hints
        if let hints = task.metadata.task?.aiExecutionHints, !hints.isEmpty {
            DisclosureGroup(
                content: {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(hints, id: \.self) { hint in
                            Text(hint)
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.top, 6)
                },
                label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.purple)
                        Text("AI Execution Hints")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                }
            )
            .accessibilityLabel("AI Execution Hints, \(hints.count) \(hints.count == 1 ? "hint" : "hints")")
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }

        // Files from task metadata (explicit files list)
        if let files = task.metadata.task?.files, !files.isEmpty {
            CardView(title: "Files", icon: "folder", iconColor: .secondary) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(files, id: \.self) { file in
                        Text(file)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }

        // Dependencies & Assignment side-by-side
        let assignee = task.assignee ?? task.metadata.task?.claimedBy
        let hasBlockedBy = !task.blockedBy.isEmpty
        let hasAssignee = assignee != nil

        if hasBlockedBy || hasAssignee {
            HStack(alignment: .top, spacing: 12) {
                if hasBlockedBy {
                    CardView(
                        title: "Blocked By",
                        icon: "exclamationmark.octagon",
                        iconColor: .orange
                    ) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(task.blockedBy, id: \.self) { dep in
                                Text("• \(dep)")
                                    .font(.callout)
                                    .foregroundStyle(.orange)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                if let resolvedAssignee = assignee {
                    CardView(
                        title: "Assigned To",
                        icon: "person.circle",
                        iconColor: .accentColor
                    ) {
                        HStack(spacing: 8) {
                            AgentAvatarView(author: resolvedAssignee, size: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(resolvedAssignee)
                                    .font(.callout)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.primary)
                                if let claimedAt = task.metadata.task?.claimedAt {
                                    Text(claimedAt, style: .relative)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }

        // Blocks card — downstream items this task unblocks (SM-DP700-BLOCKS-006)
        BlocksCard(task: task)
    }
}

// MARK: - BugOverviewContent

/// Bug overview: severity badge + RCA/regression chips + repro steps + behavior comparison +
/// environment + shared task cards (workflow, labels, criteria, checklist, dependencies, assignment).
///
/// Implements journey J-DP1 and state machine SM-DP700-OVERVIEW-001.
private struct BugOverviewContent: View {
    let task: TaskItem

    private var meta: TaskSpecificMetadata? { task.metadata.task }

    var body: some View {
        // Severity + RCA Status + Regression chips
        SeverityRCACard(meta: meta)

        // Status & Workflow card (approval, blocked, review_stage, review_result)
        StatusWorkflowCard(task: task)

        // Labels chip row
        if !task.labels.isEmpty {
            LabelsChipRow(labels: task.labels)
        }

        // Parent context (story_id)
        if let storyId = meta?.storyId {
            CardView(title: "Parent Story", icon: "doc.text", iconColor: .blue) {
                Text(storyId)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.accentColor)
                    .textSelection(.enabled)
            }
        }

        // Steps to Reproduce
        if let steps = meta?.stepsToReproduce, !steps.isEmpty {
            CardView(title: "Steps to Reproduce", icon: "list.number", iconColor: .orange) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1).")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 20, alignment: .trailing)
                            Text(step)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }

        // Expected vs Actual behavior (side-by-side)
        let hasExpected = meta?.expectedBehavior != nil
        let hasActual = meta?.actualBehavior != nil
        if hasExpected || hasActual {
            HStack(alignment: .top, spacing: 12) {
                if let expected = meta?.expectedBehavior {
                    BehaviorCard(
                        title: "Expected",
                        icon: "checkmark.circle",
                        accentColor: .green,
                        text: expected
                    )
                }
                if let actual = meta?.actualBehavior {
                    BehaviorCard(
                        title: "Actual",
                        icon: "xmark.circle",
                        accentColor: .red,
                        text: actual
                    )
                }
            }
        }

        // Environment card
        if let env = meta?.environment,
           env.macosVersion != nil || env.appVersion != nil {
            CardView(title: "Environment", icon: "laptopcomputer", iconColor: .secondary) {
                VStack(alignment: .leading, spacing: 4) {
                    if let macOS = env.macosVersion {
                        HStack(spacing: 6) {
                            Text("macOS:")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                            Text(macOS)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        }
                    }
                    if let appVersion = env.appVersion {
                        HStack(spacing: 6) {
                            Text("App version:")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                            Text(appVersion)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }

        // Discovered From (source task link)
        if let source = meta?.discoveredFrom {
            CardView(
                title: "Discovered From",
                icon: "arrow.uturn.backward.circle",
                iconColor: .secondary
            ) {
                Text(source)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.accentColor)
                    .textSelection(.enabled)
            }
        }

        // Discovered By (agent name chip)
        if let agent = meta?.discoveredBy {
            CardView(
                title: "Discovered By",
                icon: "person.circle",
                iconColor: .secondary
            ) {
                Text(agent)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
        }

        // Affected Files
        if let files = meta?.affectedFiles, !files.isEmpty {
            CardView(title: "Affected Files", icon: "doc.badge.exclamationmark", iconColor: .red) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(files, id: \.self) { file in
                        Text(file)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }

        // Completion Signal & Validation Hint
        let hasSignal = meta?.completionSignal != nil
        let hasHint = meta?.validationHint != nil
        if hasSignal || hasHint {
            CardView(title: "Completion Criteria", icon: "checkmark.seal", iconColor: .green) {
                VStack(alignment: .leading, spacing: 8) {
                    if let signal = meta?.completionSignal {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Done when", systemImage: "flag.checkered")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                            Text(signal)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let hint = meta?.validationHint {
                        if hasSignal { Divider() }
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Verify by", systemImage: "magnifyingglass")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                            Text(hint)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }

        // Checklist card
        if let checklist = meta?.checklist, !checklist.isEmpty {
            CardView(title: "Checklist", icon: "checklist", iconColor: .accentColor) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(checklist.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1).")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 20, alignment: .trailing)
                            Text(step)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }

        // Dependencies & Assignment side-by-side
        let assignee = task.assignee ?? meta?.claimedBy
        let hasBlockedBy = !task.blockedBy.isEmpty
        let hasAssignee = assignee != nil

        if hasBlockedBy || hasAssignee {
            HStack(alignment: .top, spacing: 12) {
                if hasBlockedBy {
                    CardView(
                        title: "Blocked By",
                        icon: "exclamationmark.octagon",
                        iconColor: .orange
                    ) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(task.blockedBy, id: \.self) { dep in
                                Text("• \(dep)")
                                    .font(.callout)
                                    .foregroundStyle(.orange)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                if let resolvedAssignee = assignee {
                    CardView(
                        title: "Assigned To",
                        icon: "person.circle",
                        iconColor: .accentColor
                    ) {
                        HStack(spacing: 8) {
                            AgentAvatarView(author: resolvedAssignee, size: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(resolvedAssignee)
                                    .font(.callout)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.primary)
                                if let claimedAt = meta?.claimedAt {
                                    Text(claimedAt, style: .relative)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }

        // Blocks card — downstream items this bug unblocks (SM-DP700-BLOCKS-006)
        BlocksCard(task: task)
    }
}

// MARK: - SeverityRCACard

/// Color-coded severity badge, RCA status chip, and optional regression chip for bug items.
private struct SeverityRCACard: View {
    let meta: TaskSpecificMetadata?

    var body: some View {
        let hasSeverity = meta?.severity != nil
        let hasRCA = meta?.rcaStatus != nil
        let isRegression = meta?.regression == true

        if hasSeverity || hasRCA || isRegression {
            CardView(title: "Bug Triage", icon: "ladybug", iconColor: .red) {
                FlowLayout(spacing: 6) {
                    if let severity = meta?.severity {
                        SeverityBadge(severity: severity)
                    }

                    if let rca = meta?.rcaStatus {
                        WorkflowChip(
                            label: "RCA: \(rca.replacingOccurrences(of: "-", with: " ").capitalized)",
                            color: rcaColor(for: rca)
                        )
                    }

                    if isRegression {
                        WorkflowChip(label: "Regression", color: .purple)
                    }
                }
            }
        }
    }

    private func rcaColor(for status: String) -> Color {
        switch status.lowercased() {
        case "approved": return .green
        case "reviewed": return .blue
        case "investigated": return .orange
        case "needs-more-info": return .yellow
        default: return .secondary
        }
    }
}

// MARK: - SeverityBadge

/// Color-coded capsule badge for bug severity level.
private struct SeverityBadge: View {
    let severity: String

    private var color: Color {
        switch severity.lowercased() {
        case "critical": return .red
        case "major", "high": return .orange
        case "moderate", "medium": return .yellow
        case "minor", "low": return .blue
        default: return .secondary
        }
    }

    var body: some View {
        Text(severity.capitalized)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(color.opacity(0.15))
            )
            .overlay(
                Capsule()
                    .strokeBorder(color.opacity(0.35), lineWidth: 0.5)
            )
            .accessibilityLabel("Severity: \(severity)")
    }
}

// MARK: - BehaviorCard

/// A card with a colored left accent bar used for Expected/Actual behavior comparison.
private struct BehaviorCard: View {
    let title: String
    let icon: String
    let accentColor: Color
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(accentColor)
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(accentColor)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()

            // Body text with left accent bar
            HStack(alignment: .top, spacing: 0) {
                Rectangle()
                    .fill(accentColor.opacity(0.5))
                    .frame(width: 3)

                Text(text)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 10)
                    .padding(.trailing, 12)
                    .padding(.vertical, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) behavior: \(text)")
    }
}

// MARK: - StatusWorkflowCard

/// Renders approval, blocked, review_stage, and review_result as colored chips.
/// Shown in TaskOverviewContent, StoryOverviewContent, and EpicOverviewContent.
struct StatusWorkflowCard: View {
    let task: TaskItem

    var body: some View {
        let approval = task.approval
        let isWorkflowBlocked = task.isWorkflowBlocked
        let reviewStage = task.reviewStage
        let reviewResult = task.reviewResult

        let hasAny = approval != nil || isWorkflowBlocked || reviewStage != nil || reviewResult != nil
        if hasAny {
            CardView(title: "Status & Workflow", icon: "gearshape.2", iconColor: .secondary) {
                FlowLayout(spacing: 6) {
                    if let approval {
                        WorkflowChip(
                            label: approval.capitalized,
                            color: approval == "approved" ? .green : .orange
                        )
                    }

                    if isWorkflowBlocked {
                        WorkflowChip(label: "Blocked", color: .red)
                    }

                    if let stage = reviewStage {
                        WorkflowChip(
                            label: stage.replacingOccurrences(of: "-", with: " ").capitalized,
                            color: .blue
                        )
                    }

                    if let result = reviewResult {
                        WorkflowChip(
                            label: result.capitalized,
                            color: result == "rejected" ? .red
                                : result == "passed" ? .green
                                : .secondary
                        )
                    }
                }
            }
        }
    }
}

// MARK: - BlocksCard

/// Reusable card showing items that the current task/story/epic blocks (SM-DP700-BLOCKS-006).
///
/// Each entry in `task.blocks` is resolved against `sessionTasks` by ID.
/// Resolved items are tappable and navigate to that item (IS-STORY-NAV-001 pattern).
/// Unresolved IDs are shown as plain non-interactive text (ERR-DP700-004).
/// The card is omitted entirely when `task.blocks` is empty.
struct BlocksCard: View {
    @Environment(DetailViewModel.self) private var viewModel
    @Environment(TreeViewModel.self) private var treeViewModel
    let task: TaskItem

    var body: some View {
        let resolved = viewModel.resolvedBlocks(of: task)
        if !resolved.isEmpty {
            CardView(title: "Blocks", icon: "arrow.forward.circle", iconColor: .blue) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(resolved, id: \.rawId) { entry in
                        if let item = entry.resolved {
                            BlocksCardRow(item: item) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    viewModel.navigate(to: item)
                                    treeViewModel.revealTask(item.id)
                                }
                            }
                        } else {
                            // Unresolved: raw ID shown as plain text (ERR-DP700-004)
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.forward.circle")
                                    .font(.caption2)
                                    .foregroundStyle(.blue.opacity(0.5))
                                Text(entry.rawId)
                                    .font(.callout)
                                    .foregroundStyle(.tertiary)
                                    .textSelection(.enabled)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - BlocksCardRow

/// A tappable row inside `BlocksCard` for a resolved downstream task item.
///
/// Shows the type icon and subject. Full-row tappable with hover state and hand cursor.
struct BlocksCardRow: View {
    let item: TaskItem
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: item.type.systemImageName)
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .frame(width: 14)

                Text(item.subject)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.secondary.opacity(0.05) : Color.clear)
                    .animation(.easeInOut(duration: 0.12), value: isHovered)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered in
            isHovered = hovered
            if hovered {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onDisappear {
            if isHovered {
                NSCursor.pop()
                isHovered = false
            }
        }
        .accessibilityLabel("\(item.type.displayName): \(item.subject)")
        .accessibilityHint("Navigate to this item")
    }
}

// MARK: - LabelsChipRow

/// Renders a task's labels as a horizontal flow of rounded capsule chips.
struct LabelsChipRow: View {
    let labels: [String]

    var body: some View {
        CardView(title: "Labels", icon: "tag", iconColor: .secondary) {
            FlowLayout(spacing: 6) {
                ForEach(labels, id: \.self) { label in
                    Text(label)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.secondary.opacity(0.12))
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5)
                        )
                }
            }
        }
    }
}

// MARK: - WorkflowChip

/// A small colored capsule chip used in StatusWorkflowCard.
struct WorkflowChip: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .strokeBorder(color.opacity(0.25), lineWidth: 0.5)
            )
    }
}

// MARK: - TaskStatus Sort Rank

private extension TaskStatus {
    /// Sort rank for status-based ordering: in-progress first, pending second, completed last.
    ///
    /// Used by `EpicOverviewContent.sortedStories` and `StoryOverviewContent.sortedTasks`
    /// to avoid duplicating the same switch statement in two places.
    var sortRank: Int {
        switch self {
        case .inProgress: return 0
        case .pending:    return 1
        case .completed:  return 2
        }
    }
}
