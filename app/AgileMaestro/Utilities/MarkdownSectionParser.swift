import Foundation

// MARK: - MarkdownSection

/// A parsed level-2 section from a markdown string.
struct MarkdownSection: Identifiable {
    let id = UUID()
    let heading: String
    let body: String
}

// MARK: - MarkdownSectionParser

/// Extracts named sections from markdown strings that use level-2 headings (## ).
struct MarkdownSectionParser {

    // MARK: - Parse All Sections

    /// Parses all level-2 (`## `) sections from a markdown string.
    ///
    /// Pre-heading content (text before the first `## ` heading) is captured as an
    /// "Overview" section if non-empty. Returns an empty array for blank input.
    ///
    /// - Parameter text: The full markdown string to parse.
    /// - Returns: An ordered array of `MarkdownSection` values.
    static func parse(_ text: String) -> [MarkdownSection] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        var sections: [MarkdownSection] = []
        let lines = text.components(separatedBy: "\n")
        var currentHeading: String?
        var currentBody: [String] = []

        for line in lines {
            if line.hasPrefix("## ") {
                // Flush previous section
                if let heading = currentHeading {
                    sections.append(MarkdownSection(
                        heading: heading,
                        body: currentBody.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    ))
                } else if !currentBody.isEmpty {
                    // Pre-heading content (rare) — attach as "Overview"
                    let trimmed = currentBody.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        sections.append(MarkdownSection(heading: "Overview", body: trimmed))
                    }
                }
                currentHeading = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                currentBody = []
            } else {
                currentBody.append(line)
            }
        }

        // Flush last section
        if let heading = currentHeading {
            sections.append(MarkdownSection(
                heading: heading,
                body: currentBody.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }

        return sections
    }

    // MARK: - Body for Heading (Case-Insensitive)

    /// Returns the body text for the first section whose heading contains `heading` (case-insensitive).
    ///
    /// This is used by `DescriptionTabView` to locate known section names like "Goal" or
    /// "Technical Approach" regardless of capitalisation or minor wording variations.
    ///
    /// - Parameters:
    ///   - heading: A substring to search for within section headings.
    ///   - text: The full markdown string to search.
    /// - Returns: The trimmed body of the matching section, or `nil` if not found or empty.
    static func body(for heading: String, in text: String) -> String? {
        let sections = parse(text)
        guard let match = sections.first(where: { section in
            section.heading.lowercased().contains(heading.lowercased())
        }) else { return nil }
        return match.body.isEmpty ? nil : match.body
    }

    // MARK: - Extract Section (Exact, Case-Sensitive)

    /// Extracts the body text of a level-2 section by exact name (case-sensitive).
    ///
    /// Given a markdown string like:
    /// ```
    /// ## What
    /// Create two utility structs.
    ///
    /// ## Why
    /// Needed by services.
    /// ```
    /// `extractSection(named: "What", from: markdown)` returns `"Create two utility structs."`.
    ///
    /// - Parameters:
    ///   - sectionName: The exact heading text (case-sensitive, without the `## ` prefix).
    ///   - markdown: The full markdown string to search.
    /// - Returns: The trimmed body of the section, or `nil` if the section is not found.
    static func extractSection(named sectionName: String, from markdown: String) -> String? {
        let lines = markdown.components(separatedBy: .newlines)
        let targetHeading = "## \(sectionName)"
        var collecting = false
        var collectedLines: [String] = []

        for line in lines {
            if line == targetHeading {
                collecting = true
                continue
            }
            if collecting {
                // Stop at the next level-2 heading.
                if line.hasPrefix("## ") {
                    break
                }
                collectedLines.append(line)
            }
        }

        guard collecting else { return nil }

        let result = collectedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}
