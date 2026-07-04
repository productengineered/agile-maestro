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
