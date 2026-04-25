import SwiftUI

// MARK: - StatusPill

/// Displays task status in a compact capsule badge.
/// Used in DetailHeaderView and Epic stories table.
/// Color strategy: semantic (gray/blue/green) — one circle dot + label per status.
struct StatusPill: View {
    let status: TaskStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            Text(statusLabel)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.12), in: Capsule())
        .accessibilityLabel("Status: \(statusLabel)")
    }

    // MARK: - Private

    private var statusLabel: String {
        switch status {
        case .pending:    return "Pending"
        case .inProgress: return "In Progress"
        case .completed:  return "Completed"
        }
    }

    private var statusColor: Color {
        switch status {
        case .pending:    return .secondary
        case .inProgress: return .blue
        case .completed:  return .green
        }
    }
}

// MARK: - Preview

#Preview("StatusPill — All States") {
    HStack(spacing: 8) {
        StatusPill(status: .pending)
        StatusPill(status: .inProgress)
        StatusPill(status: .completed)
    }
    .padding()
}
