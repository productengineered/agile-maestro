import Foundation

/// All fields specific to a story task.
///
/// Decoded from the flat top-level metadata JSON object when `type == "story"`.
/// All fields are optional to support resilient decoding of partial or evolving JSON.
struct StoryMetadata: Codable {

    // MARK: - Stored Properties

    let schemaVersion: String?
    /// Parent epic task ID.
    let parent: String?
    let storyId: String?
    /// v2.0: Quick reference to the parent epic.
    let epicId: String?
    let priority: String?
    /// Resilient: decoded from Int or String.
    let sprint: Int?
    /// Resilient: decoded from Int or String.
    let points: Int?
    let assignee: String?
    let claimedBy: String?
    let claimedAt: Date?
    let lastUpdatedAt: Date?
    let outOfScope: [String]?
    /// v2.0: Changed from [String] to [DesignAsset].
    let designAssets: [DesignAsset]?
    let acceptanceCriteria: [AcceptanceCriteriaItem]?
    /// v2.0: Technical constraints for this story.
    let implementationConstraints: [String]?
    /// v2.0: Context for AI agents working on this story.
    let aiContext: String?
    /// v2.0: Structured definition-of-done for this story.
    let definitionOfDone: DefinitionOfDone?
    let review: ReviewInfo?
    let tasks: [TaskReference]?

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case parent
        case storyId = "story_id"
        case epicId = "epic_id"
        case priority
        case sprint
        case points
        case assignee
        case claimedBy = "claimed_by"
        case claimedAt = "claimed_at"
        case lastUpdatedAt = "last_updated_at"
        case outOfScope = "out_of_scope"
        case designAssets = "design_assets"
        case acceptanceCriteria = "acceptance_criteria"
        case implementationConstraints = "implementation_constraints"
        case aiContext = "ai_context"
        case definitionOfDone = "definition_of_done"
        case review
        case tasks
    }

    // MARK: - Custom Decoding

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        schemaVersion = try? container.decode(String.self, forKey: .schemaVersion)
        parent = try? container.decode(String.self, forKey: .parent)
        storyId = try? container.decode(String.self, forKey: .storyId)
        epicId = try? container.decode(String.self, forKey: .epicId)
        priority = decodeFlexibleString(from: container, forKey: .priority)
        sprint = decodeFlexibleInt(from: container, forKey: .sprint)
        points = decodeFlexibleInt(from: container, forKey: .points)
        assignee = try? container.decode(String.self, forKey: .assignee)
        claimedBy = try? container.decode(String.self, forKey: .claimedBy)
        claimedAt = decodeDateResiliently(from: container, forKey: .claimedAt)
        lastUpdatedAt = decodeDateResiliently(from: container, forKey: .lastUpdatedAt)
        outOfScope = try? container.decode([String].self, forKey: .outOfScope)
        designAssets = decodeResiliently(DesignAsset.self, from: container, forKey: .designAssets)
        acceptanceCriteria = decodeResiliently(
            AcceptanceCriteriaItem.self, from: container, forKey: .acceptanceCriteria)
        implementationConstraints = try? container.decode([String].self, forKey: .implementationConstraints)
        aiContext = try? container.decode(String.self, forKey: .aiContext)
        definitionOfDone = try? container.decode(DefinitionOfDone.self, forKey: .definitionOfDone)
        review = try? container.decode(ReviewInfo.self, forKey: .review)
        tasks = decodeResiliently(TaskReference.self, from: container, forKey: .tasks)
    }

    // MARK: - Static Empty

    /// An empty StoryMetadata used as a fallback when decoding fails.
    static let empty = StoryMetadata()

    private init() {
        schemaVersion = nil
        parent = nil
        storyId = nil
        epicId = nil
        priority = nil
        sprint = nil
        points = nil
        assignee = nil
        claimedBy = nil
        claimedAt = nil
        lastUpdatedAt = nil
        outOfScope = nil
        designAssets = nil
        acceptanceCriteria = nil
        implementationConstraints = nil
        aiContext = nil
        definitionOfDone = nil
        review = nil
        tasks = nil
    }
}
