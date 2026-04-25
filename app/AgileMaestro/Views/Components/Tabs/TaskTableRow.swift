import SwiftUI

// MARK: - TaskTableRow

/// Single row in the story's tasks table. Full-row tappable to navigate to the task.
///
/// Used by `StoryOverviewContent` inside `OverviewTabView`. Extracted to its own file to
/// keep `OverviewTabView.swift` within the 600-line file length limit.
struct TaskTableRow: View {
    let taskItem: TaskItem
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            // Status dot
            statusDot
                .frame(width: 60, alignment: .leading)

            // Task title
            Text(taskItem.subject)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)

            // Type icon
            TypeIconView(type: taskItem.type, size: 12)
                .frame(width: 60, alignment: .trailing)

            // Priority badge
            if let priority = taskItem.priority {
                Text(priority)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(priorityColor(priority))
                    .monospacedDigit()
                    .frame(width: 60, alignment: .trailing)
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 60, alignment: .trailing)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.secondary.opacity(0.05) : Color.clear)
                .animation(.easeInOut(duration: 0.12), value: isHovered)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(taskItem.subject), \(taskItem.status.rawValue)")
        .accessibilityHint("Navigate to this task")
    }

    private var statusDot: some View {
        Circle()
            .fill(taskStatusColor)
            .frame(width: 8, height: 8)
    }

    private var taskStatusColor: Color {
        switch taskItem.status {
        case .completed:  return .green
        case .inProgress: return .blue
        case .pending:    return .secondary
        }
    }

    private func priorityColor(_ priority: String) -> Color {
        switch priority {
        case "P0": return .red
        case "P1": return .orange
        case "P2": return .yellow
        default:   return .secondary
        }
    }
}
