import SwiftUI

// MARK: - PriorityBadgeView

/// Displays priority level (P0–P4) in a compact colored capsule.
/// Color intensity signals urgency: P0=red, P1=orange, P2=yellow, P3=blue, P4=gray.
/// Renders nothing when `priority` is nil or empty.
struct PriorityBadgeView: View {
    let priority: String?  // Raw value: "P0", "P1", "P2", "P3", "P4"

    var body: some View {
        if let priority, !priority.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(priorityColor)
                    .symbolRenderingMode(.monochrome)

                Text(priority)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(priorityColor)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(priorityColor.opacity(0.12), in: Capsule())
            .accessibilityLabel("Priority \(priority)")
        }
    }

    // MARK: - Private

    private var priorityColor: Color {
        switch priority {
        case "P0": return .red
        case "P1": return .orange
        case "P2": return .yellow
        case "P3": return .blue
        default:   return .secondary
        }
    }
}

// MARK: - Preview

#Preview("PriorityBadgeView — All Levels") {
    HStack(spacing: 8) {
        PriorityBadgeView(priority: "P0")
        PriorityBadgeView(priority: "P1")
        PriorityBadgeView(priority: "P2")
        PriorityBadgeView(priority: "P3")
        PriorityBadgeView(priority: "P4")
        PriorityBadgeView(priority: nil)
    }
    .padding()
}
