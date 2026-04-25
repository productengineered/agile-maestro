import Foundation

/// A Claude Code task item loaded from a `.json` file in the task list directory.
///
/// The top-level JSON structure maps directly to this struct. `sourceFile` is set
/// post-parse by `TaskParserService` and is excluded from JSON decoding/encoding.
struct TaskItem: Codable, Identifiable, Hashable, Sendable {

    // MARK: - Stored Properties

    let id: String
    let subject: String
    let description: String
    let activeForm: String?
    let status: TaskStatus
    let blocks: [String]
    let blockedBy: [String]
    var metadata: TaskMetadataContainer
    /// Not decoded from JSON — set by `TaskParserService` after parsing.
    var sourceFile: String?

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case id
        case subject
        case description
        case activeForm
        case status
        case blocks
        case blockedBy
        case metadata
        // sourceFile is intentionally excluded
    }

    // MARK: - Custom Decoding

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        subject = (try? container.decode(String.self, forKey: .subject)) ?? ""
        description = (try? container.decode(String.self, forKey: .description)) ?? ""
        activeForm = try? container.decode(String.self, forKey: .activeForm)
        status = (try? container.decode(TaskStatus.self, forKey: .status)) ?? .pending
        blocks = (try? container.decode([String].self, forKey: .blocks)) ?? []
        blockedBy = (try? container.decode([String].self, forKey: .blockedBy)) ?? []
        metadata = try container.decode(TaskMetadataContainer.self, forKey: .metadata)
        sourceFile = nil
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: TaskItem, rhs: TaskItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Computed Properties

extension TaskItem {

    /// The task type derived from metadata.
    var type: TaskType {
        metadata.type
    }

    /// The parent task ID (internal numeric ID from a `"parent"` JSON key, if present).
    ///
    /// Most tasks written by the Claude Tasks CLI do NOT include a `"parent"` key.
    /// They instead record the parent's *display* ID (e.g. "AM-500") in `"epic_id"` or
    /// `"story_id"`. Use `parentDisplayId` for display-ID-based lookups and
    /// `resolvedParentId(in:)` for a fully-resolved internal ID.
    ///
    /// - Epic: always `nil`.
    /// - Story: `metadata.story?.parent`
    /// - Task/Bug/TechDebt: `metadata.task?.parent`
    var parentId: String? {
        switch metadata.type {
        case .epic:
            return nil
        case .story:
            return metadata.story?.parent
        case .task, .bug, .techdebt:
            return metadata.task?.parent
        }
    }

    /// The parent's *display* ID as stored in metadata (e.g. "AM-500" for a story, "AM-501"
    /// for a task). This is the fallback when `parentId` is nil.
    ///
    /// - Epic: always `nil`.
    /// - Story: `metadata.story?.epicId`
    /// - Task/Bug/TechDebt: `metadata.task?.storyId`
    var parentDisplayId: String? {
        switch metadata.type {
        case .epic:
            return nil
        case .story:
            return metadata.story?.epicId
        case .task, .bug, .techdebt:
            return metadata.task?.storyId
        }
    }

    /// Resolves the parent's internal task ID from a flat task list.
    ///
    /// Priority:
    /// 1. `parentId` — if the JSON included a `"parent"` key with an internal ID.
    /// 2. Lookup by `parentDisplayId` — match `item.displayId` in the provided list.
    ///
    /// Returns `nil` for epics or when no matching parent is found.
    ///
    /// - Parameter tasks: The full session task list to search.
    func resolvedParentId(in tasks: [TaskItem]) -> String? {
        if let direct = parentId { return direct }
        guard let displayId = parentDisplayId else { return nil }
        return tasks.first(where: { $0.displayId == displayId })?.id
    }

    /// A human-readable display identifier (e.g. "AM-100", "CASHFLOW-705-1").
    ///
    /// - Epic: `metadata.epic?.displayId ?? metadata.epic?.epicId`
    /// - Story: `metadata.story?.storyId`
    /// - Task/Bug/TechDebt: `metadata.task?.taskId`
    var displayId: String? {
        switch metadata.type {
        case .epic:
            return metadata.epic?.displayId ?? metadata.epic?.epicId
        case .story:
            return metadata.story?.storyId
        case .task, .bug, .techdebt:
            return metadata.task?.taskId
        }
    }

    /// Labels from metadata, defaulting to an empty array.
    var labels: [String] {
        metadata.labels ?? []
    }

    /// Comments from metadata, defaulting to an empty array.
    var comments: [Comment] {
        metadata.comments ?? []
    }

    /// True if this item is blocked by one or more items.
    var isBlocked: Bool {
        !blockedBy.isEmpty
    }

    /// True if this item blocks one or more items.
    var isBlocking: Bool {
        !blocks.isEmpty
    }

    /// Priority string (e.g. "P0", "P1").
    var priority: String? {
        metadata.priority
    }

    /// Sprint number, if applicable.
    ///
    /// - Epic: `metadata.epic?.sprint`
    /// - Story: `metadata.story?.sprint`
    /// - Task/Bug/TechDebt: `nil`
    var sprint: Int? {
        switch metadata.type {
        case .epic:
            return metadata.epic?.sprint
        case .story:
            return metadata.story?.sprint
        case .task, .bug, .techdebt:
            return nil
        }
    }

    /// Approval state string (e.g. "pending", "approved").
    var approval: String? {
        metadata.approval
    }

    /// Whether the metadata `blocked` flag is set.
    var isWorkflowBlocked: Bool {
        metadata.blocked ?? false
    }

    /// Current review stage string (e.g. "code-review", "qa").
    var reviewStage: String? {
        metadata.reviewStage
    }

    /// Current review result string (e.g. "awaiting", "rejected").
    var reviewResult: String? {
        metadata.reviewResult
    }

    /// The assignee for this item.
    ///
    /// Story: prefers `assignee`, falls back to `claimedBy`.
    /// Task/Bug/TechDebt: prefers `assignee`, falls back to `claimedBy`.
    /// Epic: always `nil`.
    var assignee: String? {
        switch metadata.type {
        case .epic:
            return nil
        case .story:
            return metadata.story?.assignee ?? metadata.story?.claimedBy
        case .task, .bug, .techdebt:
            return metadata.task?.assignee ?? metadata.task?.claimedBy
        }
    }

    // MARK: - Convenience Booleans

    /// True if the item is an epic.
    var isEpic: Bool { type == .epic }

    /// True if the item is a story.
    var isStory: Bool { type == .story }

    /// True if the item is a leaf task (task, bug, or techdebt).
    var isTask: Bool { type == .task || type == .bug || type == .techdebt }

    /// Short display identifier (e.g. "AM-100", or "#42" if no displayId).
    var shortId: String {
        displayId ?? "#\(id)"
    }
}
