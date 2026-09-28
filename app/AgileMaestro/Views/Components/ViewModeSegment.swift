import SwiftUI

// MARK: - ViewModeSegment

/// Segmented picker for switching between Tree, Kanban, and Team view modes.
///
/// Placed in the `.principal` (center) toolbar position. Uses `.fixedSize()` so
/// the control sizes to its intrinsic content width, ensuring all three segments
/// render correctly with icon and label without clipping or overlap.
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
        .fixedSize() // size to intrinsic content width; never compress/clip segments
    }
}
