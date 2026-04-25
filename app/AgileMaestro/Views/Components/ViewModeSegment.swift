import SwiftUI

// MARK: - ViewModeSegment

/// Segmented picker for switching between Tree, Kanban, and Team view modes.
///
/// Placed in the `.principal` (center) toolbar position. Fixed at 180 pt wide
/// to ensure all three segments render correctly with icon and label.
///
/// The `.onChange` handler is intentionally empty — animation on mode switch
/// is applied in `MainWindowView` at the content area level.
struct ViewModeSegment: View {

    @Binding var selectedMode: ViewMode

    var body: some View {
        Picker("View mode", selection: $selectedMode) {
            Label("Tree", systemImage: "list.bullet.indent")
                .tag(ViewMode.treeDetail)
            Label("Kanban", systemImage: "rectangle.split.3x1")
                .tag(ViewMode.kanban)
            Label("Team", systemImage: "person.3")
                .tag(ViewMode.team)
        }
        .pickerStyle(.segmented)
        .frame(width: 180)
    }
}
