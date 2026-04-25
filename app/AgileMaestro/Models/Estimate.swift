import Foundation

/// An effort estimate for an epic or story.
struct Estimate: Codable {
    let primaryUnit: String?
    let value: Int?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case primaryUnit = "primary_unit"
        case value
        case notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        primaryUnit = try? container.decode(String.self, forKey: .primaryUnit)
        value = decodeFlexibleInt(from: container, forKey: .value)
        notes = try? container.decode(String.self, forKey: .notes)
    }
}
