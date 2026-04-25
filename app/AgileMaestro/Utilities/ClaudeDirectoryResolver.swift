import Foundation

/// Resolves paths within the ~/.claude/ directory tree.
struct ClaudeDirectoryResolver {

    /// Returns the URL for the ~/.claude/ directory.
    static func claudeDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
    }

    /// Returns the URL for the ~/.claude/tasks/ directory.
    static func resolve() -> URL {
        claudeDirectory().appendingPathComponent("tasks")
    }

    /// Returns true when ~/.claude/tasks/ exists and is a directory.
    static func isTasksDirectoryAvailable() -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: resolve().path,
            isDirectory: &isDirectory
        )
        return exists && isDirectory.boolValue
    }
}
