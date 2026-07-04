import Foundation
import OSLog

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
    /// Epic-only Tier-2 agent UAT data. Absent for all other task types; absent or `nil`
    /// for epics that haven't run a Tier-2 pass yet.
    let uat: UATMetadata?

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
        case uat
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
        uat = try? container.decode(UATMetadata.self, forKey: .uat)

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
        try container.encodeIfPresent(uat, forKey: .uat)

        // Flatten type-specific metadata into the same encoder (not nested).
        try epic?.encode(to: encoder)
        try story?.encode(to: encoder)
        try task?.encode(to: encoder)
    }
}

// MARK: - UAT Metadata (Tier-2 Interaction Gate)

/// The `metadata.uat` object — Tier-2 (XCUITest) agent UAT results, written by the
/// uat-agent after each automated interaction-verification pass. Epic-only; always
/// optional, and tolerant of malformed nested content (never throws).
///
/// See `planning/notes/agent-uat-stage-reference.md` for the full field reference.
struct UATMetadata: Codable {

    /// The most recent Tier-2 interaction-verification result. `nil` if absent or if the
    /// nested object itself is malformed.
    let tier2: UATTier2Metadata?

    enum CodingKeys: String, CodingKey {
        case tier2
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tier2 = try? container.decode(UATTier2Metadata.self, forKey: .tier2)
    }
}

/// `metadata.uat.tier2` — result of the most recent Tier-2 (XCUITest) interaction-
/// verification pass. All fields are optional per `agent-uat-stage-reference.md`.
struct UATTier2Metadata: Codable {

    /// `"passed"`, `"failed"`, or `"skipped"`. An unrecognized or malformed value decodes
    /// to `nil` (treated as absent) rather than throwing — a stale/forward-incompatible
    /// value is not user-actionable, so it's logged at debug level only.
    let result: UATTier2Result?
    /// Repo-relative `.xcresult` bundle path. Present when `result == .passed`.
    let xcresult: String?
    /// Names of failing journeys/tests. Present when `result == .failed`.
    let failedTests: [String]?
    /// Why Tier 2 couldn't run. Present when `result == .skipped`.
    let reason: String?
    let recordedAt: Date?
    let recordedBy: String?

    enum CodingKeys: String, CodingKey {
        case result
        case xcresult
        case failedTests = "failed_tests"
        case reason
        case recordedAt = "recorded_at"
        case recordedBy = "recorded_by"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let rawResult = try? container.decode(String.self, forKey: .result)
        if let rawResult, let parsed = UATTier2Result(rawValue: rawResult) {
            result = parsed
        } else {
            result = nil
            if let rawResult {
                Logger.parser.debug(
                    "metadata.uat.tier2.result unrecognized value, treated as absent: \(rawResult, privacy: .public)")
            }
        }

        xcresult = try? container.decode(String.self, forKey: .xcresult)
        failedTests = decodeResiliently(String.self, from: container, forKey: .failedTests)
        reason = try? container.decode(String.self, forKey: .reason)
        recordedAt = decodeDateResiliently(from: container, forKey: .recordedAt)
        recordedBy = try? container.decode(String.self, forKey: .recordedBy)
    }
}

/// The result of a Tier-2 (XCUITest) interaction-verification pass.
enum UATTier2Result: String, Codable {
    case passed
    case failed
    case skipped
}
