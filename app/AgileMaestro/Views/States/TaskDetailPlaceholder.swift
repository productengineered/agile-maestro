import SwiftUI

// MARK: - TaskDetailPlaceholder

/// Shown in the `NavigationSplitView` detail column when no task row is selected.
///
/// Guides the user toward the sidebar without blocking content. The sidebar.left icon
/// points toward the interaction area the user should engage with next.
struct TaskDetailPlaceholder: View {

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("Select a Task")
            } icon: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 48))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
        } description: {
            Text("Choose a task from the sidebar to view its details.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    TaskDetailPlaceholder()
        .frame(width: 700, height: 600)
}
