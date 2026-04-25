import Foundation

/// A lightweight representation of a plain Claude Code task JSON file.
///
/// Unlike `TaskItem`, which requires a fully structured `metadata` block with
/// `schema_version`, `ClaudeTask` targets simpler task files that only guarantee
/// `id` and `subject`. All recognised top-level fields are decoded into typed
/// properties; every other key in the JSON is captured verbatim in `rawFields`
/// so no information is discarded.
///
/// ## Decoding contract
/// - `id` defaults to a new UUID string if absent.
/// - `subject` defaults to an empty string if absent.
/// - `description`, `status` are optional and default to `nil`.
/// - `blocks`, `blockedBy` default to empty arrays if absent or null.
/// - Any JSON key not in the known set is decoded as `AnyCodableValue` and
///   stored in `rawFields`.
struct ClaudeTask: Identifiable, Equatable, Sendable {

    // MARK: - Known Fields

    /// Internal task identifier (typically a numeric string like "215").
    let id: String

    /// Short human-readable title.
    let subject: String

    /// Long-form description, may be absent in minimal task files.
    let description: String?

    /// Task lifecycle status string (e.g. "pending", "in_progress", "completed").
    let status: String?

    /// IDs of tasks that this task blocks.
    let blocks: [String]

    /// IDs of tasks that must complete before this task can start.
    let blockedBy: [String]

    // MARK: - Unknown Fields

    /// All JSON keys not recognised as a known top-level field, decoded as
    /// `AnyCodableValue` so callers can inspect any extra metadata.
    let rawFields: [String: AnyCodableValue]

    // MARK: - Source

    /// The filename of the JSON file this task was parsed from (e.g. "215.json").
    ///
    /// Set by `TaskParserService` after decoding. Defaults to `nil` when a task is
    /// created programmatically (e.g. in tests). Detail views use this instead of
    /// constructing `"\(id).json"` because filenames may differ from the task ID.
    var sourceFile: String?
}

// MARK: - Decodable

extension ClaudeTask: Decodable {

    /// The set of JSON keys decoded into typed properties.
    private enum KnownKey: String, CodingKey, CaseIterable {
        case id
        case subject
        case description
        case status
        case blocks
        case blockedBy
    }

    init(from decoder: Decoder) throws {
        // Decode known fields from a strongly-typed keyed container.
        let known = try decoder.container(keyedBy: KnownKey.self)
        id          = try known.decode(String.self, forKey: .id)
        subject     = try known.decode(String.self, forKey: .subject)
        description = try? known.decode(String.self, forKey: .description)
        status      = try? known.decode(String.self, forKey: .status)
        blocks      = try known.decodeIfPresent([String].self, forKey: .blocks) ?? []
        blockedBy   = try known.decodeIfPresent([String].self, forKey: .blockedBy) ?? []

        // Decode ALL keys from a dynamic container, then drop the ones already handled.
        let dynamic = try decoder.container(keyedBy: DynamicKey.self)
        let knownNames = Set(KnownKey.allCases.map(\.rawValue))
        var raw: [String: AnyCodableValue] = [:]
        for key in dynamic.allKeys where !knownNames.contains(key.stringValue) {
            raw[key.stringValue] = (try? dynamic.decode(AnyCodableValue.self, forKey: key)) ?? .null
        }
        rawFields = raw
        sourceFile = nil
    }
}

// MARK: - DynamicKey

/// An ad-hoc `CodingKey` that accepts any string, used to enumerate all JSON keys.
private struct DynamicKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

// MARK: - Convenience

extension ClaudeTask {

    /// True when the task is not yet started.
    var isPending: Bool { status == "pending" }

    /// True when the task is actively being worked on.
    var isInProgress: Bool { status == "in_progress" }

    /// True when the task has been finished.
    var isCompleted: Bool { status == "completed" }

    /// True when this task is blocked by one or more others.
    var isBlocked: Bool { !blockedBy.isEmpty }

    /// True when this task blocks one or more others.
    var isBlocking: Bool { !blocks.isEmpty }
}
