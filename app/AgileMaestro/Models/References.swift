import Foundation

/// Document references linking an epic to its source specifications.
struct References: Codable {
    let prdStories: [String]?
    let techSpecSections: [String]?
    let dataSchemaSection: [String]?
    let uiSpecSections: [String]?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case prdStories = "prd_stories"
        case techSpecSections = "tech_spec_sections"
        case dataSchemaSection = "data_schema_sections"
        case uiSpecSections = "ui_spec_sections"
        case notes
    }
}
