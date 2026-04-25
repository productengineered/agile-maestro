import SwiftUI

// MARK: - ClaudeTaskDetailView

/// Read-only detail panel for a selected `ClaudeTask`.
///
/// Layout (top to bottom inside a ScrollView):
/// 1. **Header** — task ID chip + subject title + status pill + clickable filename link
/// 2. **Description** — full text in a `CardView`, hidden when nil
/// 3. **Dependencies** — Blocks and Blocked By sections as ID chips,
///    hidden when both lists are empty
/// 4. **Other Fields** — monospace key-value pairs for every entry in
///    `rawFields`; the entire card is hidden when `rawFields` is empty
struct ClaudeTaskDetailView: View {

    @Environment(SessionViewModel.self) private var sessionViewModel

    let task: ClaudeTask

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                // 1. Header
                headerSection

                // 2. Description
                if let description = task.description, !description.isEmpty {
                    descriptionCard(description)
                }

                // 3. Dependencies
                if !task.blocks.isEmpty || !task.blockedBy.isEmpty {
                    dependenciesSection
                }

                // 4. Other Fields
                if !task.rawFields.isEmpty {
                    otherFieldsCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - File URL

    private var taskFileURL: URL? {
        guard let sessionPath = sessionViewModel.selectedSession?.path else { return nil }
        // Use the actual filename recorded during parsing, not a derived "\(id).json"
        // path — Claude task filenames may differ from their task ID.
        let filename = task.sourceFile ?? "\(task.id).json"
        return sessionPath.appendingPathComponent(filename)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            // ID chip
            Text(verbatim: "#\(task.id)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.tertiary)
                .monospacedDigit()

            // Subject
            Text(task.subject.isEmpty ? "(No subject)" : task.subject)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            // Status pill
            if let status = task.status {
                ClaudeTaskStatusPill(status: status)
            }

            // Clickable filename link
            if let fileURL = taskFileURL {
                ClaudeTaskFilePathLink(fileName: fileURL.lastPathComponent, fileURL: fileURL)
            }
        }
    }

    // MARK: - Description

    private func descriptionCard(_ text: String) -> some View {
        CardView(title: "Description", icon: "text.alignleft", iconColor: .secondary) {
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Dependencies

    private var dependenciesSection: some View {
        HStack(alignment: .top, spacing: 12) {
            if !task.blocks.isEmpty {
                dependencyCard(
                    title: "Blocks",
                    icon: "arrow.forward.circle",
                    iconColor: .blue,
                    ids: task.blocks
                )
            }
            if !task.blockedBy.isEmpty {
                dependencyCard(
                    title: "Blocked By",
                    icon: "arrow.backward.circle",
                    iconColor: .orange,
                    ids: task.blockedBy
                )
            }
        }
    }

    private func dependencyCard(
        title: String,
        icon: String,
        iconColor: Color,
        ids: [String]
    ) -> some View {
        CardView(title: title, icon: icon, iconColor: iconColor) {
            FlowLayout(spacing: 6) {
                ForEach(ids, id: \.self) { rawId in
                    DependencyChip(id: rawId)
                }
            }
        }
    }

    // MARK: - Other Fields

    private var otherFieldsCard: some View {
        CardView(title: "Other Fields", icon: "ellipsis.curlybraces", iconColor: .secondary) {
            VStack(alignment: .leading, spacing: 0) {
                let sortedKeys = task.rawFields.keys.sorted()
                ForEach(Array(sortedKeys.enumerated()), id: \.element) { index, key in
                    OtherFieldRow(
                        key: key,
                        value: task.rawFields[key]?.displayString ?? "null"
                    )
                    if index < sortedKeys.count - 1 {
                        Divider()
                            .padding(.vertical, 4)
                    }
                }
            }
        }
    }
}

// MARK: - ClaudeTaskStatusPill

/// Status capsule badge for a raw `ClaudeTask` status string.
///
/// Unlike `StatusPill` (which requires a `TaskStatus` enum value), this view
/// accepts the raw string from `ClaudeTask.status` and maps it to a display
/// label and color. Unknown status values render in a neutral `.secondary` style.
private struct ClaudeTaskStatusPill: View {

    let status: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(pillColor)
                .frame(width: 6, height: 6)

            Text(pillLabel)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(pillColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(pillColor.opacity(0.12), in: Capsule())
        .accessibilityLabel("Status: \(pillLabel)")
    }

    private var pillLabel: String {
        switch status {
        case "pending":     return "Pending"
        case "in_progress": return "In Progress"
        case "completed":   return "Completed"
        default:            return status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private var pillColor: Color {
        switch status {
        case "pending":     return .secondary
        case "in_progress": return .blue
        case "completed":   return .green
        default:            return .secondary
        }
    }
}

// MARK: - DependencyChip

/// A non-interactive rounded chip displaying a raw task ID.
private struct DependencyChip: View {

    let id: String

    var body: some View {
        Text(verbatim: "#\(id)")
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel("Task \(id)")
    }
}

// MARK: - ClaudeTaskFilePathLink

/// A tappable row showing the task JSON filename. Clicking opens the file
/// in the system's default application. Mirrors `TaskFilePathLink` in DetailHeaderView.
private struct ClaudeTaskFilePathLink: View {

    let fileName: String
    let fileURL: URL

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.text")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Text(fileName)
                .font(.caption2)
                .foregroundStyle(isHovered ? .secondary : .tertiary)
                .underline(isHovered)
                .animation(.easeInOut(duration: 0.1), value: isHovered)
        }
        .onTapGesture {
            NSWorkspace.shared.open(fileURL)
        }
        .onHover { hovered in
            isHovered = hovered
            if hovered {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onDisappear {
            if isHovered {
                NSCursor.pop()
                isHovered = false
            }
        }
        .help(fileURL.path)
        .accessibilityLabel("Open task file \(fileName)")
        .accessibilityHint("Opens \(fileURL.path) in the default application")
    }
}

// MARK: - OtherFieldRow

/// A single monospace key-value row used in the Other Fields card.
private struct OtherFieldRow: View {

    let key: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 80, alignment: .leading)
                .textSelection(.enabled)

            Text(value)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(key): \(value)")
    }
}

// MARK: - Preview

#Preview("ClaudeTaskDetailView — Full") {
    let task = ClaudeTask(
        id: "215",
        subject: "Task: Define ClaudeTask model type",
        description: """
            ## What
            Define ClaudeTask struct with id, subject, description, status, \
            blocks, blockedBy, and rawFields.

            ## Why
            The sidebar needs a typed model for plain Claude task JSON files.
            """,
        status: "completed",
        blocks: ["228"],
        blockedBy: ["212"],
        rawFields: [
            "metadata": .dictionary(["schema_version": .string("2.0"), "type": .string("task")])
        ]
    )
    return ClaudeTaskDetailView(task: task)
        .frame(width: 600, height: 500)
        .background(Color(.windowBackgroundColor))
        .environment(SessionViewModel())
}

#Preview("ClaudeTaskDetailView — Minimal") {
    let task = ClaudeTask(
        id: "999",
        subject: "Simple task",
        description: nil,
        status: "pending",
        blocks: [],
        blockedBy: [],
        rawFields: [:]
    )
    return ClaudeTaskDetailView(task: task)
        .frame(width: 600, height: 300)
        .background(Color(.windowBackgroundColor))
        .environment(SessionViewModel())
}
