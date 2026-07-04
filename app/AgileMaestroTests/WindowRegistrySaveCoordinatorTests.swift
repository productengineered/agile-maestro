import XCTest
@testable import AgileMaestro

// MARK: - MockWindowRegistryService

private final class MockWindowRegistryService: WindowRegistryServiceProtocol, @unchecked Sendable {
    private(set) var savedSnapshots: [WindowRegistrySnapshot] = []

    func loadLaunchPlan() -> WindowRegistryLaunchPlan {
        .freshInstall(WindowRegistrySnapshot(entries: [], activeIdentity: nil))
    }

    func save(_ snapshot: WindowRegistrySnapshot) {
        savedSnapshots.append(snapshot)
    }

    func confirmMigration(_ snapshot: WindowRegistrySnapshot) {
        save(snapshot)
    }
}

// MARK: - WindowRegistrySaveCoordinatorTests

/// Verifies the "whenever tabs open/close/change product/view mode/session,
/// persist" registry SAVE wiring (task AM-803-5).
@MainActor
final class WindowRegistrySaveCoordinatorTests: XCTestCase {

    private var mockService: MockWindowRegistryService!
    private var sut: WindowRegistrySaveCoordinator!

    override func setUp() {
        super.setUp()
        mockService = MockWindowRegistryService()
        sut = WindowRegistrySaveCoordinator(registryService: mockService)
    }

    override func tearDown() {
        sut = nil
        mockService = nil
        super.tearDown()
    }

    func testWindowOpenedPersistsAndMarksActive() {
        let identity = ProductWindowIdentity.product(UUID())

        sut.windowOpened(identity: identity, viewMode: .kanban, selectedSessionID: nil)

        guard let saved = mockService.savedSnapshots.last else { return XCTFail("Expected a save") }
        XCTAssertEqual(saved.entries.map(\.identity), [identity])
        XCTAssertEqual(saved.entries.first?.viewMode, .kanban)
        XCTAssertEqual(saved.activeIdentity, identity)
    }

    func testWindowUpdatedChangesViewModeAndSessionForExistingWindow() {
        let identity = ProductWindowIdentity.product(UUID())
        let sessionID = UUID()
        sut.windowOpened(identity: identity, viewMode: .treeDetail, selectedSessionID: nil)

        sut.windowUpdated(identity: identity, viewMode: .team, selectedSessionID: sessionID)

        guard let saved = mockService.savedSnapshots.last else { return XCTFail("Expected a save") }
        XCTAssertEqual(saved.entries.first?.viewMode, .team)
        XCTAssertEqual(saved.entries.first?.selectedSessionID, sessionID)
    }

    func testWindowClosedRemovesEntryAndReassignsActiveToLastRemaining() {
        let first = ProductWindowIdentity.product(UUID())
        let second = ProductWindowIdentity.product(UUID())
        sut.windowOpened(identity: first, viewMode: .treeDetail, selectedSessionID: nil)
        sut.windowOpened(identity: second, viewMode: .treeDetail, selectedSessionID: nil)

        sut.windowClosed(identity: second)

        guard let saved = mockService.savedSnapshots.last else { return XCTFail("Expected a save") }
        XCTAssertEqual(saved.entries.map(\.identity), [first], "Closed window's entry must be removed")
        XCTAssertEqual(saved.activeIdentity, first, "Active must fall back to the last remaining window")
    }

    func testWindowIdentityChangedReplacesOldKeyWithNewOne() {
        let oldIdentity = ProductWindowIdentity.newEmptySentinel()
        let newIdentity = ProductWindowIdentity.product(UUID())
        sut.windowOpened(identity: oldIdentity, viewMode: .treeDetail, selectedSessionID: nil)

        sut.windowIdentityChanged(from: oldIdentity, to: newIdentity, viewMode: .kanban, selectedSessionID: nil)

        guard let saved = mockService.savedSnapshots.last else { return XCTFail("Expected a save") }
        XCTAssertEqual(saved.entries.map(\.identity), [newIdentity])
        XCTAssertEqual(saved.activeIdentity, newIdentity)
    }

    func testWindowUpdatedIsNoOpForUntrackedIdentity() {
        let neverOpened = ProductWindowIdentity.product(UUID())

        sut.windowUpdated(identity: neverOpened, viewMode: .kanban, selectedSessionID: nil)

        XCTAssertTrue(mockService.savedSnapshots.isEmpty, "Updating an untracked window must not persist anything")
    }

    // MARK: - openProductIDs() (task AM-803-3, IS-TAB-FOCUS-800-2)

    /// `openProductIDs()` is the live "which products are already open"
    /// registry the empty-tab CTA's `.focusExisting` routing depends on —
    /// every tracked `.product` window/tab must be reflected.
    func testOpenProductIDsReflectsCurrentlyTrackedProductWindows() {
        let firstID = UUID()
        let secondID = UUID()
        sut.windowOpened(identity: .product(firstID), viewMode: .treeDetail, selectedSessionID: nil)
        sut.windowOpened(identity: .product(secondID), viewMode: .treeDetail, selectedSessionID: nil)

        XCTAssertEqual(sut.openProductIDs(), [firstID, secondID])
    }

    /// Empty-tab sentinels are not products — they must never appear in the
    /// set the CTA checks against, or every empty tab would look like an
    /// "already open" product.
    func testOpenProductIDsExcludesEmptyTabSentinels() {
        sut.windowOpened(identity: .newEmptySentinel(), viewMode: .treeDetail, selectedSessionID: nil)
        let productID = UUID()
        sut.windowOpened(identity: .product(productID), viewMode: .treeDetail, selectedSessionID: nil)

        XCTAssertEqual(sut.openProductIDs(), [productID])
    }

    /// Closing a product's window/tab must remove it from the live registry —
    /// otherwise a closed product would still incorrectly route new
    /// selections to `.focusExisting` with nothing left to focus.
    func testOpenProductIDsRemovesEntryAfterWindowClosed() {
        let productID = UUID()
        sut.windowOpened(identity: .product(productID), viewMode: .treeDetail, selectedSessionID: nil)
        XCTAssertEqual(sut.openProductIDs(), [productID])

        sut.windowClosed(identity: .product(productID))

        XCTAssertTrue(sut.openProductIDs().isEmpty)
    }

    /// Reporting the same identity as opened twice (e.g. a redundant
    /// `.onAppear` fire) must not produce two entries for one product — the
    /// registry is keyed by identity, so it cannot itself become a source of
    /// duplicate live contexts.
    func testOpenProductIDsStaysSingleValuedWhenSameIdentityReportedTwice() {
        let productID = UUID()
        sut.windowOpened(identity: .product(productID), viewMode: .treeDetail, selectedSessionID: nil)
        sut.windowOpened(identity: .product(productID), viewMode: .kanban, selectedSessionID: nil)

        XCTAssertEqual(sut.openProductIDs(), [productID])
    }
}
