import Foundation

/// Domain-specific error type for AgileMaestro app operations.
enum AgileMaestroError: LocalizedError {
    case sessionDirectoryNotFound
    case sessionDirectoryNotReadable(path: URL)
    case noTasksFound(path: URL)
    case jsonParseError(file: String, underlying: Error)
    case invalidTaskStructure(file: String, reason: String)
    case backupFailed(source: URL, destination: URL, underlying: Error)
    case productSaveFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .sessionDirectoryNotFound:
            return "Session directory not found."
        case .sessionDirectoryNotReadable(let path):
            return "Cannot read session directory at \(path.path)."
        case .noTasksFound(let path):
            return "No tasks found in \(path.lastPathComponent)."
        case .jsonParseError(let file, _):
            return "Failed to parse task file: \(file)."
        case .invalidTaskStructure(let file, let reason):
            return "Invalid structure in \(file): \(reason)."
        case .backupFailed(_, let destination, _):
            return "Backup failed to \(destination.lastPathComponent)."
        case .productSaveFailed:
            return "Failed to save product list."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .sessionDirectoryNotFound:
            return "Ensure Claude Code has created tasks in ~/.claude/tasks/ and try refreshing."
        case .sessionDirectoryNotReadable:
            return "Check file permissions for the tasks directory."
        case .noTasksFound:
            return "Select a session that contains task JSON files."
        case .jsonParseError(_, let underlying):
            return "The file may be malformed. Underlying error: \(underlying.localizedDescription)"
        case .invalidTaskStructure(_, let reason):
            return "Task structure issue: \(reason)"
        case .backupFailed(let source, _, let underlying):
            return "Could not back up from \(source.lastPathComponent). Error: \(underlying.localizedDescription)"
        case .productSaveFailed(let underlying):
            return "Could not write products.json. Error: \(underlying.localizedDescription)"
        }
    }
}
