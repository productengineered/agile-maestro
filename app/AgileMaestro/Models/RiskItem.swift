import Foundation

/// A risk item describing a potential project risk.
struct RiskItem: Codable, Identifiable {
    let id: String
    let description: String?
    let probability: String?
    let impact: String?
    let mitigation: String?

    enum CodingKeys: String, CodingKey {
        case id
        case description
        case probability
        case impact
        case mitigation
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

        description = try? container.decode(String.self, forKey: .description)
        probability = try? container.decode(String.self, forKey: .probability)
        impact = try? container.decode(String.self, forKey: .impact)
        mitigation = try? container.decode(String.self, forKey: .mitigation)
    }
}
