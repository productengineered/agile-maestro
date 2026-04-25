import Foundation

/// Structured definition-of-done criteria for epics and stories.
struct DefinitionOfDone: Codable {
    let purpose: String?
    let completionGates: [String]?
    let qualityGatesSource: String?
    let generationHints: [String]?

    enum CodingKeys: String, CodingKey {
        case purpose
        case completionGates = "completion_gates"
        case qualityGatesSource = "quality_gates_source"
        case generationHints = "generation_hints"
    }

    /// All completion gates, defaulting to an empty array.
    var allGates: [String] {
        completionGates ?? []
    }
}
