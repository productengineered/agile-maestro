import Foundation

/// An acceptance criteria item using Gherkin-style Given/When/Then format.
struct AcceptanceCriteriaItem: Codable, Identifiable {
    let id: String
    let title: String?
    let given: String?
    let when: String?
    let then: String?
    let verify: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case given
        case when
        case then
        case verify
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

        title = try? container.decode(String.self, forKey: .title)
        given = try? container.decode(String.self, forKey: .given)
        when = try? container.decode(String.self, forKey: .when)
        then = try? container.decode(String.self, forKey: .then)
        verify = try? container.decode(String.self, forKey: .verify)
    }
}
