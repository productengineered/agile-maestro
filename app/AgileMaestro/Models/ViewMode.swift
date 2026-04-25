import Foundation

// MARK: - ViewMode

/// The three primary view modes available in the main content area.
///
/// `ViewMode` drives the segmented picker in the toolbar and controls which
/// content view is displayed in `MainWindowView`. Stored as a `String` raw
/// value so it can be persisted to `UserDefaults` or `AppStorage`.
enum ViewMode: String, CaseIterable {
    case treeDetail
    case kanban
    case team

    // MARK: - Display

    /// Human-readable label shown in the `ViewModeSegment` picker.
    var label: String {
        switch self {
        case .treeDetail: return "Tree"
        case .kanban: return "Kanban"
        case .team: return "Team"
        }
    }

    /// SF Symbol name for the view mode icon in the segmented control.
    var systemImage: String {
        switch self {
        case .treeDetail: return "list.bullet.indent"
        case .kanban: return "rectangle.split.3x1"
        case .team: return "person.2"
        }
    }
}
