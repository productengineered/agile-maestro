// swiftlint:disable file_length
import SwiftUI

// MARK: - DescriptionTabView

/// Renders description content as section cards, variant by task type.
///
/// If the description contains known section headings for the task type, the typed
/// variant is rendered (e.g. Goal/Problem/Solution/Outcomes for epics). If the
/// structure is unrecognised, `FallbackDescriptionContent` renders each `## ` section
/// as a collapsible accordion card. If the description is empty, `ContentUnavailableView`
/// is shown (ERR-DETAIL-001).
struct DescriptionTabView: View {
    let task: TaskItem

    var body: some View {
        if task.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // ERR-DETAIL-001: Empty description
            ContentUnavailableView(
                "No Description",
                systemImage: "doc.text",
                description: Text("No description has been provided for this item.")
            )
        } else {
            LazyVStack(alignment: .leading, spacing: 16) {
                switch task.type {
                case .epic:
                    EpicDescriptionContent(text: task.description)
                case .story:
                    StoryDescriptionContent(text: task.description)
                case .bug:
                    BugDescriptionContent(text: task.description)
                case .task, .techdebt:
                    TaskDescriptionContent(text: task.description)
                }
            }
        }
    }
}

// MARK: - EpicDescriptionContent

/// Epic description: Goal, Problem Statement, Solution, Outcomes.
///
/// Uses case-insensitive partial matching via `MarkdownSectionParser.body(for:in:)`
/// so headings like "## Goals" or "## Objective" are still matched.
/// Falls back to the generic `FallbackDescriptionContent` when no known sections exist.
private struct EpicDescriptionContent: View {
    let text: String

    private var goal: String? {
        MarkdownSectionParser.body(for: "Goal", in: text) ??
        MarkdownSectionParser.body(for: "Objective", in: text)
    }
    private var problem: String? {
        MarkdownSectionParser.body(for: "Problem", in: text)
    }
    private var solution: String? {
        MarkdownSectionParser.body(for: "Solution", in: text)
    }
    private var outcomes: String? {
        MarkdownSectionParser.body(for: "Outcome", in: text) ??
        MarkdownSectionParser.body(for: "Result", in: text)
    }

    private var hasKnownSections: Bool {
        goal != nil || problem != nil || solution != nil || outcomes != nil
    }

    var body: some View {
        if hasKnownSections {
            if let goal {
                DescriptionCard(
                    title: "Goal",
                    icon: "target",
                    iconColor: .accentColor,
                    text: goal,
                    accentBar: true
                )
            }
            if let problem {
                DescriptionCard(
                    title: "Problem Statement",
                    icon: "exclamationmark.triangle",
                    iconColor: .orange,
                    text: problem,
                    accentBar: false
                )
            }
            if let solution {
                DescriptionCard(
                    title: "Solution",
                    icon: "lightbulb",
                    iconColor: .yellow,
                    text: solution,
                    accentBar: false
                )
            }
            if let outcomes {
                DescriptionCard(
                    title: "Outcomes",
                    icon: "chart.line.uptrend.xyaxis",
                    iconColor: .green,
                    text: outcomes,
                    accentBar: false
                )
            }
        } else {
            FallbackDescriptionContent(text: text)
        }
    }
}

// MARK: - StoryDescriptionContent

/// Story description: User Story, Context, Technical Approach, Dependencies.
private struct StoryDescriptionContent: View {
    let text: String

    private var userStory: String? {
        MarkdownSectionParser.body(for: "User Story", in: text) ??
        MarkdownSectionParser.body(for: "Story", in: text)
    }
    private var context: String? {
        MarkdownSectionParser.body(for: "Context", in: text) ??
        MarkdownSectionParser.body(for: "Background", in: text)
    }
    private var approach: String? {
        MarkdownSectionParser.body(for: "Technical Approach", in: text) ??
        MarkdownSectionParser.body(for: "Approach", in: text) ??
        MarkdownSectionParser.body(for: "Implementation", in: text)
    }
    private var dependencies: String? {
        MarkdownSectionParser.body(for: "Dependencies", in: text)
    }

    private var hasKnownSections: Bool {
        userStory != nil || context != nil || approach != nil || dependencies != nil
    }

    var body: some View {
        if hasKnownSections {
            if let userStory {
                DescriptionCard(
                    title: "User Story",
                    icon: "person.fill",
                    iconColor: .accentColor,
                    text: userStory,
                    accentBar: true
                )
            }
            if let context {
                DescriptionCard(
                    title: "Context",
                    icon: "info.circle",
                    iconColor: .blue,
                    text: context,
                    accentBar: false
                )
            }
            if let approach {
                BulletListCard(
                    title: "Technical Approach",
                    icon: "hammer",
                    iconColor: .secondary,
                    text: approach
                )
            }
            if let dependencies {
                BulletListCard(
                    title: "Dependencies",
                    icon: "link",
                    iconColor: .orange,
                    text: dependencies
                )
            }
        } else {
            FallbackDescriptionContent(text: text)
        }
    }
}

// MARK: - TaskDescriptionContent

/// Task/Bug/TechDebt description: What, Why, How.
private struct TaskDescriptionContent: View {
    let text: String

    private var what: String? { MarkdownSectionParser.body(for: "What", in: text) }
    private var why: String? { MarkdownSectionParser.body(for: "Why", in: text) }
    private var how: String? { MarkdownSectionParser.body(for: "How", in: text) }

    private var hasKnownSections: Bool {
        what != nil || why != nil || how != nil
    }

    var body: some View {
        if hasKnownSections {
            if let what {
                DescriptionCard(
                    title: "What",
                    icon: "doc.text",
                    iconColor: .accentColor,
                    text: what,
                    accentBar: true
                )
            }
            if let why {
                DescriptionCard(
                    title: "Why",
                    icon: "questionmark.circle",
                    iconColor: .blue,
                    text: why,
                    accentBar: false
                )
            }
            if let how {
                BulletListCard(
                    title: "How",
                    icon: "wrench",
                    iconColor: .secondary,
                    text: how
                )
            }
        } else {
            FallbackDescriptionContent(text: text)
        }
    }
}

// MARK: - BugDescriptionContent

/// Bug description: Summary, Steps to Reproduce, Expected Behavior, Actual Behavior,
/// Severity, Discovery Context.
///
/// Steps to Reproduce renders as a numbered list card.
/// Expected/Actual render side-by-side with green/red accent bars (ERR-DP700-007 fallback).
private struct BugDescriptionContent: View {
    let text: String

    private var parser: BugDescriptionParser {
        BugDescriptionParser(description: text)
    }

    var body: some View {
        let parsed = parser
        if parsed.hasKnownSections {
            if let summary = parsed.summary {
                DescriptionCard(
                    title: "Summary",
                    icon: "ladybug",
                    iconColor: .red,
                    text: summary,
                    accentBar: true
                )
            }

            if let steps = parsed.steps {
                NumberedListCard(
                    title: "Steps to Reproduce",
                    icon: "list.number",
                    iconColor: .orange,
                    text: steps
                )
            }

            if parsed.expected != nil || parsed.actual != nil {
                HStack(alignment: .top, spacing: 12) {
                    if let expected = parsed.expected {
                        BugBehaviorCard(
                            title: "Expected Behavior",
                            icon: "checkmark.circle",
                            accentColor: .green,
                            text: expected
                        )
                    }
                    if let actual = parsed.actual {
                        BugBehaviorCard(
                            title: "Actual Behavior",
                            icon: "xmark.circle",
                            accentColor: .red,
                            text: actual
                        )
                    }
                }
            }

            if let severity = parsed.severity {
                DescriptionCard(
                    title: "Severity",
                    icon: "exclamationmark.triangle",
                    iconColor: .yellow,
                    text: severity,
                    accentBar: false
                )
            }

            if let discoveryContext = parsed.discoveryContext {
                DescriptionCard(
                    title: "Discovery Context",
                    icon: "magnifyingglass",
                    iconColor: .secondary,
                    text: discoveryContext,
                    accentBar: false
                )
            }
        } else {
            FallbackDescriptionContent(text: text)
        }
    }
}

// MARK: - NumberedListCard

/// Card that renders numbered steps for Steps to Reproduce sections.
///
/// All non-empty lines are normalized to sequential numbered rows:
/// - Lines prefixed with `"N. "` or `"N) "` are stripped and re-indexed.
/// - Lines starting with `"- "` or `"* "` are treated as numbered steps (prefix stripped).
/// - Plain lines render as body text (index nil).
private struct NumberedListCard: View {
    let title: String
    let icon: String
    let iconColor: Color
    let text: String

    private struct ListItem: Identifiable {
        let id = UUID()
        let index: Int?  // nil = plain text
        let content: String
    }

    private var items: [ListItem] {
        var result: [ListItem] = []
        var counter = 1
        let lines = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines {
            // Match "1. ", "2. ", "1) ", "2) " prefixes
            let numbered = line.range(
                of: #"^\d+[.)]\s+"#,
                options: .regularExpression
            )
            if let range = numbered {
                let content = String(line[range.upperBound...])
                result.append(ListItem(index: counter, content: content))
                counter += 1
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                // Normalize bullet lines to sequential numbered steps (CodeRabbit #4)
                let content = String(line.dropFirst(2))
                result.append(ListItem(index: counter, content: content))
                counter += 1
            } else {
                result.append(ListItem(index: nil, content: line))
            }
        }
        return result
    }

    var body: some View {
        CardView(title: title, icon: icon, iconColor: iconColor) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items) { item in
                    if let index = item.index {
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index).")
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundStyle(iconColor)
                                .frame(minWidth: 20, alignment: .trailing)
                            Text(item.content)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Text(item.content)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

// MARK: - BugBehaviorCard

/// Side-by-side card with a colored left accent bar for Expected/Actual behavior comparison.
///
/// Matches the visual pattern of `BehaviorCard` in `OverviewTabView` but scoped to
/// the description tab context.
private struct BugBehaviorCard: View {
    let title: String
    let icon: String
    let accentColor: Color
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(accentColor)
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(accentColor)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Rectangle()
                .fill(accentColor.opacity(0.2))
                .frame(height: 1)

            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
                .padding(12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(accentColor.opacity(0.35), lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(accentColor)
                .frame(width: 3)
                .cornerRadius(1.5)
                .padding(.vertical, 8)
        }
    }
}

// MARK: - DescriptionCard

/// Standard card for a description section. Optional left accent bar marks primary sections.
///
/// The accent bar is a 3pt coloured `Rectangle` placed to the left of the `CardView`.
/// `CardView` already has `frame(maxWidth: .infinity)` so the HStack fills the width
/// without requiring explicit sizing here.
private struct DescriptionCard: View {
    let title: String
    let icon: String
    let iconColor: Color
    let text: String
    let accentBar: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if accentBar {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .cornerRadius(1.5)
                    .padding(.vertical, 2)
                    .padding(.trailing, 12)
            }

            CardView(title: title, icon: icon, iconColor: iconColor) {
                Text(text)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
            }
        }
    }
}

// MARK: - BulletListCard

/// Card that renders lines as a bullet list for How / Technical Approach sections.
///
/// Lines starting with `"- "` or `"* "` become styled bullet points.
/// Plain lines render as regular body text. Nested bullets are not supported.
private struct BulletListCard: View {
    let title: String
    let icon: String
    let iconColor: Color
    let text: String

    private var lines: [String] {
        text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        CardView(title: title, icon: icon, iconColor: iconColor) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(lines, id: \.self) { line in
                    if line.hasPrefix("- ") || line.hasPrefix("* ") {
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .frame(width: 12)
                            Text(String(line.dropFirst(2)))
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Text(line)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

// MARK: - FallbackDescriptionContent

/// Fallback renderer for descriptions with no recognised section structure.
///
/// Parses all `## ` headings via `MarkdownSectionParser` and renders each as a
/// `CollapsibleCardView`. A single-expand accordion pattern is used: only one section
/// can be open at a time. Icons are cycled from a fixed set of 7 SF Symbols.
private struct FallbackDescriptionContent: View {
    let text: String

    @State private var expandedSectionId: UUID?

    private var sections: [MarkdownSection] {
        MarkdownSectionParser.parse(text)
    }

    private let fallbackIcons: [String] = [
        "doc.text", "lightbulb", "hammer", "chart.bar",
        "link", "flag", "star"
    ]

    var body: some View {
        if sections.isEmpty {
            // ERR-DETAIL-001: fallback also has nothing to show
            ContentUnavailableView(
                "No Description",
                systemImage: "doc.text",
                description: Text("No description has been provided for this item.")
            )
        } else {
            ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                CollapsibleCardView(
                    title: section.heading,
                    icon: fallbackIcons[index % fallbackIcons.count],
                    iconColor: .secondary,
                    isExpanded: Binding(
                        get: { expandedSectionId == section.id },
                        set: { expanded in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                expandedSectionId = expanded ? section.id : nil
                            }
                        }
                    )
                ) {
                    Text(section.body)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(3)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Task — What/Why/How") {
    // swiftlint:disable:next line_length
    let desc = "## What\nCreate utilities.\n\n## Why\nMarkdown benefits from visual structure.\n\n## How\n- Parse headings\n- Map to icons\n- Fallback cards"
    let taskJson = """
    {
        "id": "99",
        "subject": "Task: Preview task",
        "description": "\(desc)",
        "status": "pending",
        "blocks": [],
        "blockedBy": [],
        "metadata": {
            "schema_version": "2.0",
            "type": "task",
            "priority": "P2",
            "approval": "approved",
            "blocked": false,
            "labels": [],
            "comments": []
        }
    }
    """
    if let data = taskJson.data(using: .utf8),
       let item = try? JSONDecoder().decode(TaskItem.self, from: data) {
        ScrollView {
            DescriptionTabView(task: item)
                .padding(16)
        }
        .frame(width: 400, height: 500)
        .background(Color(.windowBackgroundColor))
    }
}

#Preview("Epic — Goal/Problem/Solution/Outcomes") {
    // swiftlint:disable:next line_length
    let desc = "## Goal\nDeliver a best-in-class detail panel.\n\n## Problem\nRaw JSON is unreadable.\n\n## Solution\nIcon-labeled cards.\n\n## Outcomes\n- Faster understanding"
    let epicJson = """
    {
        "id": "100",
        "subject": "Epic: Preview epic",
        "description": "\(desc)",
        "status": "in_progress",
        "blocks": [],
        "blockedBy": [],
        "metadata": {
            "schema_version": "2.0",
            "type": "epic",
            "priority": "P1",
            "approval": "approved",
            "blocked": false,
            "labels": [],
            "comments": []
        }
    }
    """
    if let data = epicJson.data(using: .utf8),
       let item = try? JSONDecoder().decode(TaskItem.self, from: data) {
        ScrollView {
            DescriptionTabView(task: item)
                .padding(16)
        }
        .frame(width: 400, height: 600)
        .background(Color(.windowBackgroundColor))
    }
}

#Preview("Fallback — Unknown Sections") {
    // swiftlint:disable:next line_length
    let desc = "## Introduction\nNon-standard headings.\n\n## Implementation Notes\n- Step one\n- Step two\n\n## Risk\nLow risk."
    let json = """
    {
        "id": "101",
        "subject": "Task: Custom sections",
        "description": "\(desc)",
        "status": "pending",
        "blocks": [],
        "blockedBy": [],
        "metadata": {
            "schema_version": "2.0",
            "type": "task",
            "priority": "P3",
            "approval": "pending",
            "blocked": false,
            "labels": [],
            "comments": []
        }
    }
    """
    if let data = json.data(using: .utf8),
       let item = try? JSONDecoder().decode(TaskItem.self, from: data) {
        ScrollView {
            DescriptionTabView(task: item)
                .padding(16)
        }
        .frame(width: 400, height: 500)
        .background(Color(.windowBackgroundColor))
    }
}

#Preview("Bug — Summary/Steps/Expected/Actual") {
    // swiftlint:disable:next line_length
    let desc = "## Summary\nApp crashes when tapping the save button on a draft note.\n\n## Steps to Reproduce\n1. Open the app\n2. Create a new note\n3. Type any content\n4. Tap Save\n\n## Expected Behavior\nNote is saved and user is returned to the list.\n\n## Actual Behavior\nApp crashes with EXC_BAD_ACCESS. No note is saved.\n\n## Severity\nCritical — data loss for all users.\n\n## Discovery Context\nFound during QA regression pass for AM-700."
    let bugJson = """
    {
        "id": "103",
        "subject": "Bug: App crashes on save",
        "description": "\(desc)",
        "status": "in_progress",
        "blocks": [],
        "blockedBy": [],
        "metadata": {
            "schema_version": "2.0",
            "type": "bug",
            "priority": "P0",
            "approval": "approved",
            "blocked": false,
            "labels": [],
            "comments": []
        }
    }
    """
    if let data = bugJson.data(using: .utf8),
       let item = try? JSONDecoder().decode(TaskItem.self, from: data) {
        ScrollView {
            DescriptionTabView(task: item)
                .padding(16)
        }
        .frame(width: 480, height: 700)
        .background(Color(.windowBackgroundColor))
    }
}

#Preview("Empty Description") {
    let json = """
    {
        "id": "102",
        "subject": "Task: Empty description",
        "description": "",
        "status": "pending",
        "blocks": [],
        "blockedBy": [],
        "metadata": {
            "schema_version": "2.0",
            "type": "task",
            "priority": "P3",
            "approval": "pending",
            "blocked": false,
            "labels": [],
            "comments": []
        }
    }
    """
    if let data = json.data(using: .utf8),
       let item = try? JSONDecoder().decode(TaskItem.self, from: data) {
        DescriptionTabView(task: item)
            .frame(width: 400, height: 300)
            .background(Color(.windowBackgroundColor))
    }
}
