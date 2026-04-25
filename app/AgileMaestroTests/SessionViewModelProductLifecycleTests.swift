import XCTest
@testable import AgileMaestro

// MARK: - SessionViewModelProductLifecycleTests

/// End-to-end integration tests for the complete product lifecycle.
///
/// These tests exercise the full J1 → J2 → J3 flow:
/// create product → select → refresh → edit → delete
///
/// Individual unit tests in `SessionViewModelCRUDTests` and
/// `SessionViewModelBackupAndStalenessTests` verify each operation in isolation.
/// These integration tests verify the *sequence* works correctly — that prior
/// state does not corrupt later operations.
///
/// Mock services are defined in `SessionViewModelTests.swift` and are accessible
/// within the same test target.
@MainActor
final class SessionViewModelProductLifecycleTests: XCTestCase {

    // MARK: - Properties

    private var sut: SessionViewModel!
    private var mockProductService: MockProductService!
    private var mockSessionService: MockSessionService!
    private var mockParserService: MockParserService!
    private var mockBackupService: MockBackupServiceWithCallTracking!
    private var tempDirectory: URL!

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

    private func makeSession(path: URL) -> TaskSession {
        TaskSession(id: UUID(), path: path, modifiedDate: Date())
    }

    // MARK: - Full Lifecycle: Create → Select → Refresh → Delete

    func testFullLifecycle_CreateToDelete() async throws {
        // ---- Step 1: No products initially ----
        mockProductService.loadProductsResult = .success([])
        mockSessionService.getRecentSessionsResult = .success([])
        await sut.loadProducts()

        XCTAssertTrue(sut.products.isEmpty, "No products should be loaded initially")
        XCTAssertNil(sut.selectedProduct, "selectedProduct must be nil before any product is created")

        // ---- Step 2: Create a product ----
        try await sut.createProduct(
            name: "Integration Test Product",
            taskDirectoryPath: tempDirectory.path,
            toolkitDirectoryPath: nil
        )

        XCTAssertEqual(sut.products.count, 1, "One product should exist after creation")
        XCTAssertEqual(sut.selectedProduct?.name, "Integration Test Product",
                       "Newly created product should be selected")
        XCTAssertTrue(mockProductService.saveProductsCalled,
                      "createProduct must persist to storage")

        let createdProduct = try XCTUnwrap(sut.selectedProduct)

        // ---- Step 3: Select the product and load its sessions ----
        let session = makeSession(path: tempDirectory)
        mockSessionService.getRecentSessionsResult = .success([session])
        mockParserService.loadTasksResult = .success([])

        await sut.loadSessions(for: createdProduct)

        XCTAssertEqual(sut.sessions.count, 1, "Sessions should be loaded for the selected product")
        XCTAssertEqual(sut.selectedSession?.path, tempDirectory,
                       "Most recent session should be auto-selected")
        XCTAssertEqual(sut.state, .loaded, "State must be .loaded after session load")

        // ---- Step 4: Refresh current session — backup must fire ----
        mockParserService.loadTasksResult = .success([])
        await sut.refreshCurrentSession()

        // Allow the fire-and-forget backup Task to complete
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(sut.state, .loaded,
                       "State must remain .loaded after successful refresh")
        XCTAssertNotNil(sut.lastRefreshed,
                        "lastRefreshed must be set after a successful refresh")
        XCTAssertGreaterThanOrEqual(
            mockBackupService.performBackupCallCount, 1,
            "Backup must be triggered when a product is selected and session is refreshed"
        )

        // ---- Step 5: Delete the product ----
        try await sut.removeProduct(createdProduct)

        XCTAssertTrue(sut.products.isEmpty, "products must be empty after deleting the only product")
        XCTAssertNil(sut.selectedProduct,
                     "selectedProduct must be nil after deleting the last product")
    }

    // MARK: - Create → Edit Name → Verify Updated in List

    func testEditProductName_UpdatesInProductsListAndSelectedProduct() async throws {
        // Given — create a product
        try await sut.createProduct(
            name: "Original Name",
            taskDirectoryPath: "/tmp/tasks",
            toolkitDirectoryPath: nil
        )

        let original = try XCTUnwrap(sut.selectedProduct)
        XCTAssertEqual(original.name, "Original Name")

        // When — update its name
        var renamed = original
        renamed.name = "Renamed Product"
        try await sut.updateProduct(renamed)

        // Then — products array and selectedProduct both reflect the new name
        XCTAssertEqual(sut.products.first(where: { $0.id == original.id })?.name, "Renamed Product",
                       "products array must contain the updated name")
        XCTAssertEqual(sut.selectedProduct?.name, "Renamed Product",
                       "selectedProduct must reflect the renamed product")
    }

    // MARK: - Edit Product Directory → Sessions Reload from New Path

    func testEditProductDirectory_ReloadsSessionsFromNewPath() async throws {
        // Given — create a product and load its sessions
        try await sut.createProduct(
            name: "Relocatable Product",
            taskDirectoryPath: "/tmp/original-path",
            toolkitDirectoryPath: nil
        )

        let original = try XCTUnwrap(sut.selectedProduct)

        // Prime sessions from the original path
        let oldSession = makeSession(path: URL(fileURLWithPath: "/tmp/original-path"))
        mockSessionService.getRecentSessionsResult = .success([oldSession])
        mockParserService.loadTasksResult = .success([])
        await sut.loadSessions(for: original)

        XCTAssertEqual(sut.sessions.first?.path, URL(fileURLWithPath: "/tmp/original-path"),
                       "Pre-condition: sessions should be from original path")

        // When — update the product's task directory path
        var relocated = original
        relocated.associatedSessionPath = tempDirectory.path
        try await sut.updateProduct(relocated)

        // Prime sessions from the new path
        let newSession = makeSession(path: tempDirectory)
        mockSessionService.getRecentSessionsResult = .success([newSession])
        mockParserService.loadTasksResult = .success([])

        await sut.loadSessions(for: relocated)

        // Then — sessions now reflect the new directory
        XCTAssertEqual(sut.sessions.first?.path, tempDirectory,
                       "Sessions must be loaded from the new product directory after update")
    }

    // MARK: - Delete → Next Product Selected (or nil)

    func testDeleteSelectedProduct_SelectsNextProduct() async throws {
        // Given — two products exist; first is selected
        let alpha = Product(name: "Alpha")
        let beta = Product(name: "Beta")
        mockProductService.loadProductsResult = .success([alpha, beta])
        mockSessionService.getRecentSessionsResult = .success([])
        await sut.loadProducts()

        XCTAssertEqual(sut.selectedProduct?.id, alpha.id,
                       "Pre-condition: first product should be selected after load")

        // When — delete the selected product
        try await sut.removeProduct(alpha)

        // Then — Beta becomes the selected product
        XCTAssertEqual(sut.selectedProduct?.id, beta.id,
                       "After deleting the selected product the next product must be selected")
        XCTAssertEqual(sut.products.count, 1, "Only Beta should remain in the products list")
    }

    func testDeleteLastProduct_SetsSelectedProductNil() async throws {
        // Given — single product selected
        let only = Product(name: "Last One Standing")
        mockProductService.loadProductsResult = .success([only])
        mockSessionService.getRecentSessionsResult = .success([])
        await sut.loadProducts()

        XCTAssertNotNil(sut.selectedProduct, "Pre-condition: product should be selected after load")

        // When — delete the last product
        try await sut.removeProduct(only)

        // Then
        XCTAssertNil(sut.selectedProduct,
                     "selectedProduct must be nil when no products remain after deletion")
        XCTAssertTrue(sut.products.isEmpty, "products must be empty after deleting the last product")
    }

    // MARK: - Regression: Bug 208 — stale sessions after product deletion

    /// Regression test for Bug 208: deleting the selected product while another product
    /// exists must reload sessions for the newly selected product.
    ///
    /// Before the fix, `removeProduct(_:)` set `selectedProduct = updated.first` but never
    /// called `loadSessions(for:)`. Sessions from the deleted product remained on screen.
    func testDeleteSelectedProduct_ReloadsSessions_WhenNextProductExists() async throws {
        // Given — two products; first is selected with one session loaded
        let alpha = Product(name: "Alpha")
        let beta = Product(name: "Beta")
        mockProductService.loadProductsResult = .success([alpha, beta])

        let alphaSession = makeSession(path: URL(fileURLWithPath: "/tmp/alpha-session"))
        mockSessionService.getRecentSessionsResult = .success([alphaSession])
        mockParserService.loadTasksResult = .success([])
        await sut.loadProducts()

        XCTAssertEqual(sut.selectedProduct?.id, alpha.id, "Pre-condition: Alpha should be selected")
        XCTAssertEqual(sut.sessions.count, 1, "Pre-condition: Alpha's session must be loaded")

        // Reconfigure mock so Beta's session load returns a different session
        let betaSession = makeSession(path: URL(fileURLWithPath: "/tmp/beta-session"))
        mockSessionService.getRecentSessionsResult = .success([betaSession])
        mockParserService.loadTasksResult = .success([])

        // When — delete Alpha (the selected product)
        try await sut.removeProduct(alpha)

        // Then — Beta is selected and its sessions are loaded (not Alpha's stale session)
        XCTAssertEqual(sut.selectedProduct?.id, beta.id,
                       "Beta must be selected after Alpha is deleted")
        XCTAssertEqual(sut.sessions.first?.path, URL(fileURLWithPath: "/tmp/beta-session"),
                       "Sessions must be reloaded for Beta after Alpha is deleted — not Alpha's stale session")
        XCTAssertEqual(sut.state, .loaded,
                       "State must be .loaded after session reload triggered by product deletion")
    }

    /// Regression test for Bug 208: deleting the last product must clear sessions
    /// rather than leave the deleted product's sessions visible.
    func testDeleteLastProduct_ClearsSessions() async throws {
        // Given — one product selected with a session loaded
        let only = Product(name: "Only Product")
        mockProductService.loadProductsResult = .success([only])

        let session = makeSession(path: tempDirectory)
        mockSessionService.getRecentSessionsResult = .success([session])
        mockParserService.loadTasksResult = .success([])
        await sut.loadProducts()

        XCTAssertEqual(sut.sessions.count, 1, "Pre-condition: session must be loaded before deletion")

        // After deleting the last product, loadSessionsWithoutProduct() is called.
        // Configure mock to return no sessions (no-product empty state).
        mockSessionService.getRecentSessionsResult = .success([])

        // When — delete the only product
        try await sut.removeProduct(only)

        // Then — sessions are cleared (loadSessionsWithoutProduct ran, found nothing)
        XCTAssertNil(sut.selectedProduct, "selectedProduct must be nil after deleting the last product")
        XCTAssertTrue(sut.sessions.isEmpty,
                      "sessions must be cleared after deleting the last product — no stale data should remain")
    }

    /// Verifies that deleting a NON-selected product does NOT trigger a session reload.
    /// Sessions for the currently selected product remain valid and must not be disturbed.
    func testDeleteNonSelectedProduct_DoesNotReloadSessions() async throws {
        // Given — two products; Alpha is selected with a session loaded
        let alpha = Product(name: "Alpha")
        let beta = Product(name: "Beta")
        mockProductService.loadProductsResult = .success([alpha, beta])

        let alphaSession = makeSession(path: URL(fileURLWithPath: "/tmp/alpha-session"))
        mockSessionService.getRecentSessionsResult = .success([alphaSession])
        mockParserService.loadTasksResult = .success([])
        await sut.loadProducts()

        XCTAssertEqual(sut.selectedProduct?.id, alpha.id, "Pre-condition: Alpha should be selected")

        // Reset the mock to a different result — if sessions reload, we'll catch it
        let differentSession = makeSession(path: URL(fileURLWithPath: "/tmp/different"))
        mockSessionService.getRecentSessionsResult = .success([differentSession])

        // When — delete Beta (NOT the selected product)
        try await sut.removeProduct(beta)

        // Then — Alpha remains selected and its original session is still loaded
        XCTAssertEqual(sut.selectedProduct?.id, alpha.id,
                       "Alpha must remain selected when a non-selected product (Beta) is deleted")
        XCTAssertEqual(sut.sessions.first?.path, URL(fileURLWithPath: "/tmp/alpha-session"),
                       "Alpha's sessions must remain unchanged when a non-selected product is deleted")
    }

    // MARK: - Stale Product Detection

    func testStaleProductDetection_ProductWithMissingDirectory() async throws {
        // Given — product pointing to a path that does not exist
        var staleProduct = Product(name: "Stale Product")
        staleProduct.associatedSessionPath = tempDirectory
            .appendingPathComponent("nonexistent-subdir")
            .path

        mockProductService.loadProductsResult = .success([staleProduct])
        mockSessionService.getRecentSessionsResult = .success([])

        // When — loadProducts triggers checkProductStaleness internally
        await sut.loadProducts()

        // Then
        XCTAssertTrue(sut.staleProductIDs.contains(staleProduct.id),
                      "Product with a missing directory must be in staleProductIDs after loadProducts")
    }

    func testStaleProductDetection_ProductWithValidDirectory() async throws {
        // Given — product pointing at the real temp directory (exists on disk)
        var freshProduct = Product(name: "Fresh Product")
        freshProduct.associatedSessionPath = tempDirectory.path

        mockProductService.loadProductsResult = .success([freshProduct])
        mockSessionService.getRecentSessionsResult = .success([])

        // When
        await sut.loadProducts()

        // Then
        XCTAssertFalse(sut.staleProductIDs.contains(freshProduct.id),
                       "Product with an existing directory must NOT be stale")
    }

    // MARK: - Backup Fires on Refresh

    func testBackupFiresOnRefresh_WhenProductAndSessionSelected() async throws {
        // Given — a product and session are selected
        try await sut.createProduct(
            name: "Backup Target",
            taskDirectoryPath: tempDirectory.path,
            toolkitDirectoryPath: nil
        )

        let session = makeSession(path: tempDirectory)
        mockSessionService.getRecentSessionsResult = .success([session])
        mockParserService.loadTasksResult = .success([])

        let product = try XCTUnwrap(sut.selectedProduct)
        await sut.loadSessions(for: product)

        // Reset call count before the refresh under test
        // (loadSessions → selectSession → refreshCurrentSession may have already fired once)
        let countBeforeRefresh = mockBackupService.performBackupCallCount

        // When — explicit refresh
        mockParserService.loadTasksResult = .success([])
        await sut.refreshCurrentSession()
        await Task.yield()
        await Task.yield()

        // Then — backup was triggered at least once more
        XCTAssertGreaterThan(
            mockBackupService.performBackupCallCount, countBeforeRefresh,
            "performBackup must be called again during refreshCurrentSession when a product is selected"
        )
    }

    func testBackupDoesNotFireOnRefresh_WhenNoProductSelected() async {
        // Given — no products; session discovered via auto-discover path
        let session = makeSession(path: tempDirectory)
        mockProductService.loadProductsResult = .success([])
        mockSessionService.getRecentSessionsResult = .success([session])
        mockParserService.loadTasksResult = .success([])

        await sut.loadProducts()
        await Task.yield()
        await Task.yield()

        // Then — backup must not be triggered without a selected product
        XCTAssertEqual(mockBackupService.performBackupCallCount, 0,
                       "performBackup must NOT fire when no product is selected")
    }

    // MARK: - Real Filesystem: Session Directory Detection

    /// Regression test for the bug where selecting a session directory (a directory
    /// containing .json task files) as a product's task path resulted in zero sessions
    /// being loaded.
    ///
    /// `TaskSessionService.getRecentSessions(from:)` treats the passed URL as a tasks
    /// *root* and scans for subdirectories. When the user selects a session directory
    /// directly, there are no subdirectories — only .json files — so zero sessions are
    /// returned. The fix detects .json files in the directory and creates a TaskSession
    /// directly, bypassing the subdirectory scan.
    ///
    /// This test uses a real filesystem (temp directory + .json files) and a real
    /// `TaskSessionService` because mock-based tests cannot reproduce the bug —
    /// `MockSessionService.getRecentSessions(from:)` returns a pre-seeded result
    /// regardless of path.
    func testLoadSessions_SessionDirectory_LoadsTasksDirectly() async throws {
        // Given — a temp directory that looks like a session directory (has .json files)
        let sessionDir = tempDirectory.appendingPathComponent("my-session", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let taskJSON = sessionDir.appendingPathComponent("task-1.json")
        try "{}".write(to: taskJSON, atomically: true, encoding: .utf8)

        // Wire the SUT with a real TaskSessionService (not a mock) so the path-type
        // detection in loadSessions(for:) actually hits the filesystem.
        let realSessionService = TaskSessionService(tasksRoot: sessionDir)
        let sutWithRealService = SessionViewModel(
            productService: mockProductService,
            sessionService: realSessionService,
            parserService: mockParserService,
            backupService: mockBackupService,
            fileWatcher: FileWatcherService()
        )

        var product = Product(name: "Real FS Product")
        product.associatedSessionPath = sessionDir.path

        // When — load sessions for the product that points at a session directory
        await sutWithRealService.loadSessions(for: product)

        // Then — exactly one session is found (the session directory itself)
        XCTAssertEqual(sutWithRealService.sessions.count, 1,
                       "loadSessions must find one session when the product path is a session directory")

        XCTAssertEqual(sutWithRealService.sessions.first?.path, sessionDir,
                       "The session path must match the session directory selected by the user")
        XCTAssertEqual(sutWithRealService.state, .loaded,
                       "State must be .loaded after successfully detecting the session directory")
    }

    /// Verifies that the existing subdirectory-scan behaviour still works when the
    /// product points at a tasks root (a directory that contains subdirectories, not
    /// .json files).
    func testLoadSessions_TasksRoot_ScansSubdirectoriesAsNormal() async throws {
        // Given — a tasks root with two subdirectories (each represents a session)
        let tasksRoot = tempDirectory.appendingPathComponent("tasks-root", isDirectory: true)
        let session1 = tasksRoot.appendingPathComponent("session-a", isDirectory: true)
        let session2 = tasksRoot.appendingPathComponent("session-b", isDirectory: true)
        try FileManager.default.createDirectory(at: session1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: session2, withIntermediateDirectories: true)
        // Add a .json file inside each session subdirectory so they look like real sessions
        try "{}".write(to: session1.appendingPathComponent("t.json"), atomically: true, encoding: .utf8)
        try "{}".write(to: session2.appendingPathComponent("t.json"), atomically: true, encoding: .utf8)

        let realSessionService = TaskSessionService(tasksRoot: tasksRoot)
        let sutWithRealService = SessionViewModel(
            productService: mockProductService,
            sessionService: realSessionService,
            parserService: mockParserService,
            backupService: mockBackupService,
            fileWatcher: FileWatcherService()
        )

        var product = Product(name: "Tasks Root Product")
        product.associatedSessionPath = tasksRoot.path

        // When
        await sutWithRealService.loadSessions(for: product)

        // Then — the two subdirectories are scanned and two sessions are returned
        XCTAssertEqual(sutWithRealService.sessions.count, 2,
                       "loadSessions must scan subdirectories and find 2 sessions when pointing at a tasks root")
        XCTAssertEqual(sutWithRealService.state, .loaded,
                       "State must be .loaded after scanning a tasks root with sessions")
    }
}
