import SwiftUI

// MARK: - EmptyStateView

/// Full-area placeholder shown when no session is selected (SessionViewModel.state == .idle).
///
/// The toolbar chips (ProductChipMenu, SessionChipMenu, open-directory button) remain
/// visible and accessible at all times, so no duplicate action button is needed here.
/// Uses macOS 14+ ContentUnavailableView for automatic centering and VoiceOver support.
struct EmptyStateView: View {

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("No Session Selected")
            } icon: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 48))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
        } description: {
            Text("Open a directory or select a session to get started.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    EmptyStateView()
        .frame(width: 800, height: 600)
}
