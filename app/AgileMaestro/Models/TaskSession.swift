import Foundation

/// Represents a Claude Code task session directory discovered at runtime.
///
/// A session maps to one subdirectory under `~/.claude/tasks/`. It is NOT Codable
/// because it is discovered from the filesystem, not decoded from JSON.
struct TaskSession: Identifiable, Sendable, Equatable, Hashable {
    let id: UUID
    let path: URL
    let modifiedDate: Date

    var epicName: String?
    var epicDisplayId: String?
    var taskCount: Int?

    // MARK: - Computed Properties

    /// Human-readable display name combining epic info, task count, and date.
    ///
    /// Format: "EPIC-ID: Epic Name (N tasks) - M/D h:mma"
    /// Falls back to a shortened UUID when epic info is unavailable.
    var displayName: String {
        let shortId = String(id.uuidString.prefix(8))

        let prefix: String
        if let displayId = epicDisplayId, let name = epicName {
            prefix = "\(displayId): \(name)"
        } else if let name = epicName {
            prefix = name
        } else {
            prefix = shortId
        }

        let countSuffix = taskCount.map { " (\($0) tasks)" } ?? ""
        let dateSuffix = " - \(Self.dateFormatter.string(from: modifiedDate))"

        return prefix + countSuffix + dateSuffix
    }

    // MARK: - Private Helpers

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d h:mma"
        return formatter
    }()

    // MARK: - Equatable & Hashable (by id only)

    static func == (lhs: TaskSession, rhs: TaskSession) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Lightweight summary returned by `TaskParserService.peekSessionInfo`.
struct SessionInfo: Sendable {
    let epicName: String?
    let epicDisplayId: String?
    let taskCount: Int
}
