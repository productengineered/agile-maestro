import SwiftUI

// MARK: - LoadingStateView

/// Full-area loading indicator while tasks are being parsed from disk.
///
/// Displayed when `SessionViewModel.state == .loading`. Uses a circular `ProgressView`
/// tinted with `.accentColor` as the single focal element. The supporting label
/// ("Loading tasks...") uses `.callout`/`.secondary` to recede behind the spinner.
///
/// Transitions in with `.opacity` for a gentle appearance that avoids jarring flashes.
struct LoadingStateView: View {

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.2)
                .tint(.accentColor)

            Text("Loading tasks...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
        .accessibilityLabel("Loading tasks")
    }
}

// MARK: - Preview

#Preview {
    LoadingStateView()
        .frame(width: 800, height: 600)
}
