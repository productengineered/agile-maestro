import Foundation
import Observation

// MARK: - KanbanViewModel

/// ViewModel for the Kanban board view.
///
/// Transforms a flat array of `TaskItem` values into `KanbanCard` values grouped
/// by workflow stage column. Exposes filtering and sorting for `KanbanBoardView`
/// and `KanbanFilterBarView`.
///
/// Column assignment rules (FR-4.2):
///   - completed                                         → "done"
///   - review_stage "code-review" + awaiting             → "code_review"
///   - review_stage "qa" + awaiting                      → "qa"
///   - review_stage "security" + awaiting                → "security"
///   - review_stage "product-review" + awaiting          → "product_review"
///   - review_stage "human-uat" + awaiting               → "human_uat"
///   - in_progress (no active review)                    → "in_dev"
///   - pending + approval "approved"                     → "approved"
///   - pending (no approval)                             → "backlog"
///
/// Sorting rules (FR-4.3):
///   - Non-done columns: type priority → rejected → blocked → title
///   - Done column: completedAt (lastUpdatedAt proxy) descending, nil at bottom
@Observable
@MainActor
final class KanbanViewModel {

    deinit {}

    // MARK: - State

    /// All Kanban cards built from the last `setTasks(_:)` call, sorted per column.
    private(set) var allCards: [KanbanCard] = []

    /// The active type filter for the Kanban board.
    var typeFilter: KanbanTypeFilter = .all

    /// The active epic ID filter. `nil` means no epic filter (show all).
    var epicFilter: String?

    // MARK: - Computed: Filtering

    /// Cards filtered by `typeFilter` (if not `.all`) AND `epicFilter` (if not `nil`).
    ///
    /// Both conditions apply with AND logic. Returns `allCards` unchanged when
    /// both filters are inactive.
    var filteredCards: [KanbanCard] {
        allCards.filter { card in
            let typeMatch: Bool
            if typeFilter == .all {
                typeMatch = true
            } else {
                typeMatch = card.type == typeFilterToTaskType(typeFilter)
            }

            let epicMatch: Bool
            if let epicId = epicFilter {
                epicMatch = card.epicDisplayId == epicId
            } else {
                epicMatch = true
            }

            return typeMatch && epicMatch
        }
    }

    /// Number of cards that pass the current filters.
    var filteredCount: Int { filteredCards.count }

    /// Unique, sorted epic display IDs from `allCards` where `epicDisplayId` is non-nil.
    ///
    /// Used to populate the epic filter dropdown in `KanbanFilterBarView`.
    var availableEpicIDs: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for card in allCards {
            if let epicDisplayId = card.epicDisplayId, seen.insert(epicDisplayId).inserted {
                result.append(epicDisplayId)
            }
        }
        return result.sorted()
    }

    // MARK: - Init

    init() {}

    // MARK: - Public Methods

    /// Rebuilds `allCards` from the provided task array.
    ///
    /// Each task is mapped to a `KanbanCard` with its column assigned based on
    /// workflow state. Cards inherit `epicDisplayId` from parent tasks via cascade.
    /// Cards are sorted globally (by column order, then within-column rules).
    ///
    /// - Parameter tasks: Flat array of all `TaskItem` values from `SessionViewModel`.
    func setTasks(_ tasks: [TaskItem]) {
        guard !tasks.isEmpty else {
            allCards = []
            epicFilter = nil
            return
        }

        // 1. Build a lookup for fast parent access
        let taskLookup = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })

        // 1b. Precompute resolved parent IDs in a single O(n) pass.
        //     Keyed by task.id; value is the resolved parent's task-file ID (or nil).
        //     Replaces per-call O(n) scans via resolvedParentId(in:) throughout this method.
        let resolvedParentMap: [String: String?] = Dictionary(
            uniqueKeysWithValues: tasks.map { task in
                (task.id, task.resolvedParentId(in: tasks))
            }
        )

        // 2. Map each task to a KanbanCard
        var cards = tasks.map { task in
            makeCard(from: task, taskLookup: taskLookup, resolvedParentMap: resolvedParentMap)
        }

        // 2b. Blocked-parent cascade: if a card is in "in_dev" but its parent
        //     story is blocked (metadata.blocked == true), move it back to
        //     "approved" — the work cannot proceed while the parent is blocked.
        for index in cards.indices {
            guard cards[index].column == "in_dev" else { continue }
            let task = tasks[index]
            if let parentId = resolvedParentMap[task.id].flatMap({ $0 }),
               let parentTask = taskLookup[parentId],
               parentTask.isWorkflowBlocked {
                cards[index].column = "approved"
            }
        }

        // 3. Sort globally (column order first, then within-column rules)
        cards.sort { lhs, rhs in
            let lhsOrder = columnSortOrder(lhs.column)
            let rhsOrder = columnSortOrder(rhs.column)
            if lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }
            return sortWithinColumn(lhs, rhs, isDoneColumn: lhs.column == "done")
        }

        allCards = cards

        // Clear epicFilter if the filtered epic no longer exists in the new data.
        // Prevents an empty board after session switch when the previous filter
        // referenced an epic that is not present in the refreshed task set.
        if let currentFilter = epicFilter, !availableEpicIDs.contains(currentFilter) {
            epicFilter = nil
        }
    }

    /// Returns filtered + sorted cards for a specific column.
    ///
    /// Partitions `filteredCards` to the given column. Cards are already sorted
    /// from `setTasks`; this method only filters by column.
    ///
    /// - Parameter columnId: The column identifier (e.g. `"backlog"`, `"done"`).
    /// - Returns: Cards in `filteredCards` belonging to `columnId`, in sorted order.
    func cards(for columnId: String) -> [KanbanCard] {
        filteredCards.filter { $0.column == columnId }
    }

    // MARK: - Private: Card Construction

    private func makeCard(
        from task: TaskItem,
        taskLookup: [String: TaskItem],
        resolvedParentMap: [String: String?]
    ) -> KanbanCard {
        let column = assignColumn(for: task)
        let epicId = resolveEpicId(for: task, lookup: taskLookup, resolvedParentMap: resolvedParentMap)
        let completedAt = resolveCompletedAt(for: task)

        return KanbanCard(
            id: task.id,
            type: task.type,
            displayId: task.displayId,
            title: task.subject,
            labels: task.labels,
            blocked: task.isWorkflowBlocked || task.isBlocked,
            reviewResult: task.reviewResult,
            progress: makeProgress(for: task, taskLookup: taskLookup, resolvedParentMap: resolvedParentMap),
            completedAt: completedAt,
            epicDisplayId: epicId,
            column: column,
            taskItem: task
        )
    }

    /// Assigns a column ID based on the task's workflow state.
    ///
    /// Review-stage items override the base assignment only when the task is
    /// `.pending` and awaiting review.
    private func assignColumn(for task: TaskItem) -> String {
        if task.status == .completed {
            return "done"
        }

        if let reviewColumn = reviewStageColumn(for: task) {
            return reviewColumn
        }

        switch task.status {
        case .inProgress:
            return "in_dev"
        case .pending:
            return task.approval == "approved" ? "approved" : "backlog"
        case .completed:
            return "done"
        }
    }

    /// Returns a column ID if the task has an active review stage, otherwise `nil`.
    private func reviewStageColumn(for task: TaskItem) -> String? {
        guard let reviewStage = task.reviewStage,
              task.reviewResult == "awaiting" else { return nil }
        switch reviewStage {
        case "code-review":     return "code_review"
        case "qa":              return "qa"
        case "security":        return "security"
        case "product-review":  return "product_review"
        case "human-uat":       return "human_uat"
        default:                return nil
        }
    }

    // MARK: - Private: Epic ID Cascade

    /// Resolves the epic display ID for a card by walking up the parent chain.
    ///
    /// Always returns the human-readable display ID (e.g. "AM-400") rather than the
    /// internal task file ID (e.g. "106"). Falls back to `task.id` only when
    /// `displayId` is nil, which should not occur for well-formed epics.
    ///
    /// - Epics: use their own `displayId`.
    /// - Stories: look at parent's displayId if it's an epic.
    /// - Tasks/Bugs/TechDebt: walk story → epic.
    private func resolveEpicId(
        for task: TaskItem,
        lookup: [String: TaskItem],
        resolvedParentMap: [String: String?]
    ) -> String? {
        if task.type == .epic {
            return task.displayId ?? task.id
        }

        guard let parentId = resolvedParentMap[task.id].flatMap({ $0 }),
              let parent = lookup[parentId] else {
            return nil
        }

        if parent.type == .epic {
            return parent.displayId ?? parent.id
        }

        // Grandparent (task → story → epic)
        if let grandparentId = resolvedParentMap[parent.id].flatMap({ $0 }),
           let grandparent = lookup[grandparentId],
           grandparent.type == .epic {
            return grandparent.displayId ?? grandparent.id
        }

        return nil
    }

    // MARK: - Private: Progress

    /// Builds a `KanbanProgress` for epics and stories (child task counts).
    private func makeProgress(
        for task: TaskItem,
        taskLookup: [String: TaskItem],
        resolvedParentMap: [String: String?]
    ) -> KanbanProgress? {
        guard task.type == .epic || task.type == .story else { return nil }

        // Collect children using the precomputed map (O(n) over all tasks once,
        // not O(n²) via resolvedParentId per child).
        let children = resolvedParentMap.compactMap { childId, parentId -> TaskItem? in
            guard parentId == task.id else { return nil }
            return taskLookup[childId]
        }
        guard !children.isEmpty else { return nil }

        let completed = children.filter { $0.status == .completed }.count
        let unit = task.type == .epic ? "stories" : "tasks"
        return KanbanProgress(completed: completed, total: children.count, unit: unit)
    }

    // MARK: - Private: CompletedAt

    /// Resolves a completion timestamp using `lastUpdatedAt` as a proxy.
    ///
    /// The task model does not have a dedicated `completedAt` field. For done-column
    /// sorting purposes, `lastUpdatedAt` from the type-specific metadata is the
    /// closest available signal.
    private func resolveCompletedAt(for task: TaskItem) -> Date? {
        guard task.status == .completed else { return nil }

        switch task.type {
        case .epic:
            return task.metadata.epic?.lastUpdatedAt
        case .story:
            return task.metadata.story?.lastUpdatedAt
        case .task, .bug, .techdebt:
            return task.metadata.task?.lastUpdatedAt
        }
    }

    // MARK: - Private: Sorting

    /// Type priority for within-column sort (lower = higher priority).
    private func typePriority(_ type: TaskType) -> Int {
        switch type {
        case .epic:     return 0
        case .story:    return 1
        case .bug:      return 2
        case .techdebt: return 3
        case .task:     return 4
        }
    }

    /// Sort comparator for within-column ordering.
    ///
    /// Non-done columns: type priority → rejected → blocked → title (alphabetical).
    /// Done column: completedAt descending (most recent first), nil at bottom.
    private func sortWithinColumn(
        _ lhs: KanbanCard,
        _ rhs: KanbanCard,
        isDoneColumn: Bool
    ) -> Bool {
        if isDoneColumn {
            switch (lhs.completedAt, rhs.completedAt) {
            case (.some(let lhsDate), .some(let rhsDate)):
                return lhsDate > rhsDate
            case (.some, .none):
                return true    // Has date sorts before nil
            case (.none, .some):
                return false   // nil sorts to bottom
            case (.none, .none):
                return lhs.title < rhs.title
            }
        }

        // Type priority (epic > story > bug > techdebt > task)
        let lhsPriority = typePriority(lhs.type)
        let rhsPriority = typePriority(rhs.type)
        if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }

        // Rejected items need attention — float to top
        let lhsRejected = lhs.reviewResult == "rejected"
        let rhsRejected = rhs.reviewResult == "rejected"
        if lhsRejected != rhsRejected { return lhsRejected }

        // Blocked items need attention — float to top
        if lhs.blocked != rhs.blocked { return lhs.blocked }

        // Stable tiebreaker: alphabetical subject
        return lhs.title < rhs.title
    }

    /// Numeric sort order for column IDs (used to group allCards by column position).
    private func columnSortOrder(_ columnId: String) -> Int {
        switch columnId {
        case "backlog":         return 0
        case "approved":        return 1
        case "in_dev":          return 2
        case "code_review":     return 3
        case "qa":              return 4
        case "security":        return 5
        case "product_review":  return 6
        case "human_uat":       return 7
        case "done":            return 8
        default:                return 9
        }
    }

    // MARK: - Private: Helpers

    /// Converts `KanbanTypeFilter` to `TaskType` for filtering.
    ///
    /// Note: `.all` should be handled by the caller before invoking this method.
    private func typeFilterToTaskType(_ filter: KanbanTypeFilter) -> TaskType {
        switch filter {
        case .all:      return .task  // .all is handled before this call
        case .epic:     return .epic
        case .story:    return .story
        case .task:     return .task
        case .bug:      return .bug
        case .techdebt: return .techdebt
        }
    }
}
