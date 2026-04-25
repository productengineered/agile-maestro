import Foundation

/// Protocol defining atomic backup operations for task JSON files.
///
/// Conforming types copy JSON files from a source directory to a destination
/// directory using an atomic temp-file-then-replace pattern. Backups are additive:
/// files present in the destination but not in the source are never removed.
protocol BackupServiceProtocol: Sendable {

    /// Copies all `*.json` files from `source` to `destination` atomically.
    ///
    /// For each JSON file in `source`, the implementation writes to a temporary
    /// file in `destination` and then replaces (or moves) the final file into place.
    /// This prevents observers from reading a partially written backup.
    ///
    /// - Parameters:
    ///   - source: Directory containing the JSON files to back up (e.g., a session directory).
    ///   - destination: Directory where backups are written (e.g., a product backup directory).
    /// - Throws: If any file operation fails. The caller is responsible for error handling.
    func performBackup(from source: URL, to destination: URL) async throws
}
