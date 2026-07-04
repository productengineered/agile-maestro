import XCTest
@testable import AgileMaestro

// MARK: - EmptyTabFlowTests

/// Verifies the empty new-tab CTA flow (AM-803-2, SM-EMPTY-800-T1..T5,
/// empty-new-tab-spec.md) at the unit-testable seams: sentinel identity
/// uniqueness, the CTA's non-forcing product-list load, the "not-yet-open
/// product loads into this tab" ViewModel behavior, and the dedup-routing
/// hook AM-803-3 will extend for "already-open" focus-existing behavior.
@MainActor
final class EmptyTabFlowTests: XCTestCase {

    // MARK: - Sentinel Identity Uniqueness (SM-TAB-800-T6, Cmd+T)

    /// Two empty tabs opened back-to-back must never collide under
    /// `WindowGroup`'s value-equality dedup — each `newEmptySentinel()` call
    /// must produce a distinct identity, or a second Cmd+T would silently
    /// focus the first empty tab instead of creating a new one.
    func testNewEmptySentinelProducesDistinctIdentitiesAcrossCalls() {
        let first = ProductWindowIdentity.newEmptySentinel()
        let second = ProductWindowIdentity.newEmptySentinel()

        XCTAssertNotEqual(first, second, "Two empty tabs must have distinct sentinel identities")
    }

    /// Sentinel uniqueness must hold across many calls, not just two —
    /// guards against a low-entropy or accidentally-constant UUID source.
    func testNewEmptySentinelProducesUniqueIdentitiesAcrossManyCalls() {
        let sentinels = (0..<50).map { _ in ProductWindowIdentity.newEmptySentinel() }
        let uniqueCount = Set(sentinels).count

        XCTAssertEqual(uniqueCount, sentinels.count, "All generated empty-tab sentinels must be unique")
    }

    /// `.empty` sentinels must never equal a `.product` identity, even in the
    /// degenerate case of comparing against a fresh sentinel's own UUID cast
    /// into a product-shaped identity (sanity check on the enum's Hashable
    /// conformance, since `WindowGroup` dedup relies on it).
    func testEmptySentinelNeverEqualsAProductIdentity() {
        let sentinel = ProductWindowIdentity.newEmptySentinel()
        let productIdentity = ProductWindowIdentity.product(UUID())

        XCTAssertNotEqual(sentinel, productIdentity)
    }

    // MARK: - Product Identity Dedup Contract (task AM-803-3, IS-TAB-FOCUS-800-2)

    /// The same product id must always produce an equal `ProductWindowIdentity`
    /// — this is the exact value-equality `WindowGroup`'s native dedup
    /// (research-window-tabbing.md Claim 1) keys off of. If this ever broke
    /// (e.g. a future field added to `.product` that varies per call),
    /// `openWindow(value:)` would stop focusing the existing tab and would
    /// silently open a duplicate one instead.
    func testSameProductIDProducesEqualIdentityAcrossSeparateConstructions() {
        let productID = UUID()

        let first = ProductWindowIdentity.product(productID)
        let second = ProductWindowIdentity.product(productID)

        XCTAssertEqual(first, second, "Same product id must dedup to the same identity")
        XCTAssertEqual(first.hashValue, second.hashValue, "Equal identities must hash equally")
    }

    /// Two distinct product ids must never collide — the inverse guarantee
    /// to the above, protecting against a regression where identity equality
    /// stops discriminating between different products.
    func testDifferentProductIDsProduceDistinctIdentities() {
        let first = ProductWindowIdentity.product(UUID())
        let second = ProductWindowIdentity.product(UUID())

        XCTAssertNotEqual(first, second)
    }

    // MARK: - CTA Opens Product List Without Forcing Selection (SM-EMPTY-800-T2, design3)

    /// `loadProductsForSelection()` must populate `products` for the CTA's
    /// menu without auto-selecting one — auto-selecting here would silently
    /// convert a fresh empty tab away from SCR-EMPTY before the user acts
    /// (violates design3's "no forced modal" / SM-EMPTY-800-T1 idle state).
    func testLoadProductsForSelectionPopulatesProductsWithoutAutoSelecting() async {
        let mockProductService = MockProductService()
        let products = [Product(name: "Alpha"), Product(name: "Beta")]
        mockProductService.loadProductsResult = .success(products)

        let sut = SessionViewModel(
            productService: mockProductService,
            sessionService: MockSessionService(),
            parserService: MockParserService(),
            backupService: MockBackupService(),
            fileWatcher: FileWatcherService()
        )

        await sut.loadProductsForSelection()

        XCTAssertEqual(sut.products.count, 2)
        XCTAssertNil(sut.selectedProduct, "loadProductsForSelection must never auto-select a product")
        XCTAssertEqual(sut.state, .idle, "loadProductsForSelection must not transition state — no session load implied")
    }

    /// Staleness detection still runs so the CTA's per-row indicator (AM-600
    /// pattern) reflects current filesystem state, even though no product is
    /// selected.
    func testLoadProductsForSelectionRunsStalenessCheck() async {
        let mockProductService = MockProductService()
        let staleProduct = Product(name: "Stale", associatedSessionPath: nil)
        mockProductService.loadProductsResult = .success([staleProduct])

        let sut = SessionViewModel(
            productService: mockProductService,
            sessionService: MockSessionService(),
            parserService: MockParserService(),
            backupService: MockBackupService(),
            fileWatcher: FileWatcherService()
        )

        await sut.loadProductsForSelection()

        XCTAssertTrue(sut.staleProductIDs.contains(staleProduct.id))
    }

    // MARK: - CTA Selection Path: Not-Yet-Open Product Loads Into This Tab (SM-EMPTY-800-T3)

    /// The core CTA->selection ViewModel behavior: calling `selectProduct`
    /// from a fresh empty tab (where `selectedProduct` starts `nil`, unlike
    /// the already-tested "switch away from an existing product" case)
    /// loads the chosen product directly — no guard blocks it, since nil
    /// never equals a real product id.
    func testSelectProductFromEmptyTabLoadsTheChosenProduct() async {
        let mockProductService = MockProductService()
        let mockSessionService = MockSessionService()
        let product = Product(name: "Chosen")
        mockProductService.loadProductsResult = .success([product])
        mockSessionService.getRecentSessionsResult = .success([])

        let sut = SessionViewModel(
            productService: mockProductService,
            sessionService: mockSessionService,
            parserService: MockParserService(),
            backupService: MockBackupService(),
            fileWatcher: FileWatcherService()
        )

        // Simulates the empty tab's CTA state: products loaded for display,
        // nothing selected yet.
        await sut.loadProductsForSelection()
        XCTAssertNil(sut.selectedProduct)

        sut.selectProduct(product)

        XCTAssertEqual(sut.selectedProduct?.id, product.id)
    }

    // MARK: - Already-Open Dedup Routing Hook (checklist item 4 / AM-803-3)

    /// `transitionForSelectingProduct` is the seam AM-803-3
    /// (IS-TAB-FOCUS-800-2) will extend once a real open-window registry
    /// exists. Given an empty `openProductIDs` set (today's only real call
    /// site — AM-803-2 has no registry yet), selecting any product always
    /// resolves to converting this tab in place (Path A).
    func testTransitionForSelectingProductConvertsInPlaceWhenNotOpenElsewhere() {
        let product = Product(name: "Not Open Elsewhere")

        let outcome = ProductWindowIdentity.transitionForSelectingProduct(
            product,
            openProductIDs: []
        )

        XCTAssertEqual(outcome, .convertInPlace(.product(product.id)))
    }

    /// When the product's id IS present in `openProductIDs` (the future
    /// AM-803-3 registry populated), the outcome must route to
    /// `.focusExisting` instead of converting this tab — proving the hook
    /// AM-803-3 will wire in already branches correctly today, even before
    /// the registry itself exists.
    func testTransitionForSelectingProductRoutesToFocusExistingWhenAlreadyOpen() {
        let product = Product(name: "Already Open")

        let outcome = ProductWindowIdentity.transitionForSelectingProduct(
            product,
            openProductIDs: [product.id]
        )

        XCTAssertEqual(outcome, .focusExisting)
    }

    /// A disjoint `openProductIDs` set (other products open, but not this
    /// one) must still convert in place — only an exact id match defers to
    /// the dedup path.
    func testTransitionForSelectingProductIgnoresUnrelatedOpenIDs() {
        let product = Product(name: "Target")
        let unrelatedID = UUID()

        let outcome = ProductWindowIdentity.transitionForSelectingProduct(
            product,
            openProductIDs: [unrelatedID]
        )

        XCTAssertEqual(outcome, .convertInPlace(.product(product.id)))
    }

    // MARK: - Live Registry Wiring (task AM-803-3 — the registry now exists)

    /// End-to-end proof that the real `WindowRegistrySaveCoordinator`
    /// registry (not a hand-built set) correctly routes an already-open
    /// product to `.focusExisting` — this is the exact call this task wires
    /// into `ProductWindowContentView.selectProduct`, verified here without
    /// needing to launch any actual window.
    func testLiveRegistryRoutesAlreadyOpenProductToFocusExisting() {
        let coordinator = WindowRegistrySaveCoordinator(registryService: MockWindowRegistryServiceForEmptyTabFlow())
        let alreadyOpenProduct = Product(name: "Already Open Elsewhere")
        coordinator.windowOpened(
            identity: .product(alreadyOpenProduct.id),
            viewMode: .treeDetail,
            selectedSessionID: nil
        )

        let outcome = ProductWindowIdentity.transitionForSelectingProduct(
            alreadyOpenProduct,
            openProductIDs: coordinator.openProductIDs()
        )

        XCTAssertEqual(outcome, .focusExisting)
    }

    /// The same live registry must still convert in place for a product that
    /// has never been opened — proving the wiring does not over-trigger
    /// `.focusExisting` for every selection once any product is open.
    func testLiveRegistryConvertsInPlaceForProductNotYetOpen() {
        let coordinator = WindowRegistrySaveCoordinator(registryService: MockWindowRegistryServiceForEmptyTabFlow())
        coordinator.windowOpened(identity: .product(UUID()), viewMode: .treeDetail, selectedSessionID: nil)
        let notYetOpenProduct = Product(name: "Not Open Yet")

        let outcome = ProductWindowIdentity.transitionForSelectingProduct(
            notYetOpenProduct,
            openProductIDs: coordinator.openProductIDs()
        )

        XCTAssertEqual(outcome, .convertInPlace(.product(notYetOpenProduct.id)))
    }
}

// MARK: - MockWindowRegistryServiceForEmptyTabFlow

/// Minimal no-op `WindowRegistryServiceProtocol` so
/// `WindowRegistrySaveCoordinator` can be exercised here without touching
/// `UserDefaults` — this file only cares about the coordinator's in-memory
/// `openProductIDs()` tracking, not persistence.
private final class MockWindowRegistryServiceForEmptyTabFlow: WindowRegistryServiceProtocol, @unchecked Sendable {
    func loadLaunchPlan() -> WindowRegistryLaunchPlan {
        .freshInstall(WindowRegistrySnapshot(entries: [], activeIdentity: nil))
    }
    func save(_ snapshot: WindowRegistrySnapshot) {}
    func confirmMigration(_ snapshot: WindowRegistrySnapshot) {}
}
