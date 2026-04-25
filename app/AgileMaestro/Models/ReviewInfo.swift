import Foundation

/// Review process information for a story.
struct ReviewInfo: Codable {
    let required: [String]?
    let completed: [String]?
    let currentReviewer: String?

    enum CodingKeys: String, CodingKey {
        case required
        case completed
        case currentReviewer = "current_reviewer"
    }
}
