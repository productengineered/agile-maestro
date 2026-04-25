import Foundation
import OSLog

/// Parses individual task JSON files and classifies them into three categories.
///
/// All I/O is performed on the calling async context. Concurrent parsing is
/// achieved with `withTaskGroup`. Each file is classified as:
/// - Structured (`TaskItem`): has `metadata.schema_version`, decodes fully.
/// - Claude task (`ClaudeTask`): valid JSON with `id`+`subject`, no `schema_version`.
/// - Orphaned (`OrphanedTask`): invalid JSON, missing required fields, or broken metadata.
final class TaskParserService: TaskParserServiceProtocol {

    // MARK: - Singleton

    static let shared = TaskParserService()

    // MARK: - Private Constants

    /// Files that exist in session directories but are NOT task JSON files.
    private let nonTaskFiles: Set<String> = ["settings.json", "config.json", "team-manifest.json"]

    private let logger = Logger.parser

    // MARK: - Decoder

    private static let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    // MARK: - TaskParserServiceProtocol

    func loadTasks(from directory: URL) async throws -> ParseResult {
        let fileManager = FileManager.default

        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        let jsonURLs = contents.filter { url in
            url.pathExtension == "json" && !nonTaskFiles.contains(url.lastPathComponent)
        }

        var classifications: [FileClassification] = []

        await withTaskGroup(of: FileClassification.self) { group in
            for url in jsonURLs {
                group.addTask {
                    self.classify(url: url)
                }
            }
            for await result in group {
                classifications.append(result)
            }
        }

        var structured: [TaskItem] = []
        var claudeTasks: [ClaudeTask] = []
        var orphanedTasks: [OrphanedTask] = []

        for classification in classifications {
            switch classification {
            case .structured(let item): structured.append(item)
            case .claude(let task):     claudeTasks.append(task)
            case .orphaned(let task):   orphanedTasks.append(task)
            }
        }

        return ParseResult(
            structuredTasks: sortedByID(structured),
            claudeTasks: claudeTasks,
            orphanedTasks: orphanedTasks
        )
    }

    func peekSessionInfo(in directory: URL) async -> SessionInfo {
        let fileManager = FileManager.default

        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return SessionInfo(epicName: nil, epicDisplayId: nil, taskCount: 0)
        }

        let jsonFiles = contents.filter { url in
            url.pathExtension == "json" && !nonTaskFiles.contains(url.lastPathComponent)
        }

        var epicName: String?
        var epicDisplayId: String?

        for url in jsonFiles {
            guard let item = try? parseTask(from: url), item.type == .epic else {
                continue
            }
            let rawName = item.subject
            // Strip "Epic: " prefix when present
            epicName = rawName.hasPrefix("Epic: ")
                ? String(rawName.dropFirst("Epic: ".count))
                : rawName
            epicDisplayId = item.displayId
            break
        }

        return SessionInfo(
            epicName: epicName,
            epicDisplayId: epicDisplayId,
            taskCount: jsonFiles.count
        )
    }

    // MARK: - Private Helpers

    /// Reads a single JSON file, decodes it into a `TaskItem`, and sets `sourceFile`.
    private func parseTask(from url: URL) throws -> TaskItem {
        let data = try Data(contentsOf: url)
        var item = try Self.decoder.decode(TaskItem.self, from: data)
        item.sourceFile = url.lastPathComponent
        return item
    }

    /// Classifies a single JSON file into structured, ClaudeTask, or OrphanedTask.
    ///
    /// Detection logic:
    /// 1. Read data. If read fails → OrphanedTask (no data).
    /// 2. Try JSON deserialization. If invalid JSON → OrphanedTask.
    /// 3. Check `metadata.schema_version` in the top-level object:
    ///    - Present → attempt `TaskItem` decode. Success → structured. Failure → OrphanedTask.
    ///    - Absent → check for `id` + `subject`. Both present → `ClaudeTask`. Either missing → OrphanedTask.
    private func classify(url: URL) -> FileClassification {
        let filename = url.lastPathComponent

        // Step 1: Read raw data.
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            logger.warning("Cannot read task file \(filename): \(error)")
            return .orphaned(OrphanedTask.make(filename: filename, error: error, data: nil))
        }

        // Step 2: Validate JSON structure.
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let error = ParserError.invalidJSON(filename: filename)
            logger.warning("Invalid JSON in task file \(filename)")
            return .orphaned(OrphanedTask.make(filename: filename, error: error, data: data))
        }

        // Step 3a: Has metadata.schema_version → try TaskItem decode.
        // Metadata must be a dictionary. If `metadata` exists but is not a dict
        // (e.g. a string or number), route to orphaned — it cannot be structured.
        let rawMetadata = json["metadata"]
        let metadata = rawMetadata as? [String: Any]
        if rawMetadata != nil && metadata == nil {
            let error = ParserError.malformedMetadata(filename: filename)
            logger.warning("Task file \(filename) has non-dict metadata — routing to orphaned")
            return .orphaned(OrphanedTask.make(filename: filename, error: error, data: data))
        }
        let hasSchemaVersion = (metadata?["schema_version"] as? String) != nil

        if hasSchemaVersion {
            do {
                var item = try Self.decoder.decode(TaskItem.self, from: data)
                item.sourceFile = filename
                return .structured(item)
            } catch {
                logger.warning("Failed to decode structured task \(filename): \(error)")
                return .orphaned(OrphanedTask.make(filename: filename, error: error, data: data))
            }
        }

        // Step 3b: No schema_version — check for id + subject to classify as ClaudeTask.
        let hasID = (json["id"] as? String).map { !$0.isEmpty } ?? false
        let hasSubject = (json["subject"] as? String).map { !$0.isEmpty } ?? false

        guard hasID && hasSubject else {
            let error = ParserError.missingRequiredFields(filename: filename)
            logger.warning("Task file \(filename) missing id or subject (no schema_version)")
            return .orphaned(OrphanedTask.make(filename: filename, error: error, data: data))
        }

        do {
            var claudeTask = try Self.decoder.decode(ClaudeTask.self, from: data)
            claudeTask.sourceFile = filename
            return .claude(claudeTask)
        } catch {
            logger.warning("Failed to decode ClaudeTask \(filename): \(error)")
            return .orphaned(OrphanedTask.make(filename: filename, error: error, data: data))
        }
    }

    /// Sorts tasks by numeric ID when all IDs are numeric strings; otherwise sorts lexicographically.
    private func sortedByID(_ items: [TaskItem]) -> [TaskItem] {
        let allNumeric = items.allSatisfy { Int($0.id) != nil }
        if allNumeric {
            return items.sorted { (Int($0.id) ?? 0) < (Int($1.id) ?? 0) }
        }
        return items.sorted { $0.id < $1.id }
    }
}

// MARK: - Local error types

private enum ParserError: LocalizedError {
    case invalidJSON(filename: String)
    case missingRequiredFields(filename: String)
    case malformedMetadata(filename: String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let filename):
            return "File '\(filename)' does not contain valid JSON."
        case .missingRequiredFields(let filename):
            return "File '\(filename)' is missing required fields 'id' or 'subject'."
        case .malformedMetadata(let filename):
            return "File '\(filename)' has a 'metadata' field that is not a JSON object."
        }
    }
}

// MARK: - FileClassification

extension TaskParserService {
    /// The three possible outcomes when parsing a single JSON task file.
    enum FileClassification: Sendable {
        case structured(TaskItem)
        case claude(ClaudeTask)
        case orphaned(OrphanedTask)
    }
}
