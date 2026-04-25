import Foundation

/// A comment on a task, story, or epic.
///
/// Comments are append-only records. Only rejection-type comments have `resolved` tracking.
struct Comment: Codable, Identifiable {
    let id: String
    let timestamp: Date?
    let author: String?
    let type: String?
    let content: String?
    let resolved: Bool?
    let resolvedBy: String?
    let resolvedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case author
        case type
        case content
        case resolved
        case resolvedBy = "resolved_by"
        case resolvedAt = "resolved_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Resilient ID: tries String, then Int, falls back to UUID
        if let stringId = try? container.decode(String.self, forKey: .id) {
            id = stringId
        } else if let intId = try? container.decode(Int.self, forKey: .id) {
            id = String(intId)
        } else {
            id = UUID().uuidString
        }

        timestamp = decodeDateResiliently(from: container, forKey: .timestamp)
        author = try? container.decode(String.self, forKey: .author)
        type = try? container.decode(String.self, forKey: .type)
        content = try? container.decode(String.self, forKey: .content)
        resolved = decodeFlexibleBool(from: container, forKey: .resolved)
        resolvedBy = try? container.decode(String.self, forKey: .resolvedBy)
        resolvedAt = decodeDateResiliently(from: container, forKey: .resolvedAt)
    }
}
