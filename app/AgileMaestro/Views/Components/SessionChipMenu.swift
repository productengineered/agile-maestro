import SwiftUI

// MARK: - SessionChipMenu

/// Toolbar chip showing the currently selected session.
///
/// Displays a `text.page` icon followed by the session's `displayName`,
/// truncated to 200 pt maximum width using middle truncation to preserve
/// both the epic ID prefix and the date suffix.
///
/// Opens a dropdown `Menu` listing available sessions for the selected product.
/// Disabled when no sessions are available.
struct SessionChipMenu: View {

    @Environment(SessionViewModel.self) private var viewModel

    /// Sessions independently discovered from `~/.claude/tasks/` when
    /// `viewModel.sessions` is empty (e.g. after deleting the last product).
    @State private var discoveredSessions: [TaskSession] = []

    // MARK: - Derived

    /// The list to display: prefer viewModel.sessions when populated, otherwise
    /// fall back to independently discovered sessions.
    private var displaySessions: [TaskSession] {
        viewModel.sessions.isEmpty ? discoveredSessions : viewModel.sessions
    }

    var body: some View {
        Menu {
            sessionListSection
        } label: {
            chipLabel
        }
        .menuStyle(.button)
        .buttonStyle(ChromelessStyle())
        .disabled(displaySessions.isEmpty && viewModel.selectedSession == nil)
        .accessibilityLabel(
            viewModel.selectedSession.map { "Session: \($0.displayName)" }
                ?? "No session selected"
        )
        .accessibilityHint("Opens session menu")
        .task(id: viewModel.sessions.isEmpty) {
            guard viewModel.sessions.isEmpty else {
                discoveredSessions = []
                return
            }
            discoveredSessions = (try? await TaskSessionService.shared.getRecentSessions(maxSessions: 10)) ?? []
        }
    }

    // MARK: - Private Subviews

    @ViewBuilder
    private var sessionListSection: some View {
        if displaySessions.isEmpty {
            Text("No sessions available")
                .foregroundStyle(.secondary)
        } else {
            ForEach(displaySessions) { session in
                Button {
                    Task { await viewModel.selectSession(session) }
                } label: {
                    if viewModel.selectedSession?.id == session.id {
                        Label(session.displayName, systemImage: "checkmark")
                    } else {
                        Text(session.displayName)
                    }
                }
            }
        }
    }

    private var chipLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .symbolRenderingMode(.monochrome)
            Text(viewModel.selectedSession?.displayName ?? "No Session")
                .foregroundStyle(viewModel.selectedSession == nil ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 200, alignment: .leading)
        }
    }
}
