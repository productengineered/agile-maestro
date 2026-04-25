import Foundation
import Observation

// MARK: - DetailTab

/// The active tab shown in the detail panel.
///
/// Each case corresponds to a content facet of a task item. The set of
/// available tabs varies by `TaskType` — see `availableTabs(for:)`.
///
/// Implements `SM-DETAIL-001` tab availability matrix from UX Flows Section 1:
/// - Epic:     overview, description, criteria, planning, comments
/// - Story:    overview, description, criteria, constraints, comments
/// - Task:     overview, description, checklist, verification, comments
/// - Bug:      overview, description, comments
/// - TechDebt: overview, description, comments
enum DetailTab: String, CaseIterable, Identifiable {
    case overview
    case description
    case criteria
    case planning
    case constraints
    case checklist
    case verification
    case comments

    var id: String { rawValue }

    // MARK: - Display

    var label: String {
        switch self {
        case .overview:     return "Overview"
        case .description:  return "Description"
        case .criteria:     return "Criteria"
        case .planning:     return "Planning"
        case .constraints:  return "Constraints"
        case .checklist:    return "Checklist"
        case .verification: return "Verification"
        case .comments:     return "Comments"
        }
    }

    var icon: String {
        switch self {
        case .overview:     return "square.grid.2x2"
        case .description:  return "doc.text"
        case .criteria:     return "checkmark.shield"
        case .planning:     return "calendar"
        case .constraints:  return "exclamationmark.triangle"
        case .checklist:    return "checklist"
        case .verification: return "shield.checkered"
        case .comments:     return "text.bubble"
        }
    }

    // MARK: - Tab Availability Matrix (SM-DETAIL-001)

    /// Returns the ordered list of tabs available for the given task type.
    ///
    /// This is the authoritative tab availability matrix from UX Flows Section 1:
    /// - Epic:     5 tabs (overview, description, criteria, planning, comments)
    /// - Story:    5 tabs (overview, description, criteria, constraints, comments)
    /// - Task:     5 tabs (overview, description, checklist, verification, comments)
    /// - Bug:      3 tabs (overview, description, comments)
    /// - TechDebt: 3 tabs (overview, description, comments)
    static func availableTabs(for type: TaskType) -> [DetailTab] {
        switch type {
        case .epic:     return [.overview, .description, .criteria, .planning, .comments]
        case .story:    return [.overview, .description, .criteria, .constraints, .comments]
        case .task:     return [.overview, .description, .checklist, .verification, .comments]
        case .bug:      return [.overview, .description, .comments]
        case .techdebt: return [.overview, .description, .comments]
        }
    }
}

// MARK: - BreadcrumbSegment

/// A resolved segment in the breadcrumb trail shown in `DetailHeaderView`.
///
/// Segments are computed by `DetailViewModel.breadcrumbSegments(for:)` by
/// walking the `parentId` chain through the session's task list.
struct BreadcrumbSegment {
    let taskItem: TaskItem
    let displayTitle: String
}

// MARK: - DetailViewModel

/// Central state object for the task detail panel.
///
/// Manages:
/// - `selectedTask` — the item whose details are displayed.
/// - `activeTab` — the currently visible content tab.
/// - Auto-reset logic (SM-DETAIL-001): when `selectedTask` changes to an item
///   whose type does not include the current `activeTab`, the tab resets to `.overview`.
/// - Breadcrumb resolution: walks `parentId` chains through `sessionTasks`.
///
/// Observers inject this object via SwiftUI `@Environment(DetailViewModel.self)`.
@Observable
@MainActor
final class DetailViewModel {

    // MARK: - State

    /// The task item currently shown in the detail panel.
    ///
    /// Setting this value triggers SM-DETAIL-001 auto-reset: if the new item's
    /// type does not include `activeTab`, `activeTab` resets to `.overview`.
    private(set) var selectedTask: TaskItem?

    /// The currently visible tab.
    ///
    /// Read by `DetailTabsView` for selection state. Written directly by tab pills
    /// (`viewModel.activeTab = tab`). Also written internally during task changes.
    var activeTab: DetailTab = .overview

    /// The full session task list used for breadcrumb and parent resolution.
    ///
    /// Updated by the coordinator (e.g., `MainWindowView`) when `SessionViewModel.tasks`
    /// changes. Not observed independently — callers drive updates via `setTask(_:tasks:)`.
    var sessionTasks: [TaskItem] = []

    // MARK: - Init

    init() {}

    // MARK: - Task Selection (SM-DETAIL-001)

    /// Sets the selected task and auto-resets `activeTab` if necessary.
    ///
    /// If the new task's type does not include the current `activeTab` in
    /// `DetailTab.availableTabs(for:)`, `activeTab` resets to `.overview`.
    ///
    /// - Parameters:
    ///   - task: The task to select, or `nil` to clear the detail panel.
    ///   - tasks: Updated session task list for breadcrumb resolution. Pass `nil`
    ///            to keep the existing `sessionTasks`.
    func setTask(_ task: TaskItem?, tasks: [TaskItem]? = nil) {
        if let tasks {
            sessionTasks = tasks
        }

        selectedTask = task

        guard let task else { return }

        // SM-DETAIL-001: auto-reset tab when the current tab is not available
        // for the new type. If the tab remains valid, preserve it.
        let available = DetailTab.availableTabs(for: task.type)
        if !available.contains(activeTab) {
            activeTab = .overview
        }
    }

    // MARK: - Breadcrumb Resolution (SM-BREADCRUMB-001)

    /// Resolves the ordered breadcrumb trail for the given task.
    ///
    /// Walks the `parentId` chain through `sessionTasks`. The result is ordered
    /// from the root ancestor down to the current task (inclusive):
    ///
    ///     [Epic] > [Story] > [Task]   → 3 segments
    ///     [Epic] > [Story]            → 2 segments
    ///     [Epic]                      → 1 segment
    ///
    /// Orphan tasks (no parent found in `sessionTasks`) return a single segment
    /// containing only the current task.
    ///
    /// - Parameter task: The task whose breadcrumb to resolve.
    /// - Returns: Ordered array of `BreadcrumbSegment` from root to current.
    func breadcrumbSegments(for task: TaskItem) -> [BreadcrumbSegment] {
        var segments: [BreadcrumbSegment] = []
        var current: TaskItem? = task
        var visited: Set<String> = []

        // Walk up the parent chain, guarding against cycles.
        while let item = current {
            guard !visited.contains(item.id) else { break }
            visited.insert(item.id)

            segments.insert(
                BreadcrumbSegment(
                    taskItem: item,
                    displayTitle: truncated(item.subject, maxLength: 30)
                ),
                at: 0
            )

            guard let parentId = item.resolvedParentId(in: sessionTasks) else { break }
            current = sessionTasks.first(where: { $0.id == parentId })
        }

        return segments
    }

    // MARK: - Navigation

    /// Navigates the detail panel to the given task item.
    ///
    /// Equivalent to calling `setTask(_:)` with the target item. Used by
    /// tappable breadcrumb segments in `DetailHeaderView`.
    ///
    /// - Parameter task: The task to navigate to.
    func navigate(to task: TaskItem) {
        setTask(task)
    }

    // MARK: - OverviewTabView Helpers

    /// Returns all direct child stories of the given epic.
    ///
    /// A story is a child when its `parentId` matches the epic's `id` and its type is `.story`.
    /// Used by `EpicOverviewContent` to populate the stories table.
    func childStories(of epic: TaskItem) -> [TaskItem] {
        sessionTasks.filter { $0.resolvedParentId(in: sessionTasks) == epic.id && $0.type == .story }
    }

    /// Returns all direct child tasks of the given story.
    ///
    /// A task is a child when its resolved parent ID matches the story's `id` and its type is
    /// a leaf task type (task, bug, or techdebt). Used by `StoryOverviewContent` to populate the tasks table.
    func childTasks(of story: TaskItem) -> [TaskItem] {
        sessionTasks.filter { $0.resolvedParentId(in: sessionTasks) == story.id && $0.isTask }
    }

    /// Returns the total number of leaf tasks across all child stories of an epic.
    ///
    /// Counts tasks, bugs, and techdebt items whose resolved parent ID matches any child story's id.
    func totalTaskCount(for epic: TaskItem) -> Int {
        let storyIds = Set(childStories(of: epic).map(\.id))
        return sessionTasks.filter { item in
            guard let parentId = item.resolvedParentId(in: sessionTasks) else { return false }
            return storyIds.contains(parentId) && item.isTask
        }.count
    }

    /// Returns the task completion progress for a story.
    ///
    /// - Returns: A tuple `(completed: Int, total: Int)` where `completed` is the number of
    ///   tasks with `.completed` status and `total` is all tasks under this story.
    func taskProgress(for story: TaskItem) -> (completed: Int, total: Int) {
        let tasks = sessionTasks.filter { item in
            guard let parentId = item.resolvedParentId(in: sessionTasks) else { return false }
            return parentId == story.id && item.isTask
        }
        let completed = tasks.filter { $0.status == .completed }.count
        return (completed: completed, total: tasks.count)
    }

    // MARK: - Blocks Resolution

    /// Resolves the `blocks` array of a task item into matched `TaskItem` instances.
    ///
    /// Each string in `task.blocks` is matched against `sessionTasks` by `id` (UUID string)
    /// or `displayId` (human-readable ID like "task-42"). Subject matching is not performed.
    /// Unmatched IDs are returned as `nil` entries paired with their raw string so the view
    /// can display them as plain text (ERR-DP700-004).
    ///
    /// - Parameter task: The task item whose `blocks` array to resolve.
    /// - Returns: An ordered array of `(rawId: String, resolved: TaskItem?)` tuples.
    func resolvedBlocks(of task: TaskItem) -> [(rawId: String, resolved: TaskItem?)] {
        task.blocks.map { rawId in
            let match = sessionTasks.first(where: { item in
                item.id == rawId || item.displayId == rawId
            })
            return (rawId: rawId, resolved: match)
        }
    }

    // MARK: - Header Metadata Helpers (SM-DP700-HEADER-004)

    /// Returns the agent name that has claimed the given task.
    ///
    /// Checks `task.metadata.task.claimedBy`, then `task.metadata.task.assignee`,
    /// then `task.metadata.story.claimedBy`, then `task.metadata.epic.claimedBy`
    /// as fallbacks.
    func resolvedClaimedBy(for task: TaskItem) -> String? {
        task.metadata.task?.claimedBy
            ?? task.metadata.task?.assignee
            ?? task.metadata.story?.claimedBy
            ?? task.metadata.epic?.claimedBy
    }

    /// Returns the last-updated date for the given task, checking task, story, and
    /// epic metadata paths in order.
    func resolvedLastUpdatedAt(for task: TaskItem) -> Date? {
        task.metadata.task?.lastUpdatedAt
            ?? task.metadata.story?.lastUpdatedAt
            ?? task.metadata.epic?.lastUpdatedAt
    }

    /// Returns the creation date for the given task, checking task and top-level
    /// metadata paths in order.
    func resolvedCreatedAt(for task: TaskItem) -> Date? {
        task.metadata.task?.createdAt
            ?? task.metadata.createdAt
    }

    /// Strips the `-agent` suffix from a raw agent identifier string.
    ///
    /// Converts identifiers like `"macos-developer-agent"` to `"macos-developer"`
    /// for display in the UI. Only removes the suffix when it appears at the end
    /// of the string, so identifiers like `"my-agent-service"` are left unchanged.
    func formattedAgentName(_ raw: String) -> String {
        let suffix = "-agent"
        return raw.hasSuffix(suffix) ? String(raw.dropLast(suffix.count)) : raw
    }

    /// Formats a `Date` as a medium-style absolute date/time string for accessibility labels.
    func absoluteDate(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - Helpers

    private func truncated(_ string: String, maxLength: Int) -> String {
        guard string.count > maxLength else { return string }
        return String(string.prefix(maxLength)) + "…"
    }
}
