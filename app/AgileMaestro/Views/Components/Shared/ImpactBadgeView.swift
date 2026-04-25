import SwiftUI

// MARK: - ImpactBadgeView

/// Displays risk or impact level in a colored badge.
/// Used in PlanningTabView risk cards.
/// Supported values: "high", "medium", "low", "critical" (all case-insensitive).
/// Any unrecognized input (e.g. "urgent") normalizes to "unknown".
/// Color mapping: high=red, medium=orange, low=green, critical=red, unknown=secondary.
struct ImpactBadgeView: View {
    let level: String  // "high", "medium", "low", "critical" (case-insensitive)

    // MARK: - Computed Properties

    /// Maps the raw input to a closed set: "high", "medium", "low", "critical", "unknown".
    /// Any unrecognized input (including whitespace variants) maps to "unknown".
    private var normalizedLevel: String {
        let trimmed = level.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch trimmed {
        case "high", "medium", "low", "critical": return trimmed
        default: return "unknown"
        }
    }

    private var displayText: String {
        normalizedLevel.capitalized
    }

    private var levelColor: Color {
        switch normalizedLevel {
        case "high":     return .red
        case "medium":   return .orange
        case "low":      return .green
        case "critical": return .red
        default:         return .secondary
        }
    }

    var body: some View {
        Text(displayText)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(levelColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(levelColor.opacity(0.12), in: Capsule())
            .accessibilityLabel("Impact: \(displayText)")
    }
}

// MARK: - Preview

#Preview("ImpactBadgeView — All Levels") {
    HStack(spacing: 8) {
        ImpactBadgeView(level: "high")
        ImpactBadgeView(level: "medium")
        ImpactBadgeView(level: "low")
        ImpactBadgeView(level: "critical")
        ImpactBadgeView(level: "unknown")
    }
    .padding()
}
