import SwiftUI

// MARK: - EmptyTasksView

/// Full-area placeholder shown when a session is selected but contains no task JSON files.
///
/// Rendered inside `TaskTreeView` (not as a full-window overlay) since the sidebar is
/// already visible in the loaded state. The file watcher auto-updates the tree when
/// task files appear on disk, so no manual retry action is needed.
struct EmptyTasksView: View {

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("No Tasks Found")
            } icon: {
                Image(systemName: "tray")
                    .font(.system(size: 48))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.secondary)
            }
        } description: {
            Text("No task files were found in this session. Create tasks using Claude Code to see them here.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
    }
}

// MARK: - Preview

#Preview {
    EmptyTasksView()
        .frame(width: 800, height: 600)
}
