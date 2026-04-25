import SwiftUI

// MARK: - TeamPlaceholderView

/// Full-area placeholder for Team view mode (not yet implemented).
///
/// Communicates that the Team view is planned without blocking the user.
/// Injected by `MainWindowView.modeContent` when `selectedViewMode == .team`.
struct TeamPlaceholderView: View {

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("Team View")
            } icon: {
                Image(systemName: "person.3")
                    .font(.system(size: 48))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
        } description: {
            Text("Team view is coming in a future update. Track your team's progress and assignments here.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
    }
}

// MARK: - Preview

#Preview {
    TeamPlaceholderView()
        .frame(width: 800, height: 600)
}
