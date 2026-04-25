import Foundation

/// The polymorphic metadata wrapper for a Claude Code task.
///
/// Decodes the flat `metadata` JSON object from a task file, dispatching to
/// `EpicMetadata`, `StoryMetadata`, or `TaskSpecificMetadata` based on the `type` field.
/// All decoding is resilient — individual field failures never abort the entire decode.
struct TaskMetadataContainer: Codable {

    // MARK: - Common Fields

    /// The task type. Determines which type-specific metadata is populated.
    let type: TaskType
    let labels: [String]?
    let comments: [Comment]?
    let createdAt: Date?
    let createdBy: String?
    /// Raw status string (distinct from the top-level TaskItem.status).
    let status: String?
    /// Decoded from Int or String.
    let priority: String?
    let approval: String?
    /// Decoded from Bool or String ("true"/"false").
    let blocked: Bool?
    let reviewStage: String?
    let reviewResult: String?

    // MARK: - Type-Specific Metadata

    /// Populated when `type == .epic`.
    let epic: EpicMetadata?
    /// Populated when `type == .story`.
    let story: StoryMetadata?
    /// Populated when `type == .task`, `.bug`, or `.techdebt`.
    let task: TaskSpecificMetadata?

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case type
        case labels
        case comments
        case createdAt = "created_at"
        case createdBy = "created_by"
        case status
        case priority
        case approval
        case blocked
        case reviewStage = "review_stage"
        case reviewResult = "review_result"
    }

    // MARK: - Custom Decoding

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decode type first — it controls polymorphic dispatch.
        // Fall back to .task if missing or unrecognised.
        if let rawType = try? container.decode(String.self, forKey: .type),
           let taskType = TaskType(rawValue: rawType) {
            type = taskType
        } else {
            type = .task
        }

        // Common fields
        labels = try? container.decode([String].self, forKey: .labels)
        comments = decodeResiliently(Comment.self, from: container, forKey: .comments)
        createdAt = decodeDateResiliently(from: container, forKey: .createdAt)
        createdBy = try? container.decode(String.self, forKey: .createdBy)
        status = try? container.decode(String.self, forKey: .status)
        priority = decodeFlexibleString(from: container, forKey: .priority)
        approval = try? container.decode(String.self, forKey: .approval)
        blocked = decodeFlexibleBool(from: container, forKey: .blocked)
        reviewStage = try? container.decode(String.self, forKey: .reviewStage)
        reviewResult = try? container.decode(String.self, forKey: .reviewResult)

        // Type-specific dispatch — uses the same decoder so type-specific structs
        // read from the same flat JSON object.
        switch type {
        case .epic:
            epic = (try? EpicMetadata(from: decoder)) ?? .empty
            story = nil
            task = nil
        case .story:
            epic = nil
            story = (try? StoryMetadata(from: decoder)) ?? .empty
            task = nil
        case .task, .bug, .techdebt:
            epic = nil
            story = nil
            task = (try? TaskSpecificMetadata(from: decoder)) ?? .empty
        }
    }

    // MARK: - Custom Encoding

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type.rawValue, forKey: .type)
        try container.encodeIfPresent(labels, forKey: .labels)
        try container.encodeIfPresent(comments, forKey: .comments)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(createdBy, forKey: .createdBy)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(priority, forKey: .priority)
        try container.encodeIfPresent(approval, forKey: .approval)
        try container.encodeIfPresent(blocked, forKey: .blocked)
        try container.encodeIfPresent(reviewStage, forKey: .reviewStage)
        try container.encodeIfPresent(reviewResult, forKey: .reviewResult)

        // Flatten type-specific metadata into the same encoder (not nested).
        try epic?.encode(to: encoder)
        try story?.encode(to: encoder)
        try task?.encode(to: encoder)
    }
}
