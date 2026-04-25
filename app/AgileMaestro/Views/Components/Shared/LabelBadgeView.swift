import SwiftUI

// MARK: - LabelBadgeView

/// Displays a single label tag as a small capsule.
/// Used in kanban cards and OverviewTabView label rows.
/// Color: secondary at 12% opacity — decorative, not semantic.
struct LabelBadgeView: View {
    let label: String
    var isDecorative: Bool = false

    var body: some View {
        Text(label)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.12), in: Capsule())
            .accessibilityHidden(isDecorative)
    }
}

// MARK: - Preview

#Preview("LabelBadgeView — Examples") {
    HStack(spacing: 6) {
        LabelBadgeView(label: "infrastructure")
        LabelBadgeView(label: "phase-1")
        LabelBadgeView(label: "core-data")
        LabelBadgeView(label: "ui")
    }
    .padding()
}
