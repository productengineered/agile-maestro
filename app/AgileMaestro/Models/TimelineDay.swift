import Foundation

/// A single day entry in a timeline plan.
///
/// Note: Orphaned in v2.0 schema — timeline was replaced by ExecutionPlan.
/// Retained for backward compatibility with v1.0 task data.
struct TimelineDay: Codable, Identifiable {
    let day: Int
    let focus: String?
    let stories: [String]?
    let deliverables: [String]?

    enum CodingKeys: String, CodingKey {
        case day
        case focus
        case stories
        case deliverables
    }

    var id: Int { day }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Resilient day decoding: tries Int first, then String->Int, fallback 0
        if let intDay = try? container.decode(Int.self, forKey: .day) {
            day = intDay
        } else if let stringDay = try? container.decode(String.self, forKey: .day),
                  let parsedDay = Int(stringDay) {
            day = parsedDay
        } else {
            day = 0
        }
        focus = try? container.decode(String.self, forKey: .focus)
        stories = try? container.decode([String].self, forKey: .stories)
        deliverables = try? container.decode([String].self, forKey: .deliverables)
    }
}
