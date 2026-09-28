import SwiftUI

// MARK: - TreeRowView

/// Single row in the task tree sidebar.
///
/// Renders: indentation spacer, chevron (if parent node), TypeIconView, number
/// label (`task.id`, matching the `.json` filename), title text, spacer, child
/// count badge (if parent node), and StatusDotView.
///
/// The number leads the subject (e.g. "88 - TechDebt: sign-in...") so LLM agents
/// and users can match a row to its task file at a glance. It is pinned to a fixed
/// size and given layout priority so it never truncates — only the subject does.
///
/// Responds to selection (`.accentColor.opacity(0.15)` background) and hover
/// (`.secondary.opacity(0.05)` background) state changes with animated fills.
///
/// The chevron animates 90° on expand/collapse via `node.isExpanded`.
/// Tapping the row (outside the chevron) calls `onSelect`.
struct TreeRowView: View {

    // MARK: - Properties

    let node: TreeNode
    let indentLevel: Int
    let isSelected: Bool
    let onSelect: () -> Void
    /// Called when the user taps the chevron. Routes through the ViewModel so
    /// expand state is persisted to UserDefaults via `TreeViewModel.toggleExpand(node:)`.
    let onToggleExpand: (() -> Void)?

    @State private var isHovered = false

    // MARK: - Body

    var body: some View {
        HStack(spacing: 6) {
            indentationSpacer

            chevronOrPlaceholder

            TypeIconView(type: node.task.type, size: 11)
                .accessibilityHidden(true)

            numberLabel

            Text(node.task.subject)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            if node.hasChildren {
                childCountBadge
            }

            StatusDotView(status: node.task.status)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(minHeight: 28)
        .background(rowBackground)
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture(perform: onSelect)
        .onHover { hovered in
            isHovered = hovered
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel)
        .accessibilityHint("Double tap to select")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Subviews

    @ViewBuilder
    private var indentationSpacer: some View {
        if indentLevel > 0 {
            Spacer()
                .frame(width: CGFloat(indentLevel) * 16)
        }
    }

    @ViewBuilder
    private var chevronOrPlaceholder: some View {
        if node.hasChildren {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    onToggleExpand?()
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(node.isExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.2), value: node.isExpanded)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                node.isExpanded
                    ? "Collapse \(node.task.subject)"
                    : "Expand \(node.task.subject)"
            )
            .accessibilityHint(
                node.isExpanded
                    ? "Double tap to collapse"
                    : "Double tap to expand"
            )
        } else {
            Spacer()
                .frame(width: 24)
        }
    }

    /// The row's leading number (`task.id`, matching the `.json` filename). Uses
    /// the same token treatment as the detail card's number badge (caption,
    /// medium weight, tertiary, monospaced digits) for visual consistency.
    /// `.fixedSize` + `.layoutPriority(1)` guarantee it never truncates or
    /// compresses — only `subject` gives up space when the row is narrow.
    private var numberLabel: some View {
        Text("\(node.task.id) -")
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.tertiary)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
    }

    private var childCountBadge: some View {
        Text("\(node.children.count)")
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.secondary.opacity(0.12))
            )
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(
                isSelected
                    ? Color.accentColor.opacity(0.15)
                    : isHovered
                        ? Color.secondary.opacity(0.05)
                        : Color.clear
            )
            .animation(.easeInOut(duration: 0.15), value: isSelected)
            .animation(.easeInOut(duration: 0.12), value: isHovered)
    }

    // MARK: - Accessibility Label

    private var rowAccessibilityLabel: String {
        let type = node.task.type.displayName
        let status = node.task.status.displayName
        let base = "\(node.task.numberedSubject), \(type), \(status)"
        if node.hasChildren {
            let expandState = node.isExpanded ? "expanded" : "collapsed"
            return "\(base), \(expandState), \(node.children.count) children"
        }
        return base
    }
}

// MARK: - Preview

#Preview("TreeRowView — States") {
    let epicJSON = """
    {
      "id": "1", "subject": "Epic: App Shell and Toolbar UI", "description": "",
      "status": "in_progress", "blocks": [], "blockedBy": [],
      "metadata": { "type": "epic", "priority": "P1", "approval": "approved", "blocked": false }
    }
    """
    let storyJSON = """
    {
      "id": "2", "subject": "Story: Tree Sidebar with Expand/Collapse", "description": "",
      "status": "pending", "blocks": [], "blockedBy": [],
      "metadata": { "type": "story", "priority": "P2", "approval": "approved", "blocked": false }
    }
    """
    let taskJSON = """
    {
      "id": "3", "subject": "Task: Create TreeRowView component", "description": "",
      "status": "completed", "blocks": [], "blockedBy": [],
      "metadata": { "type": "task", "priority": "P2", "approval": "approved", "blocked": false }
    }
    """

    let makeNode: (String) -> TreeNode? = { json in
        guard let data = json.data(using: .utf8),
              let item = try? JSONDecoder().decode(TaskItem.self, from: data) else { return nil }
        return TreeNode(task: item)
    }

    guard let epicItem = makeNode(epicJSON),
          let storyItem = makeNode(storyJSON),
          let taskItem = makeNode(taskJSON) else { return Text("Preview data error") }
    epicItem.children = [storyItem, taskItem]
    epicItem.isExpanded = true

    return VStack(alignment: .leading, spacing: 0) {
        Text("Default")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 8)

        TreeRowView(node: epicItem, indentLevel: 0, isSelected: false, onSelect: {}, onToggleExpand: {
            epicItem.isExpanded.toggle()
        })

        Text("Selected")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 8)

        TreeRowView(node: storyItem, indentLevel: 1, isSelected: true, onSelect: {}, onToggleExpand: {
            storyItem.isExpanded.toggle()
        })

        Text("Leaf (no chevron)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 8)

        TreeRowView(node: taskItem, indentLevel: 2, isSelected: false, onSelect: {}, onToggleExpand: nil)
    }
    .frame(width: 260)
    .padding(4)
}
