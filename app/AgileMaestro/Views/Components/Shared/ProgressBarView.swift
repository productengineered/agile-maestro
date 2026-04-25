import SwiftUI

// MARK: - ProgressBarView

/// Thin horizontal progress bar showing task completion percentage.
///
/// Used in the epic stories table and kanban cards. The `value` parameter is
/// clamped to `[0.0, 1.0]`. At 100% the fill switches from accent to green to
/// signal completion. The view is hidden from VoiceOver — parent rows provide
/// the accessible description (e.g., "8 of 12 tasks complete").
struct ProgressBarView: View {
    let value: Double  // 0.0 to 1.0 (clamped in init)
    let height: CGFloat

    init(value: Double, height: CGFloat = 4) {
        self.value = max(0, min(1, value))
        self.height = height
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: height)

                Capsule()
                    .fill(value >= 1.0 ? Color.green : Color.accentColor)
                    .frame(width: geo.size.width * value, height: height)
            }
        }
        .frame(height: height)
        // Accessibility: parent row covers the meaning (e.g., "8 of 12 tasks complete")
        .accessibilityHidden(true)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        // 0% — full gray track
        VStack(alignment: .leading, spacing: 4) {
            Text("0%").font(.caption).foregroundStyle(.secondary)
            ProgressBarView(value: 0.0)
        }

        // Partial — accent fill
        VStack(alignment: .leading, spacing: 4) {
            Text("60%").font(.caption).foregroundStyle(.secondary)
            ProgressBarView(value: 0.6)
        }

        // 100% — green fill
        VStack(alignment: .leading, spacing: 4) {
            Text("100%").font(.caption).foregroundStyle(.secondary)
            ProgressBarView(value: 1.0)
        }

        // Custom height
        VStack(alignment: .leading, spacing: 4) {
            Text("Custom height (8pt)").font(.caption).foregroundStyle(.secondary)
            ProgressBarView(value: 0.45, height: 8)
        }
    }
    .padding(24)
    .frame(width: 300)
}
