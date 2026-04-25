import Foundation

// MARK: - BugDescriptionParser

/// Parses a bug task description string into its constituent sections.
///
/// Bug descriptions are expected to contain one or more of the following level-2
/// markdown headings. Each property uses a fallback alias chain so that minor
/// heading variants (e.g. "Steps" or "Repro" instead of "Steps to Reproduce")
/// are still matched by `MarkdownSectionParser.body(for:in:)`.
///
/// | Property          | Primary heading          | Aliases                  |
/// |-------------------|--------------------------|--------------------------|
/// | `summary`         | "Summary"                | —                        |
/// | `steps`           | "Steps to Reproduce"     | "Steps", "Repro"         |
/// | `expected`        | "Expected Behavior"      | "Expected"               |
/// | `actual`          | "Actual Behavior"        | "Actual"                 |
/// | `severity`        | "Severity"               | —                        |
/// | `discoveryContext`| "Discovery Context"      | "Context"                |
///
/// Example usage:
/// ```swift
/// let parser = BugDescriptionParser(description: task.description)
/// if let summary = parser.summary { ... }
/// ```
struct BugDescriptionParser {

    // MARK: - Stored Properties

    /// The raw markdown description string passed at initialisation.
    let description: String

    // MARK: - Initialisation

    /// Creates a parser for the given bug description string.
    ///
    /// - Parameter description: The full markdown description of the bug task.
    init(description: String) {
        self.description = description
    }

    // MARK: - Parsed Properties

    /// The "Summary" section body, or `nil` if the heading is absent or empty.
    var summary: String? {
        MarkdownSectionParser.body(for: "Summary", in: description)
    }

    /// The reproduction steps section body.
    ///
    /// Resolves via the alias chain:
    /// "Steps to Reproduce" → "Steps" → "Repro"
    var steps: String? {
        MarkdownSectionParser.body(for: "Steps to Reproduce", in: description) ??
        MarkdownSectionParser.body(for: "Steps", in: description) ??
        MarkdownSectionParser.body(for: "Repro", in: description)
    }

    /// The expected-behavior section body.
    ///
    /// Resolves via the alias chain: "Expected Behavior" → "Expected"
    var expected: String? {
        MarkdownSectionParser.body(for: "Expected Behavior", in: description) ??
        MarkdownSectionParser.body(for: "Expected", in: description)
    }

    /// The actual-behavior section body.
    ///
    /// Resolves via the alias chain: "Actual Behavior" → "Actual"
    var actual: String? {
        MarkdownSectionParser.body(for: "Actual Behavior", in: description) ??
        MarkdownSectionParser.body(for: "Actual", in: description)
    }

    /// The "Severity" section body, or `nil` if the heading is absent or empty.
    var severity: String? {
        MarkdownSectionParser.body(for: "Severity", in: description)
    }

    /// The discovery context section body.
    ///
    /// Resolves via the alias chain: "Discovery Context" → "Context"
    var discoveryContext: String? {
        MarkdownSectionParser.body(for: "Discovery Context", in: description) ??
        MarkdownSectionParser.body(for: "Context", in: description)
    }

    // MARK: - Derived

    /// `true` when at least one known section heading was matched.
    ///
    /// Used by `BugDescriptionContent` to decide between the typed layout and the
    /// generic `FallbackDescriptionContent` fallback.
    var hasKnownSections: Bool {
        summary != nil || steps != nil || expected != nil ||
        actual != nil || severity != nil || discoveryContext != nil
    }
}
