import Foundation

/// A lightweight reference to a task, embedded in a story's metadata.
struct TaskReference: Codable, Identifiable {
    let id: String
    let displayId: String?
    let title: String?
    let status: String?
    let hours: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case claudeTaskId = "claude_task_id"
        case taskId = "task_id"
        case title
        case subject
        case status
        case hours
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Resilient ID: tries id, claude_task_id, task_id (String or Int), UUID fallback
        id = decodeResilientID(
            from: container,
            primaryKey: .id,
            fallbackKeys: [.claudeTaskId, .taskId]
        )

        // displayId from task_id field (e.g. "CASHFLOW-705-1")
        if let stringTaskId = try? container.decode(String.self, forKey: .taskId) {
            displayId = stringTaskId
        } else if let intTaskId = try? container.decode(Int.self, forKey: .taskId) {
            displayId = String(intTaskId)
        } else {
            displayId = nil
        }

        // Resilient title: tries title, falls back to subject
        if let titleValue = try? container.decode(String.self, forKey: .title) {
            title = titleValue
        } else {
            title = try? container.decode(String.self, forKey: .subject)
        }

        status = try? container.decode(String.self, forKey: .status)

        // Resilient hours: Int or String
        if let intHours = try? container.decode(Int.self, forKey: .hours) {
            hours = intHours
        } else if let stringHours = try? container.decode(String.self, forKey: .hours) {
            hours = Int(stringHours)
        } else {
            hours = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(displayId, forKey: .taskId)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(hours, forKey: .hours)
    }
}
