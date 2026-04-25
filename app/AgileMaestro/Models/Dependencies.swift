import Foundation

/// Epic-level dependency information.
struct Dependencies: Codable {
    let external: [ExternalDependency]?
    let `internal`: [String]?
    let blocksEpics: [String]?

    enum CodingKeys: String, CodingKey {
        case external
        case `internal` = "internal"
        case blocksEpics = "blocks_epics"
    }
}

/// A single external dependency (library, service, or team).
struct ExternalDependency: Codable, Identifiable {
    let name: String?
    let version: String?
    let purpose: String?

    private let fallbackID: String = UUID().uuidString

    enum CodingKeys: String, CodingKey {
        case name
        case version
        case purpose
    }

    var id: String {
        name ?? fallbackID
    }
}
