import CryptoKit
import Foundation
import OSLog

/// Discovers Claude Code task sessions from `~/.claude/tasks/`.
///
/// Each subdirectory of the tasks root becomes a `TaskSession`. The service
/// is stateless — it reads from disk every time it is called. Sorting and
/// capping are applied before results are returned.
final class TaskSessionService: TaskSessionServiceProtocol {

    // MARK: - Singleton

    static let shared = TaskSessionService()

    // MARK: - Private Properties

    private let tasksRoot: URL
    private let logger = Logger.app

    // MARK: - Init

    /// Creates a service that reads from `~/.claude/tasks/`.
    init(tasksRoot: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/tasks")) {
        self.tasksRoot = tasksRoot
    }

    // MARK: - TaskSessionServiceProtocol

    func getRecentSessions(from path: URL, maxSessions: Int = 10) async throws -> [TaskSession] {
        let scoped = TaskSessionService(tasksRoot: path)
        return try await scoped.getRecentSessions(maxSessions: maxSessions)
    }

    func getRecentSessions(maxSessions: Int = 5) async throws -> [TaskSession] {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: tasksRoot.path) else {
            logger.info("Tasks root does not exist: \(self.tasksRoot.path)")
            return []
        }

        let contents = try fileManager.contentsOfDirectory(
            at: tasksRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        var sessions: [TaskSession] = []
        for url in contents {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                continue
            }

            let modifiedDate = (try? url.resourceValues(
                forKeys: [.contentModificationDateKey]
            ))?.contentModificationDate ?? Date.distantPast

            let sessionId = Self.uuid(forDirectoryName: url.lastPathComponent, fullPath: url.path)
            let session = TaskSession(id: sessionId, path: url, modifiedDate: modifiedDate)
            sessions.append(session)
        }

        let sorted = sessions.sorted { $0.modifiedDate > $1.modifiedDate }
        let capped = Array(sorted.prefix(maxSessions))
        logger.info("Discovered \(sessions.count) sessions, returning \(capped.count)")
        return capped
    }

    func enrichSessions(
        _ sessions: [TaskSession],
        using parser: TaskParserServiceProtocol
    ) async -> [TaskSession] {
        await withTaskGroup(of: (Int, SessionInfo).self) { group in
            for (index, session) in sessions.enumerated() {
                group.addTask {
                    let info = await parser.peekSessionInfo(in: session.path)
                    return (index, info)
                }
            }

            var enriched = sessions
            for await (index, info) in group {
                enriched[index].epicName = info.epicName
                enriched[index].epicDisplayId = info.epicDisplayId
                enriched[index].taskCount = info.taskCount
            }
            return enriched
        }
    }

    // MARK: - Private Helpers

    /// Returns a UUID for a directory: the folder name itself if it is a valid UUID,
    /// otherwise a deterministic UUID derived from the SHA-256 hash of `fullPath`.
    private static func uuid(forDirectoryName name: String, fullPath: String) -> UUID {
        if let direct = UUID(uuidString: name) {
            return direct
        }
        let digest = SHA256.hash(data: Data(fullPath.utf8))
        // SHA-256 produces 32 bytes; a UUID needs 16 bytes (128 bits)
        var bytes = Array(digest.prefix(16))
        // Set version bits (v4) and variant bits (RFC 4122)
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return NSUUID(uuidBytes: bytes) as UUID
    }
}
