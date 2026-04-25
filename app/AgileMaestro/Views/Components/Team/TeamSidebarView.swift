import SwiftUI

// MARK: - TeamSidebarView

/// Left sidebar in the Team NavigationSplitView.
///
/// Displays three navigation items — Team Roster, Workflow, and Directory Health —
/// using `.listStyle(.sidebar)` for macOS Liquid Glass vibrancy treatment.
///
/// Accent color appears ONLY on the selected row via List's native selection highlight.
/// All other icons are secondary to keep visual weight focused on selection.
///
/// Conforms to SM-TEAM-001: displayed only in the `.loaded` view state.
struct TeamSidebarView: View {

    // MARK: - Properties

    @Binding var selectedSection: TeamSection
    let manifest: AgentManifest

    // MARK: - Body

    var body: some View {
        List(selection: $selectedSection) {
            sectionHeader
            navigationItems
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 260)
        .accessibilityLabel("Team navigation")
    }

    // MARK: - Section Header

    /// Uppercase tracked label matching the TaskTreeView "TASK TREE" header pattern.
    /// Decorative — hidden from VoiceOver.
    private var sectionHeader: some View {
        HStack {
            Text("TEAM")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(1.2)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .accessibilityHidden(true)
    }

    // MARK: - Navigation Items

    /// ForEach over all TeamSection cases — order determined by CaseIterable conformance.
    private var navigationItems: some View {
        ForEach(TeamSection.allCases) { section in
            Label {
                Text(section.rawValue)
                    .font(.callout)
            } icon: {
                Image(systemName: section.icon)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.secondary)
            }
            .badge(badge(for: section))
            .tag(section)
            .accessibilityLabel(accessibilityLabel(for: section))
            .accessibilityHint(accessibilityHint(for: section))
        }
    }

    // MARK: - Helpers

    /// Returns a Text badge showing the count for roster and pipeline sections.
    /// Health has no meaningful count — returns nil.
    private func badge(for section: TeamSection) -> Text? {
        switch section {
        case .roster:
            return Text("\(manifest.agents.count)")
        case .pipeline:
            return Text("\(manifest.workflowPipelines.count)")
        case .health:
            return nil
        }
    }

    /// Compound accessibility label combining the section name with a count.
    private func accessibilityLabel(for section: TeamSection) -> String {
        switch section {
        case .roster:
            return "Team Roster, \(manifest.agents.count) agents"
        case .pipeline:
            return "Workflow, \(manifest.workflowPipelines.count) pipelines"
        case .health:
            return "Directory Health"
        }
    }

    /// Contextual hint describing the content shown in each detail pane.
    private func accessibilityHint(for section: TeamSection) -> String {
        switch section {
        case .roster:   return "Shows agent cards grouped by role"
        case .pipeline: return "Shows Epic, Story, and Task workflow stages"
        case .health:   return "Shows agent, command, skill, and rule counts"
        }
    }
}

// MARK: - Previews

#Preview("TeamSidebarView — Loaded") {
    @Previewable @State var selected: TeamSection = .roster
    TeamSidebarView(
        selectedSection: $selected,
        manifest: AgentManifest.preview
    )
    .frame(width: 240, height: 400)
}

#Preview("TeamSidebarView — Pipeline Selected") {
    @Previewable @State var selected: TeamSection = .pipeline
    TeamSidebarView(
        selectedSection: $selected,
        manifest: AgentManifest.preview
    )
    .frame(width: 240, height: 400)
}

#Preview("TeamSidebarView — Health Selected") {
    @Previewable @State var selected: TeamSection = .health
    TeamSidebarView(
        selectedSection: $selected,
        manifest: AgentManifest.preview
    )
    .frame(width: 240, height: 400)
}
