import Foundation

// MARK: - KanbanProgress

/// Progress information for an epic or story card on the Kanban board.
struct KanbanProgress {
    let completed: Int
    let total: Int
    let unit: String

    /// Count of bugs/techdebt attached directly to an epic (not counted in
    /// `total`/`unit`, which represent story progress only). Zero for story
    /// cards, and for epics with no directly-linked bugs/techdebt.
    let linkedCount: Int

    init(completed: Int, total: Int, unit: String, linkedCount: Int = 0) {
        self.completed = completed
        self.total = total
        self.unit = unit
        self.linkedCount = linkedCount
    }
}

// MARK: - KanbanCard

/// A card displayed on the Kanban board, wrapping a `TaskItem`.
struct KanbanCard: Identifiable {
    let id: String
    let type: TaskType
    let displayId: String?
    let title: String
    let labels: [String]
    let blocked: Bool
    let reviewResult: String?
    let progress: KanbanProgress?
    let completedAt: Date?
    var epicDisplayId: String?
    var column: String
    let taskItem: TaskItem
}

// MARK: - UAT Tier-2 Exposure

extension KanbanCard {

    /// The most recent Tier-2 agent UAT result for this card's underlying task, mirroring
    /// how `reviewResult` is exposed above. Sourced from `taskItem.uatTier2` (computed, not
    /// stored) so this stays in sync without a `KanbanViewModel.makeCard` change.
    ///
    /// `nil` for non-epic cards, or epics with no Tier-2 pass recorded yet.
    var uatTier2: UATTier2Metadata? {
        taskItem.uatTier2
    }
}

// MARK: - KanbanColumnDef

/// Definition of a column on the Kanban board.
struct KanbanColumnDef: Identifiable {
    let id: String
    let label: String
    let dotColor: String

    // MARK: - Static Column Definitions

    /// All 10 Kanban columns in display order.
    /// R1.1: "agent_uat" inserted between "product_review" and "human_uat".
    static let allColumns: [KanbanColumnDef] = [
        KanbanColumnDef(id: "backlog", label: "Backlog", dotColor: "gray"),
        KanbanColumnDef(id: "approved", label: "Approved", dotColor: "blue"),
        KanbanColumnDef(id: "in_dev", label: "In Dev", dotColor: "orange"),
        KanbanColumnDef(id: "code_review", label: "Code Review", dotColor: "purple"),
        KanbanColumnDef(id: "qa", label: "QA", dotColor: "yellow"),
        KanbanColumnDef(id: "security", label: "Security", dotColor: "red"),
        KanbanColumnDef(id: "product_review", label: "Product Review", dotColor: "indigo"),
        KanbanColumnDef(id: "agent_uat", label: "Agent UAT", dotColor: "teal"),
        KanbanColumnDef(id: "human_uat", label: "Human UAT", dotColor: "pink"),
        KanbanColumnDef(id: "done", label: "Done", dotColor: "green")
    ]

    // MARK: - Visibility

    /// Filters `allColumns` down to the columns visible for the current data set.
    ///
    /// Security, Agent UAT, and Human UAT columns are epic-gated: they only appear
    /// once at least one epic card exists in the session. All other columns are
    /// always visible.
    static func visibleColumns(hasEpicCards: Bool) -> [KanbanColumnDef] {
        allColumns.filter { column in
            switch column.id {
            case "security", "agent_uat", "human_uat":
                return hasEpicCards
            default:
                return true
            }
        }
    }
}

// MARK: - KanbanTypeFilter

/// Filter for displaying specific task types on the Kanban board.
enum KanbanTypeFilter: String, CaseIterable {
    case all
    case epic
    case story
    case task
    case bug
    case techdebt

    var label: String {
        switch self {
        case .all: return "All"
        case .epic: return "Epics"
        case .story: return "Stories"
        case .task: return "Tasks"
        case .bug: return "Bugs"
        case .techdebt: return "Tech Debt"
        }
    }
}
