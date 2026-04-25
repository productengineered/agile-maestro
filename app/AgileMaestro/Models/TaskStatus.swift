import Foundation

/// Status of a Claude Code task item.
/// Resilient to both snake_case ("in_progress") and camelCase ("inProgress") raw values.
enum TaskStatus: String, Codable, CaseIterable {
    case pending = "pending"
    case inProgress = "in_progress"
    case completed = "completed"

    // MARK: - Codable

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        switch rawValue.lowercased() {
        case "pending":
            self = .pending
        case "in_progress", "inprogress":
            self = .inProgress
        case "completed", "done", "closed":
            self = .completed
        default:
            // Unknown values default to pending rather than throwing
            self = .pending
        }
    }

    // MARK: - Display

    var displayName: String {
        switch self {
        case .pending:    return "Pending"
        case .inProgress: return "In Progress"
        case .completed:  return "Completed"
        }
    }
}
