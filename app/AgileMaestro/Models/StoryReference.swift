import Foundation

/// A lightweight reference to a story, embedded in an epic's metadata.
struct StoryReference: Codable, Identifiable {
    let id: String
    let taskId: String?
    let title: String?
    let description: String?
    let status: String?
    let points: Int?
    let hours: Double?
    let tasks: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case claudeTaskId = "claude_task_id"
        case taskId = "task_id"
        case storyId = "story_id"
        case title
        case subject
        case description
        case status
        case points
        case hours
        case tasks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Resilient ID: tries id, claude_task_id, story_id (String or Int), UUID fallback
        id = decodeResilientID(
            from: container,
            primaryKey: .id,
            fallbackKeys: [.claudeTaskId, .storyId, .taskId]
        )

        // Resilient taskId: tries task_id (String/Int), falls back to story_id
        if let stringTaskId = try? container.decode(String.self, forKey: .taskId) {
            taskId = stringTaskId
        } else if let intTaskId = try? container.decode(Int.self, forKey: .taskId) {
            taskId = String(intTaskId)
        } else if let stringStoryId = try? container.decode(String.self, forKey: .storyId) {
            taskId = stringStoryId
        } else {
            taskId = nil
        }

        // Resilient title: tries title, falls back to subject
        if let titleValue = try? container.decode(String.self, forKey: .title) {
            title = titleValue
        } else {
            title = try? container.decode(String.self, forKey: .subject)
        }

        description = try? container.decode(String.self, forKey: .description)
        status = try? container.decode(String.self, forKey: .status)

        // Resilient points: Int or String
        if let intPoints = try? container.decode(Int.self, forKey: .points) {
            points = intPoints
        } else if let stringPoints = try? container.decode(String.self, forKey: .points) {
            points = Int(stringPoints)
        } else {
            points = nil
        }

        // Resilient hours: Double, Int, or String
        if let doubleHours = try? container.decode(Double.self, forKey: .hours) {
            hours = doubleHours
        } else if let intHours = try? container.decode(Int.self, forKey: .hours) {
            hours = Double(intHours)
        } else if let stringHours = try? container.decode(String.self, forKey: .hours) {
            hours = Double(stringHours)
        } else {
            hours = nil
        }

        tasks = try? container.decode([String].self, forKey: .tasks)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(taskId, forKey: .taskId)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(points, forKey: .points)
        try container.encodeIfPresent(hours, forKey: .hours)
        try container.encodeIfPresent(tasks, forKey: .tasks)
    }
}
