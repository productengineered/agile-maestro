import SwiftUI

// MARK: - StatPillView

/// Small icon + label + value pill for stats rows in tab views.
///
/// Used in `OverviewTabView` and `PlanningTabView` stats rows. Renders a colored
/// SF Symbol icon, an uppercase secondary label, and a monospaced semibold value.
/// Exposes a combined accessibility label: `"\(label): \(value)"`.
struct StatPillView: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(iconColor)
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        // Accessibility: accessible label per UX Flows Section 8: "[label]: [value]"
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - Preview

#Preview {
    HStack(spacing: 8) {
        StatPillView(
            icon: "checkmark.circle.fill",
            iconColor: .green,
            label: "Completed",
            value: "12"
        )
        StatPillView(
            icon: "clock.fill",
            iconColor: .orange,
            label: "In Progress",
            value: "3"
        )
        StatPillView(
            icon: "circle.dashed",
            iconColor: .secondary,
            label: "Pending",
            value: "7"
        )
        StatPillView(
            icon: "percent",
            iconColor: .accentColor,
            label: "Done",
            value: "55%"
        )
    }
    .padding(24)
}
