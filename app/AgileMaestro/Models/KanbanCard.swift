import Foundation

// MARK: - KanbanProgress

/// Progress information for an epic or story card on the Kanban board.
struct KanbanProgress {
    let completed: Int
    let total: Int
    let unit: String
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

// MARK: - KanbanColumnDef

/// Definition of a column on the Kanban board.
struct KanbanColumnDef: Identifiable {
    let id: String
    let label: String
    let dotColor: String

    // MARK: - Static Column Definitions

    /// All 9 Kanban columns in display order.
    static let allColumns: [KanbanColumnDef] = [
        KanbanColumnDef(id: "backlog", label: "Backlog", dotColor: "gray"),
        KanbanColumnDef(id: "approved", label: "Approved", dotColor: "blue"),
        KanbanColumnDef(id: "in_dev", label: "In Dev", dotColor: "orange"),
        KanbanColumnDef(id: "code_review", label: "Code Review", dotColor: "purple"),
        KanbanColumnDef(id: "qa", label: "QA", dotColor: "yellow"),
        KanbanColumnDef(id: "security", label: "Security", dotColor: "red"),
        KanbanColumnDef(id: "product_review", label: "Product Review", dotColor: "indigo"),
        KanbanColumnDef(id: "human_uat", label: "Human UAT", dotColor: "pink"),
        KanbanColumnDef(id: "done", label: "Done", dotColor: "green")
    ]
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
