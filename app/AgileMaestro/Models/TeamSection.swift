import Foundation

// MARK: - TeamSection

/// Identifies a section in the Team sidebar.
///
/// Used by `TeamSidebarView` for navigation and by `TeamView` for detail pane routing.
/// Conforms to `RawRepresentable` so `rawValue` doubles as the display title.
enum TeamSection: String, Equatable, Hashable, Identifiable, CaseIterable {

    case roster   = "Team Roster"
    case pipeline = "Workflow"
    case health   = "Directory Health"

    // MARK: - Identifiable

    var id: Self { self }

    // MARK: - Display Properties

    /// SF Symbol name for the sidebar icon.
    ///
    /// Use `.monochrome` rendering mode — all three symbols are filled variants.
    var icon: String {
        switch self {
        case .roster:   return "person.3.fill"
        case .pipeline: return "arrow.triangle.branch"
        case .health:   return "checkmark.shield.fill"
        }
    }

    /// Human-readable title for the sidebar item (alias for `rawValue`).
    var title: String { rawValue }
}
