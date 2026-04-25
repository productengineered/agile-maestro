import SwiftUI

// MARK: - ChecklistTabView (Task only)

/// Ephemeral checklist — state resets when task changes.
/// IS-CHECKLIST-001: full row is tappable, not just icon.
/// SM-CHECKLIST-001: checkedItems Set drives visual state.
struct ChecklistTabView: View {
    let task: TaskItem

    // SM-CHECKLIST-001: ephemeral local state
    @State private var checkedItems: Set<Int> = []

    private var checklist: [String] { task.metadata.task?.checklist ?? [] }

    var body: some View {
        if checklist.isEmpty {
            // ERR-DETAIL-003
            ContentUnavailableView(
                "No Checklist",
                systemImage: "checklist",
                description: Text("No checklist steps have been defined for this task.")
            )
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Header: "Checklist" + count badge
                checklistHeader
                    .padding(.bottom, 12)

                // Checklist items
                ForEach(Array(checklist.enumerated()), id: \.offset) { index, item in
                    ChecklistItemRow(
                        text: item,
                        isChecked: checkedItems.contains(index),
                        onToggle: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                if checkedItems.contains(index) {
                                    checkedItems.remove(index)
                                } else {
                                    checkedItems.insert(index)
                                }
                            }
                        }
                    )
                }
            }
            // SM-CHECKLIST-001: reset state on task change
            .task(id: task.id) {
                checkedItems = []
            }
        }
    }

    // MARK: - Checklist Header

    private var checklistHeader: some View {
        HStack(spacing: 8) {
            Text("Checklist")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            Spacer()

            // X/Y count badge (green when all done, accent otherwise)
            let allDone = !checklist.isEmpty && checkedItems.count == checklist.count
            let badgeColor: Color = allDone ? .green : .accentColor

            HStack(spacing: 4) {
                if allDone {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .symbolRenderingMode(.monochrome)
                }
                Text("\(checkedItems.count)/\(checklist.count)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(badgeColor, in: Capsule())
            .animation(.easeInOut(duration: 0.2), value: allDone)
        }
    }
}

// MARK: - ChecklistItemRow

/// Full-row tappable checklist item. IS-CHECKLIST-001.
private struct ChecklistItemRow: View {
    let text: String
    let isChecked: Bool
    let onToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 10) {
                // Toggle icon
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(isChecked ? Color.green : Color.secondary)
                    .symbolRenderingMode(isChecked ? .monochrome : .hierarchical)
                    .frame(width: 20)

                // Item text
                Text(text)
                    .font(.callout)
                    .foregroundStyle(isChecked ? Color.secondary : Color.primary)
                    .strikethrough(isChecked, color: .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.secondary.opacity(0.05) : Color.clear)
                    .animation(.easeInOut(duration: 0.12), value: isHovered)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered in isHovered = hovered }
        // Section 8 accessibility
        .accessibilityLabel("\(text), \(isChecked ? "checked" : "unchecked")")
        .accessibilityHint(isChecked ? "Tap to uncheck" : "Tap to mark complete")
        .accessibilityAddTraits(isChecked ? .isSelected : [])
    }
}

// MARK: - Preview

#Preview("ChecklistTabView - With Items") {
    let mockChecklist = [
        "Read task description and local_checks",
        "Implement the core feature",
        "Write unit tests",
        "Run SwiftLint and fix warnings",
        "Build and verify"
    ]

    // Build a minimal TaskItem for preview
    ScrollView {
        ChecklistTabView(task: PreviewTaskFactory.makeTask(checklist: mockChecklist))
            .padding(16)
    }
    .frame(width: 400, height: 500)
}

#Preview("ChecklistTabView - Empty") {
    ScrollView {
        ChecklistTabView(task: PreviewTaskFactory.makeTask(checklist: []))
            .padding(16)
    }
    .frame(width: 400, height: 300)
}

// MARK: - Preview Factory

/// Minimal factory for creating TaskItem previews without a full JSON file.
private enum PreviewTaskFactory {
    static func makeTask(checklist: [String]) -> TaskItem {
        let json = """
        {
          "id": "preview-task-001",
          "subject": "Preview Task",
          "description": "A preview task for ChecklistTabView.",
          "status": "in_progress",
          "blocks": [],
          "blockedBy": [],
          "metadata": {
            "schema_version": "2.0",
            "type": "task",
            "priority": "P2",
            "approval": "approved",
            "blocked": false,
            "checklist": \(jsonArray(checklist)),
            "local_checks": ["Build passes", "Tests pass"],
            "completion_signal": "All checks verified",
            "comments": []
          }
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // swiftlint:disable:next force_try
        return try! decoder.decode(TaskItem.self, from: Data(json.utf8))
    }

    private static func jsonArray(_ items: [String]) -> String {
        let escaped = items.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }
        return "[\(escaped.joined(separator: ", "))]"
    }
}
