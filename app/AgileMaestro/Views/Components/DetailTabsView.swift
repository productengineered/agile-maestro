import SwiftUI

// MARK: - DetailTabsView

/// Horizontal scrolling pill bar for tab navigation within the detail panel.
///
/// Displays all tabs available for the current `task.type` per the Tab Availability
/// Matrix (UX Flows Section 1 / SM-TAB-001). Pills are intrinsic-size — they are
/// never stretched to fill available width.
///
/// **Tab selection (IS-TABS-001):** Tapping a pill calls
/// `withAnimation(.easeInOut(duration: 0.2))` before setting `viewModel.activeTab`.
///
/// **Accessibility:** Active pill: "[name] tab, selected" (no hint).
/// Inactive pill: "[name] tab" + "Switch to [name] view" hint.
///
/// **Keyboard:** Each pill is `.focusable()` and responds to Space / Return.
struct DetailTabsView: View {

    @Environment(DetailViewModel.self) private var viewModel

    let task: TaskItem

    // MARK: - Computed

    private var availableTabs: [DetailTab] {
        DetailTab.availableTabs(for: task.type)
    }

    private var commentCount: Int {
        task.comments.count
    }

    // MARK: - Body

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(availableTabs) { tab in
                    TabPillButton(
                        tab: tab,
                        isSelected: viewModel.activeTab == tab,
                        badge: tab == .comments ? commentCount : nil,
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.activeTab = tab
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - TabPillButton

/// A single tab pill within `DetailTabsView`.
///
/// Renders an icon + label inside a `Capsule` background.
/// - Selected: `.accentColor` fill, white label
/// - Unselected: `secondary.opacity(0.08)` fill, `.secondary` label
private struct TabPillButton: View {

    let tab: DetailTab
    let isSelected: Bool
    /// Optional badge count. Pass `nil` to suppress the badge entirely.
    /// A value of 0 is also suppressed (badge only shows when count > 0).
    let badge: Int?
    let onTap: () -> Void

    // MARK: - Focus State

    @FocusState private var isFocused: Bool

    // MARK: - Accessibility

    /// Badge count announced to VoiceOver when count > 0 (e.g. "3 comments").
    private var badgeAccessibilityValue: String {
        guard let count = badge, count > 0 else { return "" }
        let unit = tab == .comments ? (count == 1 ? "comment" : "comments") : ""
        return unit.isEmpty ? "\(count)" : "\(count) \(unit)"
    }

    // MARK: - Body

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11, weight: .medium))
                    .symbolRenderingMode(.hierarchical)

                Text(tab.label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))

                if let count = badge, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.secondary.opacity(0.12))
                        )
                }
            }
            .foregroundStyle(isSelected ? .white : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        // IS-TABS-001 accessibility
        .accessibilityLabel(isSelected ? "\(tab.label) tab, selected" : "\(tab.label) tab")
        .accessibilityValue(badgeAccessibilityValue)
        .accessibilityHint(isSelected ? "" : "Switch to \(tab.label) view")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        // Animate pill background on selection state change
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Preview

#Preview("DetailTabsView — Task (5 tabs)") {
    let json = """
    {
      "id": "1", "subject": "Task: Add unit tests", "description": "",
      "status": "in_progress", "blocks": [], "blockedBy": [],
      "metadata": { "type": "task", "priority": "P2", "approval": "approved", "blocked": false }
    }
    """
    guard let task = try? JSONDecoder().decode(TaskItem.self, from: Data(json.utf8)) else {
        return AnyView(Text("Preview: failed to decode TaskItem"))
    }
    let vm = DetailViewModel()

    return AnyView(
        DetailTabsView(task: task)
            .environment(vm)
            .padding()
            .frame(width: 600)
    )
}

#Preview("DetailTabsView — Epic (5 tabs)") {
    let json = """
    {
      "id": "2", "subject": "Epic: Detail Panel", "description": "",
      "status": "in_progress", "blocks": [], "blockedBy": [],
      "metadata": { "type": "epic", "priority": "P1", "approval": "approved", "blocked": false }
    }
    """
    guard let task = try? JSONDecoder().decode(TaskItem.self, from: Data(json.utf8)) else {
        return AnyView(Text("Preview: failed to decode TaskItem"))
    }
    let vm = DetailViewModel()

    return AnyView(
        DetailTabsView(task: task)
            .environment(vm)
            .padding()
            .frame(width: 600)
    )
}

#Preview("DetailTabsView — Bug (3 tabs)") {
    let json = """
    {
      "id": "3", "subject": "Bug: Fix crash on launch", "description": "",
      "status": "pending", "blocks": [], "blockedBy": [],
      "metadata": { "type": "bug", "priority": "P0", "approval": "approved", "blocked": false }
    }
    """
    guard let task = try? JSONDecoder().decode(TaskItem.self, from: Data(json.utf8)) else {
        return AnyView(Text("Preview: failed to decode TaskItem"))
    }
    let vm = DetailViewModel()

    return AnyView(
        DetailTabsView(task: task)
            .environment(vm)
            .padding()
            .frame(width: 600)
    )
}
