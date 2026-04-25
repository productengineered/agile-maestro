import Foundation

/// AI-oriented execution plan for an epic, replacing the legacy timeline.
struct ExecutionPlan: Codable {
    let shape: String?
    let phases: [ExecutionPhase]?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case shape
        case phases
        case notes
    }
}

/// A single phase within an execution plan.
struct ExecutionPhase: Codable, Identifiable {
    let phase: String?
    let intent: String?
    let stories: [String]?
    let deliverables: [String]?

    private let fallbackID: String = UUID().uuidString

    enum CodingKeys: String, CodingKey {
        case phase
        case intent
        case stories
        case deliverables
    }

    var id: String {
        phase ?? fallbackID
    }
}
