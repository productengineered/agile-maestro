import SwiftUI

// MARK: - RefreshButton

/// Toolbar button that triggers a session reload.
///
/// Shows an `arrow.clockwise` icon that rotates continuously while
/// `viewModel.isRefreshing` is `true`. A time-ago label appears to the
/// right of the icon once the session has been refreshed at least once.
///
/// Placed in the `.automatic` (trailing) toolbar group. Responds to
/// Cmd+R via a `NotificationCenter` post (wired at scene level in
/// `AgileMaestroApp`).
struct RefreshButton: View {

    @Environment(SessionViewModel.self) private var viewModel

    var body: some View {
        Button {
            Task { await viewModel.refreshCurrentSession() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.clockwise")
                    .symbolRenderingMode(.monochrome)
                    .symbolEffect(
                        .rotate,
                        isActive: viewModel.isRefreshing
                    )

                Text(viewModel.lastRefreshedText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .opacity(viewModel.lastRefreshed == nil ? 0 : 1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Refresh")
        .accessibilityHint(
            viewModel.lastRefreshed != nil
                ? "Refreshes the current session. Last refreshed \(viewModel.lastRefreshedText)"
                : "Refreshes the current session"
        )
    }
}
