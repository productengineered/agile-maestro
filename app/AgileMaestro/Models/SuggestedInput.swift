import Foundation

/// A suggested input value provided by planning agents.
struct SuggestedInput: Codable, Identifiable {
    let field: String?
    let suggestion: String?

    private let fallbackID: String = UUID().uuidString

    enum CodingKeys: String, CodingKey {
        case field
        case suggestion
    }

    var id: String {
        field ?? fallbackID
    }
}
