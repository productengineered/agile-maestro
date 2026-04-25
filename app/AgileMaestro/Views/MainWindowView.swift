import SwiftUI
import os

// MARK: - MainWindowView

/// Primary container for the app shell.
///
/// Hosts the window toolbar and switches the content area between three view
/// modes (tree+detail, kanban, team) based on `selectedViewMode`. Full-window
/// state overlays (idle, loading, error) sit below the toolbar so the chips
/// remain interactive during data loads.
///
/// Product CRUD sheet/alert state lives on `SessionViewModel` so that
/// `ProductChipMenu` can drive presentation without needing view-local bindings.
struct MainWindowView: View {

    // MARK: - Environment

    @Environment(SessionViewModel.self) private var sessionViewModel
    @Environment(TreeViewModel.self) private var treeViewModel
    @Environment(KanbanViewModel.self) private var kanbanViewModel
    @Environment(DetailViewModel.self) private var detailViewModel
    @Environment(TeamViewModel.self) private var teamViewModel

    // MARK: - State

    @State private var selectedViewMode: ViewMode = .treeDetail

    // MARK: - Body

    var body: some View {
        @Bindable var vm = sessionViewModel
        contentArea
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 10) {
                        ProductChipMenu(
                            showingNewProductSheet: $vm.showingNewProductSheet,
                            showingEditProductSheet: $vm.showingEditProductSheet,
                            showingDeleteAlert: $vm.showingDeleteAlert
                        )
                        .help("Select or manage products")

                        SessionChipMenu()
                            .help("Select session")

                        Button {
                            openDirectoryPanel()
                        } label: {
                            Image(systemName: "folder.badge.plus")
                                .symbolRenderingMode(.hierarchical)
                        }
                        .help("Open a task directory")
                        .accessibilityLabel("Open directory")
                        .accessibilityHint("Opens a folder picker to load tasks from any directory")

                        Spacer()

                        ViewModeSegment(selectedMode: $selectedViewMode)

                        Spacer()

                        RefreshButton()
                            .help("Refresh current session (⌘R)")
                            .padding(.trailing, 4)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .sheet(isPresented: $vm.showingNewProductSheet) {
                NewProductSheet(sessionViewModel: sessionViewModel)
            }
            .sheet(isPresented: $vm.showingEditProductSheet) {
                if let product = sessionViewModel.selectedProduct {
                    EditProductSheet(product: product, sessionViewModel: sessionViewModel)
                }
            }
            .alert("Remove Product?", isPresented: $vm.showingDeleteAlert) {
                Button("Remove", role: .destructive) {
                    if let product = sessionViewModel.selectedProduct {
                        Task {
                            do {
                                try await sessionViewModel.removeProduct(product)
                            } catch {
                                Logger(
                                    subsystem: Bundle.main.bundleIdentifier ?? "AgileMaestro",
                                    category: "MainWindowView"
                                ).error("removeProduct failed: \(error.localizedDescription)")
                            }
                        }
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will remove the product from AgileMaestro. Task files on disk are not affected.")
            }
            .onReceive(NotificationCenter.default.publisher(for: .refreshRequested)) { _ in
                Task { await sessionViewModel.refreshCurrentSession() }
            }
            .task {
                await sessionViewModel.loadProducts()
                syncViewModels(with: sessionViewModel.tasks)
            }
            .onChange(of: sessionViewModel.lastRefreshed) { _, _ in
                syncViewModels(with: sessionViewModel.tasks)
            }
            .onChange(of: sessionViewModel.selectedSession?.id) { _, _ in
                syncViewModels(with: sessionViewModel.tasks)
            }
            .onChange(of: teamViewModel.showEditProduct) { _, newValue in
                if newValue {
                    sessionViewModel.showingEditProductSheet = true
                    teamViewModel.showEditProduct = false
                }
            }
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        switch sessionViewModel.state {
        case .idle:
            emptyStateOverlay
        case .loading:
            loadingStateOverlay
        case .error(let error):
            errorStateOverlay(error: error)
        case .loaded:
            modeContent
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .animation(.easeOut(duration: 0.25), value: sessionViewModel.state == .loaded)
        }
    }

    @ViewBuilder
    private var modeContent: some View {
        switch selectedViewMode {
        case .treeDetail:
            TreeDetailView()
        case .kanban:
            KanbanBoardView(onSelectTask: handleCardSelect)
        case .team:
            TeamView()
        }
    }

    // MARK: - Card Navigation

    /// Handles a card tap from the Kanban board.
    ///
    /// Switches the view mode to tree+detail, reveals the tapped task in the
    /// sidebar, and animates the transition. Called via the `onSelectTask` closure
    /// on `KanbanBoardView`.
    ///
    /// - Parameter task: The task that was tapped.
    private func handleCardSelect(_ task: TaskItem) {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedViewMode = .treeDetail
        }
        treeViewModel.revealTask(task.id)
    }

    // MARK: - State Overlays

    private var emptyStateOverlay: some View {
        EmptyStateView()
    }

    private var loadingStateOverlay: some View {
        LoadingStateView()
    }

    private func errorStateOverlay(error: AgileMaestroError) -> some View {
        ErrorStateView(error: error) {
            Task { await sessionViewModel.refreshCurrentSession() }
        }
    }

    // MARK: - Private Helpers

    private func syncViewModels(with tasks: [TaskItem]) {
        let sessionID = sessionViewModel.selectedSession?.id.uuidString ?? ""

        // Capture selected task ID before rebuilding so we can restore it after refresh.
        let previousTaskID = detailViewModel.selectedTask?.id

        let expandedIDs = treeViewModel.snapshotExpandedIDs()
        treeViewModel.buildTree(from: tasks, sessionID: sessionID)
        treeViewModel.restoreExpandedIDs(expandedIDs)
        treeViewModel.setClaudeTasks(
            sessionViewModel.claudeTasks,
            orphanedTasks: sessionViewModel.orphanedTasks
        )
        kanbanViewModel.setTasks(tasks)

        // Restore detail selection: re-find the task by ID in the refreshed list.
        // If the task was deleted, setTask(nil) clears the panel to the idle state.
        let restored = previousTaskID.flatMap { id in tasks.first(where: { $0.id == id }) }
        detailViewModel.setTask(restored, tasks: tasks)
    }

    private func openDirectoryPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a Claude Code tasks directory"
        panel.prompt = "Open"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await sessionViewModel.openDirectory(url: url) }
    }
}

// MARK: - TreeDetailView

/// HSplitView wrapper for the tree+detail layout.
///
/// Uses HSplitView instead of NavigationSplitView to avoid window chrome
/// integration (title positioning, toolbar partitioning, sidebar toggle injection).
struct TreeDetailView: View {

    @Environment(TreeViewModel.self) private var treeViewModel

    var body: some View {
        HSplitView {
            TaskTreeView()
                .frame(minWidth: 220, idealWidth: 250, maxWidth: 280)
            TaskDetailView()
        }
    }
}

// MARK: - Preview

#Preview {
    MainWindowView()
        .environment(SessionViewModel())
        .environment(TreeViewModel())
        .environment(KanbanViewModel())
        .environment(DetailViewModel())
        .environment(TeamViewModel())
        .frame(width: 1200, height: 800)
}
