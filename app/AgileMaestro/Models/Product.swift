import Foundation

/// A user-registered project directory that AgileMaestro monitors.
///
/// Products are stored as a JSON array in
/// `~/Library/Application Support/AgileMaestro/products.json`.
struct Product: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var name: String
    var associatedSessionPath: String?
    var claudeDirectoryPath: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case associatedSessionPath = "associated_session_path"
        case claudeDirectoryPath = "claude_directory_path"
        case createdAt = "created_at"
    }

    init(
        id: UUID = UUID(),
        name: String,
        associatedSessionPath: String? = nil,
        claudeDirectoryPath: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.associatedSessionPath = associatedSessionPath
        self.claudeDirectoryPath = claudeDirectoryPath
        self.createdAt = createdAt
    }

    // MARK: - Computed Properties

    /// Backup directory for this product's task JSON files.
    var backupDirectoryURL: URL {
        // swiftlint:disable:next force_unwrapping
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AgileMaestro")
            .appendingPathComponent("products")
            .appendingPathComponent(id.uuidString)
            .appendingPathComponent("backups")
    }

    /// URL of the .claude/ toolkit directory, if configured.
    var claudeDirectoryURL: URL? {
        claudeDirectoryPath.map { URL(fileURLWithPath: $0).appendingPathComponent(".claude") }
    }

    /// URL of the team-manifest.json within the .claude/ directory.
    var manifestURL: URL? {
        claudeDirectoryURL?.appendingPathComponent("team-manifest.json")
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Product, rhs: Product) -> Bool {
        lhs.id == rhs.id
    }
}
