import Foundation
import OSLog

/// Mirrors `*.json` files from a session directory to a product backup directory.
///
/// Each file is written atomically: a temp file is written first and then moved
/// into the destination using `FileManager.replaceItemAt` (overwrite) or
/// `FileManager.moveItem` (new file). Files present in the destination but absent
/// from the source are left untouched — backups are additive only.
final class BackupService: BackupServiceProtocol {

    // MARK: - Singleton

    static let shared = BackupService()

    // MARK: - Private Properties

    // FileManager is not formally Sendable but is safe to use from multiple contexts
    // when accessed only via its stateless default instance.
    nonisolated(unsafe) private let fileManager: FileManager
    private let logger = Logger.backup

    // MARK: - Init

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - BackupServiceProtocol

    func performBackup(from source: URL, to destination: URL) async throws {
        try ensureDirectory(destination)

        let contents = try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        let jsonFiles = contents.filter { $0.pathExtension == "json" }
        logger.info("Backing up \(jsonFiles.count) JSON file(s) from \(source.lastPathComponent)")

        for sourceFile in jsonFiles {
            let filename = sourceFile.lastPathComponent
            let destinationFile = destination.appendingPathComponent(filename)
            let tempFile = destination.appendingPathComponent(".\(filename).tmp")

            let data = try Data(contentsOf: sourceFile)
            try data.write(to: tempFile, options: .atomic)

            do {
                if fileManager.fileExists(atPath: destinationFile.path) {
                    _ = try fileManager.replaceItemAt(destinationFile, withItemAt: tempFile)
                } else {
                    try fileManager.moveItem(at: tempFile, to: destinationFile)
                }
            } catch {
                try? fileManager.removeItem(at: tempFile)
                throw error
            }
        }

        logger.info("Backup complete: \(jsonFiles.count) file(s) written to \(destination.lastPathComponent)")
    }

    // MARK: - Private Helpers

    private func ensureDirectory(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw CocoaError(.fileWriteFileExists,
                                 userInfo: [NSLocalizedDescriptionKey:
                                    "Expected a directory at \(url.path) but found a regular file."])
            }
            return
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
