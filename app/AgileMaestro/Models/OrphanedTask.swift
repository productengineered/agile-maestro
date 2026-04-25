import Foundation

/// Represents a task file that could not be parsed due to malformation or corruption.
///
/// OrphanedTask preserves enough information for the user to diagnose why a file
/// failed to load: the filename for identification, the error message explaining
/// the failure, any partial fields that could be extracted before failure, and
/// the raw file contents for manual inspection.
struct OrphanedTask: Identifiable, Equatable, Sendable {

    /// The task file's filename, used as the stable identifier.
    let filename: String

    /// A human-readable description of why the file could not be parsed.
    let errorMessage: String

    /// Any string-valued fields that could be extracted from the file before parsing failed.
    /// Keys are field names (e.g., "id", "subject", "status"); values are their raw string representations.
    let partialFields: [String: String]

    /// The raw contents of the file, capped at 100 KB to prevent excessive memory usage.
    let rawJSON: String

    // MARK: - Identifiable

    var id: String { filename }

    // MARK: - Factory

    /// Creates an OrphanedTask from a filename, parse error, and optional raw file data.
    ///
    /// - Parameters:
    ///   - filename: The name of the file that failed to parse (not the full path).
    ///   - error: The error that occurred during parsing.
    ///   - data: The raw bytes of the file, if available. Capped at 100 KB when converting to a string.
    /// - Returns: An OrphanedTask capturing the failure information.
    static func make(filename: String, error: Error, data: Data?) -> OrphanedTask {
        let rawJSON: String
        if let data {
            let capped = data.prefix(100 * 1024)
            rawJSON = String(bytes: capped, encoding: .utf8)
                ?? String(bytes: capped, encoding: .isoLatin1)
                ?? "<binary data>"
        } else {
            rawJSON = ""
        }

        let partialFields = Self.extractPartialFields(from: data)

        return OrphanedTask(
            filename: filename,
            errorMessage: error.localizedDescription,
            partialFields: partialFields,
            rawJSON: rawJSON
        )
    }

    // MARK: - Private helpers

    /// Attempts a best-effort extraction of top-level string fields from raw JSON data.
    /// Returns an empty dictionary if extraction fails at any point.
    private static func extractPartialFields(from data: Data?) -> [String: String] {
        guard let data else { return [:] }
        let capped = data.prefix(100 * 1024)
        guard let json = try? JSONSerialization.jsonObject(with: capped) as? [String: Any] else {
            return [:]
        }
        var fields: [String: String] = [:]
        for (key, value) in json {
            switch value {
            case let string as String:
                fields[key] = string
            case let bool as Bool:
                fields[key] = bool ? "true" : "false"
            case let number as NSNumber:
                fields[key] = number.stringValue
            default:
                // Intentionally skip arrays and dictionaries.
                // partialFields is string-only for display purposes; nested
                // structures are already available in rawJSON for manual inspection.
                break
            }
        }
        return fields
    }
}
