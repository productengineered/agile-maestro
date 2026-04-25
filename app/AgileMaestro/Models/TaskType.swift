import Foundation

/// The type of a Claude Code task item (epic, story, task, bug, or techdebt).
enum TaskType: String, Codable, CaseIterable {
    case epic
    case story
    case task
    case bug
    case techdebt

    // MARK: - Codable

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        switch rawValue.lowercased() {
        case "epic":
            self = .epic
        case "story":
            self = .story
        case "task":
            self = .task
        case "bug":
            self = .bug
        case "techdebt", "tech_debt", "tech-debt":
            self = .techdebt
        default:
            // Unknown types default to task
            self = .task
        }
    }

    // MARK: - Display

    var displayName: String {
        switch self {
        case .epic:     return "Epic"
        case .story:    return "Story"
        case .task:     return "Task"
        case .bug:      return "Bug"
        case .techdebt: return "Tech Debt"
        }
    }

    var systemImageName: String {
        switch self {
        case .epic:     return "flag.fill"
        case .story:    return "book.fill"
        case .task:     return "checkmark.circle"
        case .bug:      return "ant.fill"
        case .techdebt: return "wrench.fill"
        }
    }

    /// SF Symbol name used in the tree sidebar (per UI-SPEC 2.6).
    /// Kept separate from `systemImageName` so other usages are not affected.
    var treeIconName: String {
        switch self {
        case .epic:     return "mountain.2.fill"
        case .story:    return "book.fill"
        case .task:     return "checklist"
        case .bug:      return "ladybug.fill"
        case .techdebt: return "wrench.and.screwdriver.fill"
        }
    }
}
