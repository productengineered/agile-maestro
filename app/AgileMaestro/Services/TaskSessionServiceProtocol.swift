import Foundation

/// Protocol defining session discovery operations for Claude Code task sessions.
///
/// Conforming types scan `~/.claude/tasks/` for session directories and return
/// structured `TaskSession` values. The protocol is designed for dependency
/// injection and unit-test isolation.
protocol TaskSessionServiceProtocol: Sendable {

    /// Discovers the most recently modified task sessions from the default tasks root.
    ///
    /// - Parameter maxSessions: Maximum number of sessions to return. Defaults to 5.
    /// - Returns: Sessions sorted by modification date descending (newest first).
    /// - Throws: If the tasks directory cannot be read.
    func getRecentSessions(maxSessions: Int) async throws -> [TaskSession]

    /// Discovers the most recently modified task sessions from a specific directory.
    ///
    /// Used when a product has an `associatedSessionPath` that differs from the
    /// default `~/.claude/tasks/` root. This overload keeps the scoping logic
    /// inside the service layer, enabling full mock isolation in tests.
    ///
    /// - Parameters:
    ///   - path: The root directory to scan for session subdirectories.
    ///   - maxSessions: Maximum number of sessions to return. Defaults to 10.
    /// - Returns: Sessions sorted by modification date descending (newest first).
    /// - Throws: If the directory cannot be read.
    func getRecentSessions(from path: URL, maxSessions: Int) async throws -> [TaskSession]

    /// Enriches sessions with epic name, display ID, and task count.
    ///
    /// Each session directory is peeked concurrently using the provided parser.
    /// Non-fatal errors from individual sessions are silently skipped.
    ///
    /// - Parameters:
    ///   - sessions: Sessions returned by `getRecentSessions`.
    ///   - parser: Parser used to peek at each session directory.
    /// - Returns: Sessions with `epicName`, `epicDisplayId`, and `taskCount` populated.
    func enrichSessions(_ sessions: [TaskSession], using parser: TaskParserServiceProtocol) async -> [TaskSession]
}
