import SwiftUI

// MARK: - CollapsibleSectionView

/// Collapsible section for orphan Bugs / Tech Debt / Claude Tasks / Orphaned Tasks items.
///
/// Header row is tappable to expand/collapse the section. Children are
/// rendered via a generic `@ViewBuilder` content closure. Expand state
/// is controlled externally via the `isExpanded` Bool and `onToggle`
/// callback so `TreeViewModel` owns persist behavior.
///
/// Pass a `badgeColor` to tint the count badge (e.g., `.orange` for warning sections).
/// Defaults to `.tertiary` when nil.
///
/// Animation: children slide in/out with `.spring(response: 0.3)` and
/// a combined `.opacity + .scale` transition.
struct CollapsibleSectionView<Content: View>: View {

    // MARK: - Properties

    let title: String
    let count: Int
    let isExpanded: Bool
    let badgeColor: Color?
    let onToggle: () -> Void
    @ViewBuilder let content: () -> Content

    // MARK: - Init

    init(
        title: String,
        count: Int,
        isExpanded: Bool,
        badgeColor: Color? = nil,
        onToggle: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.count = count
        self.isExpanded = isExpanded
        self.badgeColor = badgeColor
        self.onToggle = onToggle
        self.content = content
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header row (tappable)
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    onToggle()
                }
            }, label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.2), value: isExpanded)

                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(1.0)

                    Text("(\(count))")
                        .font(.caption2)
                        .foregroundStyle(badgeColor.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.tertiary))
                        .monospacedDigit()

                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            })
            .buttonStyle(.plain)
            .accessibilityLabel(
                "\(title) section, \(count) items, \(isExpanded ? "expanded" : "collapsed")"
            )
            .accessibilityHint("Double tap to \(isExpanded ? "collapse" : "expand")")

            // Children with spring transition
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .transition(.opacity.combined(with: .scale(scale: 0, anchor: .top)))
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isExpanded)
            }
        }
    }
}
