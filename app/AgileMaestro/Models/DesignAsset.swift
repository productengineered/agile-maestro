import Foundation

/// A design asset reference (Figma file, Sketch document, etc.).
struct DesignAsset: Codable, Identifiable {
    let name: String?
    let url: String?
    let type: String?

    private let fallbackID: String = UUID().uuidString

    enum CodingKeys: String, CodingKey {
        case name
        case url
        case type
    }

    var id: String {
        name ?? fallbackID
    }
}
