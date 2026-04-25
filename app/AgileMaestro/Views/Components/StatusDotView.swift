import SwiftUI

// MARK: - StatusDotView

/// Small colored circle indicating task status.
/// Always paired with an `.accessibilityLabel` — color is never the sole indicator.
///
/// Color mapping:
/// - `.pending`    → `.gray`
/// - `.inProgress` → `.blue`
/// - `.completed`  → `.green`
struct StatusDotView: View {
    let status: TaskStatus

    var body: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 7, height: 7)
            .accessibilityLabel(status.displayName)
    }

    // MARK: - Status Color

    private var statusColor: Color {
        switch status {
        case .pending:    return .gray
        case .inProgress: return .blue
        case .completed:  return .green
        }
    }
}

// MARK: - Preview

#Preview("StatusDotView — All Statuses") {
    VStack(alignment: .leading, spacing: 12) {
        ForEach(TaskStatus.allCases, id: \.self) { taskStatus in
            HStack(spacing: 8) {
                StatusDotView(status: taskStatus)
                Text(taskStatus.displayName)
                    .font(.callout)
            }
        }
    }
    .padding()
}
