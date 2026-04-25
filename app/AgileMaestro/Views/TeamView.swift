import SwiftUI

// MARK: - TeamView

// Purpose: Root Team view. NavigationSplitView shell containing TeamSidebarView (sidebar)
// and the selected detail pane (GroupedRosterView, TeamWorkflowView, or DirectoryHealthView).
//
// Layout: NavigationSplitView — sidebar width 220-260pt, detail fills remainder.
// State: Driven by TeamViewModel.ViewState (SM-TEAM-001). Empty states replace the full view.
// Matches Tree view split pattern (AM-200 TaskTreeView + detail panel).
//
// Empty states (ERR-TV-001 / ERR-TV-002 / ERR-TV-003):
//   ERR-TV-001 — .idle, !hasToolkitPath: no toolkit configured (folder.badge.gearshape)
//   ERR-TV-002 — .idle, isManifestMissing: toolkit set but manifest file absent (doc.badge.exclamationmark)
//   ERR-TV-003 — .error(message): manifest parse failure (exclamationmark.triangle)
//
// TeamViewModel is injected via @Environment by AgileMaestroApp.
// SessionViewModel provides the active product for loadManifest(for:).
struct TeamView: View {
    @Environment(TeamViewModel.self) private var teamViewModel
    @Environment(SessionViewModel.self) private var sessionViewModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        Group {
            switch teamViewModel.viewState {
            case .idle:
                idleState

            case .loading:
                teamLoadingState

            case .loaded(let manifest):
                teamLoadedView(manifest: manifest)

            case .error(let message):
                teamErrorState(message: message)
            }
        }
        .task(id: sessionViewModel.selectedProduct?.id) {
            guard let product = sessionViewModel.selectedProduct else { return }
            await teamViewModel.loadManifest(for: product)
        }
    }

    // MARK: - Idle State Router (ERR-TV-001 / ERR-TV-002)

    @ViewBuilder
    private var idleState: some View {
        if teamViewModel.hasToolkitPath && teamViewModel.isManifestMissing {
            // ERR-TV-002: toolkit configured but manifest file missing
            ContentUnavailableView {
                Label("No Manifest Found", systemImage: "doc.badge.exclamationmark")
            } description: {
                Text("""
                A toolkit directory is configured but no team manifest was found. \
                Run the manifest generator script to create one.
                """)
            } actions: {
                Button("Update Team Info") {
                    guard let product = sessionViewModel.selectedProduct else { return }
                    Task { await teamViewModel.updateManifest(for: product) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .accessibilityLabel("Update team info")
                .accessibilityHint("Run the manifest generator script to create a team manifest")
            }
        } else {
            // ERR-TV-001: no toolkit configured
            teamNotConfiguredState
        }
    }

    // MARK: - Loaded State

    private func teamLoadedView(manifest: AgentManifest) -> some View {
        @Bindable var vm = teamViewModel
        return NavigationSplitView(columnVisibility: $columnVisibility) {
            TeamSidebarView(
                selectedSection: $vm.selectedSection,
                manifest: manifest
            )
        } detail: {
            detailView(for: teamViewModel.selectedSection, manifest: manifest)
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Detail Router

    @ViewBuilder
    private func detailView(for section: TeamSection, manifest: AgentManifest) -> some View {
        switch section {
        case .roster:
            GroupedRosterView(agents: teamViewModel.filteredAgents)
                .id("roster")

        case .pipeline:
            TeamWorkflowView(pipelines: teamViewModel.pipelines)
                .id("workflow")

        case .health:
            DirectoryHealthView(
                health: manifest.directoryHealth,
                generatedAt: manifest.generatedAt,
                isUpdating: teamViewModel.isUpdating,
                onUpdate: {
                    guard let product = sessionViewModel.selectedProduct else { return }
                    await teamViewModel.updateManifest(for: product)
                }
            )
            .id("health")
        }
    }

    // MARK: - Empty States

    // ERR-TV-001
    private var teamNotConfiguredState: some View {
        ContentUnavailableView {
            Label("No Toolkit Configured", systemImage: "folder.badge.gearshape")
        } description: {
            Text("Set a toolkit directory in Product Settings to see your AI team")
        } actions: {
            Button("Open Product Settings") {
                teamViewModel.showEditProduct = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .accessibilityLabel("Open Product Settings")
            .accessibilityHint("Configure a toolkit directory for this product")
        }
    }

    private var teamLoadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Loading team manifest\u{2026}")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Loading team information")
    }

    // ERR-TV-003
    private func teamErrorState(message: String) -> some View {
        ContentUnavailableView {
            Label("Manifest Corrupted", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Update Team Info") {
                guard let product = sessionViewModel.selectedProduct else { return }
                Task { await teamViewModel.updateManifest(for: product) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .accessibilityLabel("Update team info")
            .accessibilityHint("Regenerate the team manifest to fix this issue")
        }
    }
}

// MARK: - Previews

#Preview("Team View \u{2014} Loaded") {
    TeamView()
        .environment(TeamViewModel.previewLoaded())
        .environment(SessionViewModel())
        .frame(width: 1000, height: 650)
        .preferredColorScheme(.dark)
}

#Preview("Team View \u{2014} No Toolkit") {
    TeamView()
        .environment(TeamViewModel.previewIdle())
        .environment(SessionViewModel())
        .frame(width: 1000, height: 650)
        .preferredColorScheme(.light)
}

#Preview("Team View \u{2014} Loading") {
    TeamView()
        .environment(TeamViewModel.previewLoading())
        .environment(SessionViewModel())
        .frame(width: 1000, height: 650)
}

#Preview("Team View \u{2014} Error") {
    TeamView()
        .environment(TeamViewModel.previewError())
        .environment(SessionViewModel())
        .frame(width: 1000, height: 650)
}
