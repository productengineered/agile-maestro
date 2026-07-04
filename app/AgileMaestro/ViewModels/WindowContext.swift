import Observation

// MARK: - WindowContext

/// Aggregates the per-window ViewModel graph so each app window owns an
/// independent product context (R2.1).
///
/// `WindowContext` composes the five existing ViewModels — `sessionViewModel`,
/// `treeViewModel`, `kanbanViewModel`, `detailViewModel`, and `teamViewModel` —
/// each created fresh in `init()`. It does not introduce new business logic and
/// does not duplicate app-wide singleton services (e.g. `ProductService`); those
/// remain owned by the individual ViewModels exactly as they are today.
///
/// **Ownership contract:** A `WindowContext` instance is created once per window
/// (see `AgileMaestroApp`, which currently injects the five ViewModels directly —
/// wiring `WindowContext` into the scene is tracked separately). Two `WindowContext`
/// instances never share ViewModel state: each holds its own instances, so state
/// mutated in one window's ViewModels (selected product, selected session, tree
/// expansion, kanban filters, etc.) has no effect on any other window.
///
/// **Teardown contract:** `WindowContext` holds strong references to its five
/// ViewModels for the lifetime of the owning window. When the window closes and
/// releases its `WindowContext`, all five ViewModels — and anything they retain
/// (e.g. `SessionViewModel`'s file watcher) — become eligible for deallocation.
/// `WindowContext` itself has no teardown logic of its own; it defers entirely to
/// its owned ViewModels' existing lifecycle behavior.
@Observable
@MainActor
final class WindowContext {

    // MARK: - Owned ViewModels

    /// Drives product and session selection for this window's toolbar.
    private(set) var sessionViewModel: SessionViewModel

    /// Drives the task tree for this window's selected session.
    private(set) var treeViewModel: TreeViewModel

    /// Drives the kanban board for this window's selected session.
    private(set) var kanbanViewModel: KanbanViewModel

    /// Drives the task detail pane for this window's selected task.
    private(set) var detailViewModel: DetailViewModel

    /// Drives the team roster/pipeline/health tabs for this window.
    private(set) var teamViewModel: TeamViewModel

    // MARK: - View Mode

    /// The currently selected content view mode (tree+detail, kanban, or team)
    /// for this window's main content area.
    ///
    /// Lives on `WindowContext` rather than as view-local `@State` on
    /// `MainWindowView` so a future second window (AM-803) does not share
    /// view mode selection with the first — each window's mode is part of
    /// its own independent product context (R2.1).
    var selectedViewMode: ViewMode = .treeDetail

    // MARK: - Init

    /// Creates a `WindowContext` with fresh (or injected) ViewModel instances.
    ///
    /// Every parameter is defaulted to a fresh, production-configured instance —
    /// matching `SessionViewModel`'s `init(fileWatcher:)` dependency-injection
    /// idiom — so tests can substitute pre-configured or mock-backed ViewModels
    /// without needing to reach into their internal services.
    ///
    /// - Parameters:
    ///   - sessionViewModel: The session/product selection ViewModel for this window.
    ///   - treeViewModel: The task tree ViewModel for this window.
    ///   - kanbanViewModel: The kanban board ViewModel for this window.
    ///   - detailViewModel: The task detail ViewModel for this window.
    ///   - teamViewModel: The team roster ViewModel for this window.
    init(
        sessionViewModel: SessionViewModel = SessionViewModel(),
        treeViewModel: TreeViewModel = TreeViewModel(),
        kanbanViewModel: KanbanViewModel = KanbanViewModel(),
        detailViewModel: DetailViewModel = DetailViewModel(),
        teamViewModel: TeamViewModel = TeamViewModel()
    ) {
        self.sessionViewModel = sessionViewModel
        self.treeViewModel = treeViewModel
        self.kanbanViewModel = kanbanViewModel
        self.detailViewModel = detailViewModel
        self.teamViewModel = teamViewModel
    }
}
