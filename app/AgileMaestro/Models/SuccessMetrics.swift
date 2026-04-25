import Foundation

/// Success metrics for an epic, grouped by priority tier.
struct SuccessMetrics: Codable {
    let primary: [String]?
    let secondary: [String]?

    enum CodingKeys: String, CodingKey {
        case primary
        case secondary
    }

    /// All metrics combined: primary first, then secondary.
    var allMetrics: [String] {
        (primary ?? []) + (secondary ?? [])
    }
}
