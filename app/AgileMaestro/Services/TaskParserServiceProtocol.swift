import Foundation

/// The three-way result of parsing a session directory.
///
/// - `structuredTasks`: Files that decoded fully as `TaskItem` (have `metadata.schema_version`).
/// - `claudeTasks`: Files with valid JSON containing `id` and `subject` but no `metadata.schema_version`.
/// - `orphanedTasks`: Everything else — invalid JSON, missing `id`/`subject`, or broken metadata.
struct ParseResult: Sendable {
    /// Fully-structured tasks, sorted by numeric ID (or lexicographically for non-numeric IDs).
    let structuredTasks: [TaskItem]
    /// Plain Claude Code task files that have `id` and `subject` but no `schema_version`.
    let claudeTasks: [ClaudeTask]
    /// Files that could not be classified as either structured or ClaudeTask.
    let orphanedTasks: [OrphanedTask]
}

/// Protocol defining task JSON parsing operations.
///
/// Conforming types read `.json` files from a session directory and decode them
/// into a `ParseResult` containing three typed collections. The protocol supports
/// dependency injection for unit testing.
protocol TaskParserServiceProtocol: Sendable {

    /// Loads and classifies all task files from a session directory.
    ///
    /// Reads all `*.json` files in `directory`, excluding known non-task files
    /// (`settings.json`, `config.json`, `team-manifest.json`). Parsing is done
    /// concurrently. Each file is classified into one of three categories:
    /// structured (full `TaskItem`), claudeTask (plain id+subject JSON), or orphaned.
    ///
    /// - Parameter directory: URL of the session directory to scan.
    /// - Returns: A `ParseResult` with three typed arrays.
    /// - Throws: If the directory cannot be enumerated.
    func loadTasks(from directory: URL) async throws -> ParseResult

    /// Returns lightweight session metadata without fully decoding every task.
    ///
    /// Counts the `.json` task files in `directory` and finds the first epic task
    /// to extract a display name. This is substantially cheaper than `loadTasks(from:)`.
    ///
    /// - Parameter directory: URL of the session directory to peek.
    /// - Returns: `SessionInfo` with `epicName`, `epicDisplayId`, and `taskCount`.
    func peekSessionInfo(in directory: URL) async -> SessionInfo
}
