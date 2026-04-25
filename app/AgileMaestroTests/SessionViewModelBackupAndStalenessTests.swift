import XCTest
@testable import AgileMaestro

// MARK: - MockBackupServiceWithCallTracking

/// An instrumented BackupService mock that records every `performBackup` invocation.
///
/// Extends the observable property set of `MockBackupService` with a `performBackupCallCount`
/// counter so tests can assert that fire-and-forget backup tasks were triggered without
/// introducing timing dependencies on the real filesystem.
final class MockBackupServiceWithCallTracking: BackupServiceProtocol, @unchecked Sendable {
    var performBackupResult: Result<Void, Error> = .success(())
    private(set) var performBackupCallCount: Int = 0
    private(set) var lastSource: URL?
    private(set) var lastDestination: URL?

    func performBackup(from source: URL, to destination: URL) async throws {
        performBackupCallCount += 1
        lastSource = source
        lastDestination = destination
        try performBackupResult.get()
    }
}

// MARK: - SessionViewModelBackupIntegrationTests

/// Tests for `SessionViewModel.refreshCurrentSession()` fire-and-forget backup integration.
///
/// Mock services (`MockProductService`, `MockSessionService`, `MockParserService`) are
/// defined in `SessionViewModelTests.swift` and accessible within the same test target.
@MainActor
final class SessionViewModelBackupIntegrationTests: XCTestCase {

    // MARK: - Properties

    private var sut: SessionViewModel!
    private var mockProductService: MockProductService!
    private var mockSessionService: MockSessionService!
    private var mockParserService: MockParserService!
    private var mockBackupService: MockBackupServiceWithCallTracking!

    // MARK: - Setup / Teardown

    override func setUp() async throws {
        try await super.setUp()
        mockProductService = MockProductService()
        mockSessionService = MockSessionService()
        mockParserService = MockParserService()
        mockBackupService = MockBackupServiceWithCallTracking()
        sut = SessionViewModel(
            productService: mockProductService,
            sessionService: mockSessionService,
            parserService: mockParserService,
            backupService: mockBackupService,
            fileWatcher: FileWatcherService()
        )
    }

    override func tearDown() async throws {
        sut = nil
        mockProductService = nil
        mockSessionService = nil
        mockParserService = nil
        mockBackupService = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeSession(
        path: URL = URL(fileURLWithPath: "/tmp/session")
    ) -> TaskSession {
        TaskSession(id: UUID(), path: path, modifiedDate: Date())
    }

    private func loadProduct(_ product: Product) async {
        mockProductService.loadProductsResult = .success([product])
        mockSessionService.getRecentSessionsResult = .success([])
        await sut.loadProducts()
    }

    // MARK: - Backup fires on refresh

    func testRefreshCurrentSessionFiresBackupWhenProductIsSelected() async {
        // Given — a selected product and a selected session
        let product = Product(name: "BackupTest")
        await loadProduct(product)

        let session = makeSession(path: URL(fileURLWithPath: "/tmp/tasks"))
        mockParserService.loadTasksResult = .success([])
        await sut.selectSession(session)

        // The fire-and-forget Task is racing with the test. Yield the run loop long
        // enough for the unstructured task to complete before asserting.
        await Task.yield()
        // Allow one more yield in case the unstructured Task needs two loop turns.
        await Task.yield()

        // Then
        XCTAssertGreaterThanOrEqual(
            mockBackupService.performBackupCallCount, 1,
            "performBackup must be called at least once when a product and session are selected"
        )
        XCTAssertEqual(
            mockBackupService.lastSource, session.path,
            "backup source must be the session directory"
        )
    }

    func testRefreshCurrentSessionDoesNotFireBackupWhenNoProductSelected() async {
        // Given — no products loaded; auto-discover path selects a session without a product
        let session = makeSession(path: URL(fileURLWithPath: "/tmp/no-product"))
        mockProductService.loadProductsResult = .success([])
        mockSessionService.getRecentSessionsResult = .success([session])
        mockParserService.loadTasksResult = .success([])

        await sut.loadProducts()

        // Yield enough for any spurious backup task to complete
        await Task.yield()
        await Task.yield()

        // Then — backup must not be called when selectedProduct is nil
        XCTAssertEqual(
            mockBackupService.performBackupCallCount, 0,
            "performBackup must NOT be called when no product is selected"
        )
    }

    func testRefreshCurrentSessionBackupFailureDoesNotAffectSessionState() async {
        // Given — backup is configured to fail; refresh must still succeed
        struct BackupError: Error {}
        mockBackupService.performBackupResult = .failure(BackupError())

        let product = Product(name: "Resilient")
        await loadProduct(product)

        let session = makeSession()
        mockParserService.loadTasksResult = .success([])
        await sut.selectSession(session)

        await Task.yield()
        await Task.yield()

        // Then — state is loaded; backup failure is swallowed by the fire-and-forget
        XCTAssertEqual(sut.state, .loaded,
                       "Backup failure must not affect refreshCurrentSession state")
    }
}

// MARK: - SessionViewModelStalenessTests

/// Tests for `SessionViewModel.checkProductStaleness()`.
///
/// Uses real temporary directories so the `FileManager.default.fileExists` call inside
/// `checkProductStaleness()` returns deterministic results without mocking the framework.
@MainActor
final class SessionViewModelStalenessTests: XCTestCase {

    // MARK: - Properties

    private var sut: SessionViewModel!
    private var mockProductService: MockProductService!
    private var mockSessionService: MockSessionService!
    private var mockParserService: MockParserService!
    private var mockBackupService: MockBackupService!
    private var tempDirectory: URL!

    // MARK: - Setup / Teardown

    override func setUp() async throws {
        try await super.setUp()
        mockProductService = MockProductService()
        mockSessionService = MockSessionService()
        mockParserService = MockParserService()
        mockBackupService = MockBackupService()
        sut = SessionViewModel(
            productService: mockProductService,
            sessionService: mockSessionService,
            parserService: mockParserService,
            backupService: mockBackupService,
            fileWatcher: FileWatcherService()
        )
        // Create a unique temp directory for each test
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        sut = nil
        mockProductService = nil
        mockSessionService = nil
        mockParserService = nil
        mockBackupService = nil
        tempDirectory = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// Primes sut.products via loadProducts() using the given list.
    private func loadProducts(_ products: [Product]) async {
        mockProductService.loadProductsResult = .success(products)
        mockSessionService.getRecentSessionsResult = .success([])
        await sut.loadProducts()
    }

    // MARK: - Tests

    func testCheckProductStalenessMarksProductsWithMissingDirectoryAsStale() async {
        // Given — product whose path does not exist
        var product = Product(name: "Stale")
        product.associatedSessionPath = tempDirectory
            .appendingPathComponent("nonexistent-subdir")
            .path
        await loadProducts([product])

        // When
        sut.checkProductStaleness()

        // Then
        XCTAssertTrue(sut.staleProductIDs.contains(product.id),
                      "Product with missing directory path must be in staleProductIDs")
    }

    func testCheckProductStalenessDoesNotMarkProductsWithValidDirectoryAsStale() async {
        // Given — product pointing at the real temp directory (exists on disk)
        var product = Product(name: "Fresh")
        product.associatedSessionPath = tempDirectory.path
        await loadProducts([product])

        // When
        sut.checkProductStaleness()

        // Then
        XCTAssertFalse(sut.staleProductIDs.contains(product.id),
                       "Product with an existing directory must NOT be in staleProductIDs")
    }

    func testCheckProductStalenessMarksProductsWithNoPathAsStale() async {
        // Given — product with nil associatedSessionPath
        var product = Product(name: "NoPath")
        product.associatedSessionPath = nil
        await loadProducts([product])

        // When
        sut.checkProductStaleness()

        // Then
        XCTAssertTrue(sut.staleProductIDs.contains(product.id),
                      "Product with nil associatedSessionPath must be treated as stale")
    }

    func testCheckProductStalenessHandlesMixedStaleAndFreshProducts() async {
        // Given — two products: one valid, one pointing to a missing path
        var fresh = Product(name: "Fresh")
        fresh.associatedSessionPath = tempDirectory.path

        var stale = Product(name: "Stale")
        stale.associatedSessionPath = tempDirectory
            .appendingPathComponent("gone")
            .path

        await loadProducts([fresh, stale])

        // When
        sut.checkProductStaleness()

        // Then
        XCTAssertFalse(sut.staleProductIDs.contains(fresh.id),
                       "Fresh product must not appear in staleProductIDs")
        XCTAssertTrue(sut.staleProductIDs.contains(stale.id),
                      "Stale product must appear in staleProductIDs")
    }

    func testCheckProductStalenessWithNoProductsLeavesStaleIDsEmpty() async {
        // Given — no products loaded
        await loadProducts([])

        // When
        sut.checkProductStaleness()

        // Then
        XCTAssertTrue(sut.staleProductIDs.isEmpty,
                      "staleProductIDs must be empty when no products are registered")
    }

    func testLoadProductsPopulatesStaleProductIDsAutomatically() async {
        // Given — loadProducts() should call checkProductStaleness() internally
        var stale = Product(name: "AutoStale")
        stale.associatedSessionPath = "/nonexistent/path/that/does/not/exist"
        mockProductService.loadProductsResult = .success([stale])
        mockSessionService.getRecentSessionsResult = .success([])

        // When
        await sut.loadProducts()

        // Then — staleProductIDs must be populated without an explicit call
        XCTAssertTrue(sut.staleProductIDs.contains(stale.id),
                      "loadProducts must automatically populate staleProductIDs for missing paths")
    }
}
