import SwiftUI

// MARK: - KanbanColumnView

/// Single vertical Kanban column — header row plus a scrollable card list.
///
/// Fixed width of 180pt. Background is transparent so the board's background
/// material shows through. Uses `LazyVStack` for performance with up to ~100 cards.
/// The empty state renders a centered "No items" text (not `ContentUnavailableView`,
/// which is too heavy for a narrow column).
struct KanbanColumnView: View {
    let column: KanbanColumnDef
    let cards: [KanbanCard]
    let onSelect: (TaskItem) -> Void

    // MARK: - Column header dot color
    // Maps dotColor string from KanbanColumnDef to a SwiftUI Color.
    // All colors are semantic system colors — adapt to light/dark automatically.
    private var dotColor: Color {
        switch column.dotColor {
        case "gray":   return .secondary
        case "blue":   return .blue
        case "orange": return .orange
        case "purple": return .purple
        case "yellow": return .yellow
        case "green":  return .green
        case "red":    return .red
        case "pink":   return .pink
        case "teal":   return .teal
        case "indigo": return .indigo
        default:       return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: Column Header
            // Not interactive. Color dot + label + spacer + count badge.
            HStack(spacing: 6) {
                // Colored dot (8pt — matches StatusPill dot size from shared-components-spec)
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)

                // Column label
                Text(column.label)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                // Card count badge
                Text("\(cards.count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)
            // Accessibility: column header as a single static label
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(column.label) column, \(cards.count) items")

            // Divider under header
            Divider()
                .padding(.horizontal, 12)

            // MARK: Card List or Empty State
            if cards.isEmpty {
                // Empty state: simple "No items" text.
                // Not ContentUnavailableView — too heavy for a narrow column.
                Text("No items")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
                    .accessibilityLabel("No items in \(column.label)")
            } else {
                // Scrollable card stack.
                // ScrollView vertical per-column (not the board's horizontal scroll).
                // showsIndicators: false — individual column scroll bars clutter the board.
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(cards) { card in
                            KanbanCardView(card: card, onSelect: onSelect)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
                // Soft fade at top/bottom of column scroll to indicate overflow content
                .scrollEdgeEffectStyle(.soft, for: .top)
                .scrollEdgeEffectStyle(.soft, for: .bottom)
            }
        }
        // Fixed column width within the 160-200pt design range
        .frame(width: 180)
    }
}

// MARK: - Previews

// swiftlint:disable force_try
private func previewTaskItem(id: String, subject: String, type: String = "task") -> TaskItem {
    let json = """
    {
        "id": "\(id)",
        "subject": "\(subject)",
        "description": "",
        "status": "pending",
        "blocks": [],
        "blockedBy": [],
        "metadata": { "type": "\(type)" }
    }
    """
    let data = Data(json.utf8)
    return try! JSONDecoder().decode(TaskItem.self, from: data)
}
// swiftlint:enable force_try

#Preview("Populated Column") {
    let sampleCards = [
        KanbanCard(
            id: "task-1",
            type: .task,
            displayId: "AM-310-3",
            title: "Build KanbanCardView with type chip",
            labels: ["ui"],
            blocked: false,
            reviewResult: nil,
            progress: nil,
            completedAt: nil,
            epicDisplayId: "AM-310",
            column: "in_dev",
            taskItem: previewTaskItem(id: "task-1", subject: "Build KanbanCardView with type chip")
        ),
        KanbanCard(
            id: "task-2",
            type: .bug,
            displayId: "AM-310-5",
            title: "Fix stale selection crash on session reload",
            labels: ["bug"],
            blocked: true,
            reviewResult: nil,
            progress: nil,
            completedAt: nil,
            epicDisplayId: "AM-310",
            column: "in_dev",
            taskItem: previewTaskItem(id: "task-2", subject: "Fix stale selection crash", type: "bug")
        ),
        KanbanCard(
            id: "story-1",
            type: .story,
            displayId: "AM-400-1",
            title: "KanbanViewModel column assignment",
            labels: ["kanban"],
            blocked: false,
            reviewResult: "rejected",
            progress: KanbanProgress(completed: 2, total: 5, unit: "tasks"),
            completedAt: nil,
            epicDisplayId: "AM-400",
            column: "in_dev",
            taskItem: previewTaskItem(id: "story-1", subject: "KanbanViewModel column assignment", type: "story")
        )
    ]

    KanbanColumnView(
        column: KanbanColumnDef(id: "in_dev", label: "In Dev", dotColor: "orange"),
        cards: sampleCards,
        onSelect: { _ in }
    )
    .padding(16)
    .preferredColorScheme(.dark)
}

#Preview("Empty Column") {
    KanbanColumnView(
        column: KanbanColumnDef(id: "qa", label: "QA", dotColor: "green"),
        cards: [],
        onSelect: { _ in }
    )
    .padding(16)
    .preferredColorScheme(.light)
}

#Preview("All Columns Side by Side") {
    ScrollView(.horizontal, showsIndicators: true) {
        HStack(alignment: .top, spacing: 12) {
            KanbanColumnView(
                column: KanbanColumnDef(id: "backlog", label: "Backlog", dotColor: "gray"),
                cards: [],
                onSelect: { _ in }
            )
            KanbanColumnView(
                column: KanbanColumnDef(id: "approved", label: "Approved", dotColor: "blue"),
                cards: [],
                onSelect: { _ in }
            )
            KanbanColumnView(
                column: KanbanColumnDef(id: "in_dev", label: "In Dev", dotColor: "orange"),
                cards: [],
                onSelect: { _ in }
            )
        }
        .padding(16)
    }
}
