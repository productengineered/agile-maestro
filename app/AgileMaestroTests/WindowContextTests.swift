import XCTest
@testable import AgileMaestro

// MARK: - WindowContextTests

/// Verifies that `WindowContext` owns fresh, independent ViewModel instances
/// per window (R2.1) — the foundational guarantee both AM-802's remaining
/// tasks and AM-803's tabs depend on.
@MainActor
final class WindowContextTests: XCTestCase {

    // MARK: - Ownership

    /// A single `WindowContext` exposes all five owned ViewModels, each a
    /// distinct instance from the others (no accidental aliasing within one
    /// context).
    func testInitProducesFiveDistinctOwnedViewModels() {
        let sut = WindowContext()

        XCTAssertNotNil(sut.sessionViewModel)
        XCTAssertNotNil(sut.treeViewModel)
        XCTAssertNotNil(sut.kanbanViewModel)
        XCTAssertNotNil(sut.detailViewModel)
        XCTAssertNotNil(sut.teamViewModel)
    }

    // MARK: - Cross-Instance Isolation

    /// Two separate `WindowContext` instances must not share any ViewModel
    /// instance — each window's ViewModel graph is independent.
    func testTwoInstancesHaveDistinctViewModelIdentities() {
        let first = WindowContext()
        let second = WindowContext()

        XCTAssertFalse(first.sessionViewModel === second.sessionViewModel)
        XCTAssertFalse(first.treeViewModel === second.treeViewModel)
        XCTAssertFalse(first.kanbanViewModel === second.kanbanViewModel)
        XCTAssertFalse(first.detailViewModel === second.detailViewModel)
        XCTAssertFalse(first.teamViewModel === second.teamViewModel)
    }

    /// Mutating public state on one `WindowContext`'s ViewModels must not be
    /// observable through a second `WindowContext`'s ViewModels — proving the
    /// two instances are independently mutable, not just distinct objects.
    func testMutatingOneInstanceDoesNotAffectAnother() {
        let first = WindowContext()
        let second = WindowContext()

        // Baseline: both start with the same defaults.
        XCTAssertEqual(first.treeViewModel.isBugSectionExpanded, second.treeViewModel.isBugSectionExpanded)
        XCTAssertEqual(first.detailViewModel.activeTab, second.detailViewModel.activeTab)
        XCTAssertEqual(first.teamViewModel.searchQuery, second.teamViewModel.searchQuery)

        // Mutate only `first`'s owned ViewModels.
        first.treeViewModel.isBugSectionExpanded = false
        first.kanbanViewModel.typeFilter = .bug
        first.detailViewModel.activeTab = .comments
        first.teamViewModel.searchQuery = "search-query-\(UUID().uuidString)"
        first.sessionViewModel.showingNewProductSheet = true

        // `second`'s state must be untouched.
        XCTAssertTrue(second.treeViewModel.isBugSectionExpanded)
        XCTAssertEqual(second.kanbanViewModel.typeFilter, .all)
        XCTAssertNotEqual(second.detailViewModel.activeTab, .comments)
        XCTAssertNotEqual(second.teamViewModel.searchQuery, first.teamViewModel.searchQuery)
        XCTAssertFalse(second.sessionViewModel.showingNewProductSheet)

        // `first`'s mutations did take effect on `first`.
        XCTAssertFalse(first.treeViewModel.isBugSectionExpanded)
        XCTAssertEqual(first.kanbanViewModel.typeFilter, .bug)
        XCTAssertEqual(first.detailViewModel.activeTab, .comments)
        XCTAssertTrue(first.sessionViewModel.showingNewProductSheet)
    }

    // MARK: - View Mode

    /// Two separate `WindowContext` instances must be able to hold different
    /// `selectedViewMode` values at the same time — proving view mode
    /// selection is owned per-window (task-11 / AM-802-3), not shared global
    /// state that happens to work only because there's currently one window.
    func testTwoInstancesCanHoldDifferentSelectedViewModeValuesSimultaneously() {
        let first = WindowContext()
        let second = WindowContext()

        // Baseline: both start with the same default.
        XCTAssertEqual(first.selectedViewMode, .treeDetail)
        XCTAssertEqual(second.selectedViewMode, .treeDetail)

        first.selectedViewMode = .kanban
        second.selectedViewMode = .team

        XCTAssertEqual(first.selectedViewMode, .kanban)
        XCTAssertEqual(second.selectedViewMode, .team)
    }

    // MARK: - Teardown (task-12 / IS-800-6)

    /// Releasing a `WindowContext` must deallocate all five owned ViewModels —
    /// proving no retain cycle exists between `WindowContext` and any of them
    /// (audited manually: none of the five hold a reference back to
    /// `WindowContext` or to a sibling ViewModel; wiring happens at the view
    /// layer only, per the "Ownership contract" doc comment on
    /// `WindowContext`). This is a regression guard against a future cycle
    /// being introduced accidentally.
    func testReleasingWindowContextDeallocatesAllFiveOwnedViewModels() {
        var context: WindowContext? = WindowContext()
        weak var weakSession = context?.sessionViewModel
        weak var weakTree = context?.treeViewModel
        weak var weakKanban = context?.kanbanViewModel
        weak var weakDetail = context?.detailViewModel
        weak var weakTeam = context?.teamViewModel

        XCTAssertNotNil(weakSession)
        XCTAssertNotNil(weakTree)
        XCTAssertNotNil(weakKanban)
        XCTAssertNotNil(weakDetail)
        XCTAssertNotNil(weakTeam)

        context = nil

        XCTAssertNil(weakSession, "SessionViewModel leaked — retain cycle with WindowContext?")
        XCTAssertNil(weakTree, "TreeViewModel leaked — retain cycle with WindowContext?")
        XCTAssertNil(weakKanban, "KanbanViewModel leaked — retain cycle with WindowContext?")
        XCTAssertNil(weakDetail, "DetailViewModel leaked — retain cycle with WindowContext?")
        XCTAssertNil(weakTeam, "TeamViewModel leaked — retain cycle with WindowContext?")
    }

    /// Releasing a `WindowContext` deallocates its owned `SessionViewModel`,
    /// which in turn deallocates its `FileWatcherService` — proving the
    /// teardown contract documented on `WindowContext`: it has no explicit
    /// teardown logic of its own and relies entirely on the existing
    /// deinit-based cleanup chain (`FileWatcherService.deinit` at
    /// `FileWatcherService.swift` ~line 140 calls `stopInternal()`, which
    /// stops the FSEventStream and cancels the polling timer/debounce work
    /// item — see ~line 291).
    ///
    /// Deallocation is synchronous, deterministic ARC (no autorelease pool
    /// involved here), so asserting the weak reference is `nil` immediately
    /// after releasing the `WindowContext` is definitive proof the watcher's
    /// underlying resources were released: an object that no longer exists
    /// cannot fire further `onChange` callbacks, and no FSEvents stream or
    /// polling timer can be left running.
    ///
    /// Construction is scoped inside `makeContext()` rather than bound to
    /// named `let`s in the test body. In an unoptimized (`-Onone`, i.e. Debug
    /// test) build, ARC extends a named local's lifetime to the end of its
    /// *lexical scope* — not its last use — purely so it stays inspectable in
    /// the debugger. A `probeWatcher`/`sessionViewModel` `let` living directly
    /// in this method would therefore keep `FileWatcherService` alive until
    /// the closing brace regardless of whether `WindowContext`'s teardown
    /// chain actually released it, making the final assertion pass
    /// vacuously. Returning from `makeContext()` closes that inner scope
    /// before the assertions run, so `weakWatcher` only stays alive through
    /// `WindowContext`'s own strong-reference chain — exactly what this test
    /// intends to prove.
    func testReleasingWindowContextStopsSessionFileWatcher() async throws {
        let tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectoryURL) }

        weak var weakWatcher: FileWatcherService?

        func makeContext() -> WindowContext {
            let probeWatcher = FileWatcherService()
            weakWatcher = probeWatcher

            // Inject the probe watcher so `weakWatcher` observes the exact
            // same instance `SessionViewModel` (and therefore
            // `WindowContext`) ends up owning. `probeWatcher` and
            // `sessionViewModel` are local to this helper, so they release
            // when it returns instead of lingering for the rest of the test.
            let sessionViewModel = SessionViewModel(
                productService: MockProductService(),
                sessionService: MockSessionService(),
                parserService: MockParserService(),
                backupService: MockBackupService(),
                fileWatcher: probeWatcher
            )

            return WindowContext(sessionViewModel: sessionViewModel)
        }

        var context: WindowContext? = makeContext()

        let session = TaskSession(id: UUID(), path: tempDirectoryURL, modifiedDate: Date())
        await context?.sessionViewModel.selectSession(session)

        XCTAssertNotNil(weakWatcher, "Watcher should still be alive while its WindowContext is retained")

        context = nil

        XCTAssertNil(
            weakWatcher,
            "Releasing WindowContext must deallocate the file watcher (via SessionViewModel) — " +
            "proving FileWatcherService.deinit's stopInternal() ran, leaving no leaked FSEvents " +
            "stream or polling timer and no possibility of further onChange callbacks"
        )
    }

    // MARK: - Dependency Injection

    /// `WindowContext`'s init parameters are defaulted but overridable, so a
    /// caller (e.g. a test or a future preview) can inject pre-configured
    /// ViewModel instances instead of relying on fresh defaults.
    func testInitAcceptsInjectedViewModelInstances() {
        let injectedTeamViewModel = TeamViewModel()
        injectedTeamViewModel.searchQuery = "injected-query"

        let sut = WindowContext(teamViewModel: injectedTeamViewModel)

        XCTAssertTrue(sut.teamViewModel === injectedTeamViewModel)
        XCTAssertEqual(sut.teamViewModel.searchQuery, "injected-query")
    }
}
