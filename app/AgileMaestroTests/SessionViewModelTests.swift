import XCTest
@testable import AgileMaestro

// MARK: - Mock Services

final class MockProductService: ProductServiceProtocol, @unchecked Sendable {
    var loadProductsResult: Result<[Product], Error> = .success([])
    var saveProductsResult: Result<Void, Error> = .success(())
    var saveProductsCalled = false
    var savedProducts: [Product] = []

    func loadProducts() async throws -> [Product] {
        try loadProductsResult.get()
    }

    func saveProducts(_ products: [Product]) async throws {
        saveProductsCalled = true
        savedProducts = products
        try saveProductsResult.get()
    }

    func ensureBackupDirectory(for product: Product) async throws {}
}

final class MockSessionService: TaskSessionServiceProtocol, @unchecked Sendable {
    var getRecentSessionsResult: Result<[TaskSession], Error> = .success([])

    func getRecentSessions(maxSessions: Int) async throws -> [TaskSession] {
        try getRecentSessionsResult.get()
    }

    func getRecentSessions(from path: URL, maxSessions: Int) async throws -> [TaskSession] {
        // Delegates to the same configurable result regardless of path,
        // keeping tests independent of filesystem state.
        try getRecentSessionsResult.get()
    }

    func enrichSessions(_ sessions: [TaskSession], using parser: any TaskParserServiceProtocol) async -> [TaskSession] {
        // Pass through by default; tests can configure specific enriched sessions
        // by configuring getRecentSessionsResult with already-enriched sessions.
        sessions
    }
}

final class MockParserService: TaskParserServiceProtocol, @unchecked Sendable {
    /// Convenience property: tests set this to a [TaskItem] result; it is wrapped
    /// into a ParseResult (structuredTasks only, no claudeTasks/orphanedTasks) on return.
    var loadTasksResult: Result<[TaskItem], Error> = .success([])

    /// Optional override for claudeTasks returned in ParseResult.
    var claudeTasksResult: [ClaudeTask] = []

    /// Optional override for orphanedTasks returned in ParseResult.
    var orphanedTasksResult: [OrphanedTask] = []

    /// When true, the *next* call to `loadTasks(from:)` suspends until the test
    /// calls `resumeSuspendedLoad()`. Lets tests observe `SessionViewModel.state`
    /// mid-refresh (task-7 regression coverage: background refresh must never
    /// transition through `.loading`).
    private var shouldSuspendNextLoad = false
    private var suspensionContinuation: CheckedContinuation<Void, Never>?

    /// True once a suspended `loadTasks` call is parked awaiting `resumeSuspendedLoad()`.
    private(set) var isSuspended = false

    func armSuspension() {
        shouldSuspendNextLoad = true
    }

    func resumeSuspendedLoad() {
        isSuspended = false
        suspensionContinuation?.resume()
        suspensionContinuation = nil
    }

    func loadTasks(from directory: URL) async throws -> ParseResult {
        if shouldSuspendNextLoad {
            shouldSuspendNextLoad = false
            isSuspended = true
            await withCheckedContinuation { continuation in
                suspensionContinuation = continuation
            }
        }
        let items = try loadTasksResult.get()
        return ParseResult(structuredTasks: items, claudeTasks: claudeTasksResult, orphanedTasks: orphanedTasksResult)
    }

    func peekSessionInfo(in directory: URL) async -> SessionInfo {
        SessionInfo(epicName: nil, epicDisplayId: nil, taskCount: 0)
    }
}

final class MockBackupService: BackupServiceProtocol, @unchecked Sendable {
    var performBackupResult: Result<Void, Error> = .success(())

    func performBackup(from source: URL, to destination: URL) async throws {
        try performBackupResult.get()
    }
}

// MARK: - SessionViewModelTests

@MainActor
// swiftlint:disable:next type_body_length
final class SessionViewModelTests: XCTestCase {

    // MARK: - Properties

    private var sut: SessionViewModel!
    private var mockProductService: MockProductService!
    private var mockSessionService: MockSessionService!
    private var mockParserService: MockParserService!
    private var mockBackupService: MockBackupService!

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
        id: UUID = UUID(),
        path: URL = URL(fileURLWithPath: "/tmp/session"),
        modifiedDate: Date = Date()
    ) -> TaskSession {
        TaskSession(id: id, path: path, modifiedDate: modifiedDate)
    }

    /// Polls (yielding to the MainActor between checks) until `mockParserService`
    /// reports it has parked in a suspended `loadTasks` call, or `attempts` is
    /// exhausted. Used to deterministically observe `SessionViewModel.state`
    /// while a refresh is in flight.
    private func waitForParserSuspension(attempts: Int = 50) async {
        var remaining = attempts
        while !mockParserService.isSuspended && remaining > 0 {
            await Task.yield()
            remaining -= 1
        }
    }

    private func makeTaskItem(id: String) throws -> TaskItem {
        let json = """
        {
          "id": "\(id)",
          "subject": "Task \(id)",
          "description": "Description",
          "status": "pending",
          "blocks": [],
          "blockedBy": [],
          "metadata": {
            "type": "task",
            "priority": "P2",
            "approval": "approved",
            "blocked": false
          }
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try JSONDecoder().decode(TaskItem.self, from: data)
    }

    // MARK: - Initial State

    func testInitialState() {
        XCTAssertEqual(sut.state, .idle)
        XCTAssertTrue(sut.products.isEmpty)
        XCTAssertNil(sut.selectedProduct)
        XCTAssertTrue(sut.sessions.isEmpty)
        XCTAssertNil(sut.selectedSession)
        XCTAssertTrue(sut.tasks.isEmpty)
        XCTAssertTrue(sut.claudeTasks.isEmpty)
        XCTAssertTrue(sut.orphanedTasks.isEmpty)
        XCTAssertEqual(sut.parsedCount, 0)
        XCTAssertEqual(sut.totalCount, 0)
        XCTAssertNil(sut.lastRefreshed)
        XCTAssertTrue(sut.staleProductIDs.isEmpty)
        XCTAssertFalse(sut.showingNewProductSheet)
        XCTAssertFalse(sut.showingEditProductSheet)
        XCTAssertFalse(sut.showingDeleteAlert)
    }

    // MARK: - loadProducts: State Transitions

    func testLoadProductsWithNoProductsReachesLoadedState() async {
        mockProductService.loadProductsResult = .success([])
        mockSessionService.getRecentSessionsResult = .success([])

        await sut.loadProducts()

        XCTAssertEqual(sut.state, .loaded)
    }

    // MARK: - Bug 105 Regression: No-products fallback to session discovery

    func testLoadProductsWithNoProductsAutoDiscoversSessions() async {
        // REGRESSION TEST: Before the fix, loadProducts() with empty products would set
        // state = .loaded and stop — never calling getRecentSessions(). The app would
        // stay in idle/loaded with no sessions discovered.
        let session = makeSession(id: UUID(), path: URL(fileURLWithPath: "/tmp/auto-discovered"), modifiedDate: Date())
        mockProductService.loadProductsResult = .success([])
        mockSessionService.getRecentSessionsResult = .success([session])
        mockParserService.loadTasksResult = .success([])

        await sut.loadProducts()

        XCTAssertEqual(sut.sessions.count, 1,
                       "Sessions should be discovered even when no products are registered")
        XCTAssertEqual(sut.selectedSession?.path, URL(fileURLWithPath: "/tmp/auto-discovered"),
                       "Most recent session should be auto-selected")
        XCTAssertNil(sut.selectedProduct,
                     "selectedProduct must remain nil — no product was loaded")
        XCTAssertEqual(sut.state, .loaded)
    }

    func testLoadProductsWithNoProductsAndNoSessionsReachesLoadedState() async {
        // When no products AND no sessions exist, state should reach .loaded (not stay .idle).
        mockProductService.loadProductsResult = .success([])
        mockSessionService.getRecentSessionsResult = .success([])

        await sut.loadProducts()

        XCTAssertEqual(sut.state, .loaded)
        XCTAssertTrue(sut.sessions.isEmpty)
        XCTAssertNil(sut.selectedSession)
    }

    func testLoadProductsWithNoProductsSessionDiscoveryErrorSetsErrorState() async {
        // When no products but session discovery throws, state should be .error.
        mockProductService.loadProductsResult = .success([])
        mockSessionService.getRecentSessionsResult = .failure(AgileMaestroError.sessionDirectoryNotFound)

        await sut.loadProducts()

        guard case .error = sut.state else {
            XCTFail("Expected .error state when session discovery fails, got \(sut.state)")
            return
        }
    }

    func testLoadProductsPopulatesProductsArray() async {
        let products = [Product(name: "Alpha"), Product(name: "Beta")]
        mockProductService.loadProductsResult = .success(products)
        mockSessionService.getRecentSessionsResult = .success([])

        await sut.loadProducts()

        XCTAssertEqual(sut.products.count, 2)
    }

    func testLoadProductsAutoSelectsFirstProduct() async {
        let product = Product(name: "First")
        mockProductService.loadProductsResult = .success([product])
        mockSessionService.getRecentSessionsResult = .success([])

        await sut.loadProducts()

        XCTAssertEqual(sut.selectedProduct?.name, "First")
    }

    func testLoadProductsWithNoProductsLeavesSelectedProductNil() async {
        mockProductService.loadProductsResult = .success([])

        await sut.loadProducts()

        XCTAssertNil(sut.selectedProduct)
    }

    func testLoadProductsOnAgileMaestroErrorSetsErrorState() async {
        let error = AgileMaestroError.productSaveFailed(underlying: URLError(.badURL))
        mockProductService.loadProductsResult = .failure(error)

        await sut.loadProducts()

        guard case .error = sut.state else {
            XCTFail("Expected .error state, got \(sut.state)")
            return
        }
    }

    func testLoadProductsOnGenericErrorSetsErrorState() async {
        struct ArbitraryError: Error {}
        mockProductService.loadProductsResult = .failure(ArbitraryError())

        await sut.loadProducts()

        guard case .error = sut.state else {
            XCTFail("Expected .error state, got \(sut.state)")
            return
        }
    }

    // MARK: - loadSessions: Auto-Selection (AC3)

    func testLoadSessionsAutoSelectsMostRecentSession() async {
        let product = Product(name: "Test")
        let olderDate = Date(timeIntervalSinceNow: -3600)
        let newerDate = Date(timeIntervalSinceNow: -60)

        // Sessions come in sorted newest-first from the service.
        let newerSession = makeSession(id: UUID(), modifiedDate: newerDate)
        let olderSession = makeSession(id: UUID(), modifiedDate: olderDate)
        mockSessionService.getRecentSessionsResult = .success([newerSession, olderSession])
        mockParserService.loadTasksResult = .success([])

        await sut.loadSessions(for: product)

        XCTAssertEqual(sut.selectedSession?.id, newerSession.id,
                       "loadSessions should auto-select the first (most recent) session")
    }

    func testLoadSessionsWithNoSessionsSetsLoadedState() async {
        let product = Product(name: "Empty")
        mockSessionService.getRecentSessionsResult = .success([])

        await sut.loadSessions(for: product)

        XCTAssertEqual(sut.state, .loaded)
        XCTAssertNil(sut.selectedSession)
    }

    func testLoadSessionsPopulatesSessionsArray() async {
        let product = Product(name: "Test")
        let session1 = makeSession()
        let session2 = makeSession()
        mockSessionService.getRecentSessionsResult = .success([session1, session2])
        mockParserService.loadTasksResult = .success([])

        await sut.loadSessions(for: product)

        XCTAssertEqual(sut.sessions.count, 2)
    }

    func testLoadSessionsOnAgileMaestroErrorSetsErrorState() async {
        let product = Product(name: "Test")
        mockSessionService.getRecentSessionsResult = .failure(AgileMaestroError.sessionDirectoryNotFound)

        await sut.loadSessions(for: product)

        guard case .error = sut.state else {
            XCTFail("Expected .error state, got \(sut.state)")
            return
        }
    }

    func testLoadSessionsOnGenericErrorSetsErrorState() async {
        let product = Product(name: "Test")
        struct ArbitraryError: Error {}
        mockSessionService.getRecentSessionsResult = .failure(ArbitraryError())

        await sut.loadSessions(for: product)

        guard case .error = sut.state else {
            XCTFail("Expected .error state, got \(sut.state)")
            return
        }
    }

    // MARK: - refreshCurrentSession

    func testRefreshCurrentSessionWithNoSelectedSessionIsNoOp() async {
        // No session is selected — refreshCurrentSession should do nothing.
        await sut.refreshCurrentSession()

        XCTAssertEqual(sut.state, .idle, "State should remain idle when no session is selected")
        XCTAssertTrue(sut.tasks.isEmpty)
    }

    func testRefreshCurrentSessionLoadsTasksAndReachesLoadedState() async {
        // First, select a session by going through selectSession.
        let session = makeSession()
        let task1 = try? makeTaskItem(id: "1")
        let task2 = try? makeTaskItem(id: "2")
        mockParserService.loadTasksResult = .success([task1, task2].compactMap { $0 })

        await sut.selectSession(session)

        XCTAssertEqual(sut.tasks.count, 2)
        XCTAssertEqual(sut.parsedCount, 2)
        XCTAssertNotNil(sut.lastRefreshed)
        XCTAssertEqual(sut.state, .loaded)
    }

    func testRefreshCurrentSessionFirstLoadOnErrorSetsErrorState() async {
        // No prior loaded content — a failure on the very first load has nothing
        // to preserve on screen, so it should transition to .error.
        let session = makeSession()
        mockParserService.loadTasksResult = .failure(AgileMaestroError.noTasksFound(path: session.path))

        await sut.selectSession(session)

        guard case .error = sut.state else {
            XCTFail("Expected .error state after a failed first load, got \(sut.state)")
            return
        }
    }

    func testRefreshCurrentSessionFirstLoadTransitionsThroughLoadingThenLoaded() async {
        // The very first load (state starts at .idle) should still show the
        // full loading state while in flight, then reach .loaded.
        let session = makeSession()
        mockParserService.loadTasksResult = .success([])
        mockParserService.armSuspension()

        let selectTask = Task { await sut.selectSession(session) }
        await waitForParserSuspension()

        XCTAssertEqual(sut.state, .loading, "First load should show .loading while data is in flight")

        mockParserService.resumeSuspendedLoad()
        await selectTask.value

        XCTAssertEqual(sut.state, .loaded)
    }

    func testRefreshCurrentSessionBackgroundRefreshNeverEntersLoadingState() async {
        // First load succeeds, reaching .loaded with content on screen.
        let session = makeSession()
        let task1 = try? makeTaskItem(id: "1")
        mockParserService.loadTasksResult = .success([task1].compactMap { $0 })
        await sut.selectSession(session)
        XCTAssertEqual(sut.state, .loaded)

        // A background refresh (triggered by the file watcher or the refresh
        // button) must keep existing content on screen — never swap to .loading —
        // while new data loads.
        mockParserService.armSuspension()
        let refreshTask = Task { await sut.refreshCurrentSession() }
        await waitForParserSuspension()

        XCTAssertEqual(sut.state, .loaded, "Background refresh must not leave .loaded before new data arrives")
        XCTAssertTrue(sut.isRefreshing, "Toolbar spinner should still indicate the refresh in progress")
        XCTAssertEqual(sut.tasks.count, 1, "Existing content must remain visible during the background refresh")

        mockParserService.resumeSuspendedLoad()
        await refreshTask.value

        XCTAssertEqual(sut.state, .loaded)
    }

    func testRefreshCurrentSessionBackgroundRefreshFailureKeepsLoadedStateAndData() async {
        // First load succeeds with content.
        let session = makeSession()
        let task1 = try? makeTaskItem(id: "1")
        mockParserService.loadTasksResult = .success([task1].compactMap { $0 })
        await sut.selectSession(session)
        XCTAssertEqual(sut.state, .loaded)
        XCTAssertEqual(sut.tasks.count, 1)

        // Background refresh fails — existing content must stay on screen instead
        // of being replaced by ErrorStateView.
        let refreshError = AgileMaestroError.noTasksFound(path: session.path)
        mockParserService.loadTasksResult = .failure(refreshError)
        await sut.refreshCurrentSession()

        XCTAssertEqual(sut.state, .loaded, "Background refresh failure must not replace loaded content with .error")
        XCTAssertEqual(sut.tasks.count, 1, "Prior task data must be preserved on a failed background refresh")
        XCTAssertNotNil(sut.refreshError, "Failure should be recorded non-destructively for the refresh indicator")
    }

    // MARK: - selectSession

    func testSelectSessionSetsSelectedSession() async {
        let session = makeSession()
        mockParserService.loadTasksResult = .success([])

        await sut.selectSession(session)

        XCTAssertEqual(sut.selectedSession?.id, session.id)
    }

    // MARK: - openDirectory

    func testOpenDirectoryCreatesTransientSessionWithGivenURL() async {
        let url = URL(fileURLWithPath: "/tmp/test-dir")
        mockParserService.loadTasksResult = .success([])

        await sut.openDirectory(url: url)

        XCTAssertEqual(sut.selectedSession?.path, url)
    }

    // MARK: - claudeTasks and orphanedTasks

    func testRefreshCurrentSessionPopulatesClaudeTasksAndOrphanedTasks() async {
        let claude = ClaudeTask(
            id: "ct-1",
            subject: "Claude task",
            description: nil,
            status: "pending",
            blocks: [],
            blockedBy: [],
            rawFields: [:]
        )
        let orphaned = OrphanedTask(
            filename: "bad.json",
            errorMessage: "key not found",
            partialFields: [:],
            rawJSON: "{}"
        )
        let session = makeSession()
        mockParserService.loadTasksResult = .success([])
        mockParserService.claudeTasksResult = [claude]
        mockParserService.orphanedTasksResult = [orphaned]

        await sut.selectSession(session)

        XCTAssertEqual(sut.claudeTasks.count, 1)
        XCTAssertEqual(sut.claudeTasks.first?.id, "ct-1")
        XCTAssertEqual(sut.orphanedTasks.count, 1)
        XCTAssertEqual(sut.orphanedTasks.first?.filename, "bad.json")
    }

    func testRemoveSelectedProductClearsClaudeTasksAndOrphanedTasks() async throws {
        // Arrange: load product, select session, populate claude + orphaned tasks.
        let product = Product(name: "Test")
        let session = makeSession()
        mockProductService.loadProductsResult = .success([product])
        mockSessionService.getRecentSessionsResult = .success([session])
        mockParserService.loadTasksResult = .success([])
        mockParserService.claudeTasksResult = [
            ClaudeTask(
                id: "ct-1", subject: "X", description: nil,
                status: nil, blocks: [], blockedBy: [], rawFields: [:]
            )
        ]
        mockParserService.orphanedTasksResult = [
            OrphanedTask(filename: "x.json", errorMessage: "err", partialFields: [:], rawJSON: "{}")
        ]
        await sut.loadProducts()

        XCTAssertFalse(sut.claudeTasks.isEmpty, "claudeTasks should be populated before removal")
        XCTAssertFalse(sut.orphanedTasks.isEmpty, "orphanedTasks should be populated before removal")

        // Act: remove the only product (triggers clear path).
        mockProductService.saveProductsResult = .success(())
        try await sut.removeProduct(product)

        XCTAssertTrue(sut.claudeTasks.isEmpty, "claudeTasks should clear when all products are removed")
        XCTAssertTrue(sut.orphanedTasks.isEmpty, "orphanedTasks should clear when all products are removed")
    }

    func testLoadAndHandleSessionsWithNoSessionsClearsClaudeTasksAndOrphanedTasks() async {
        // Arrange: populate tasks via a session, then load with no sessions.
        let session = makeSession()
        mockParserService.loadTasksResult = .success([])
        mockParserService.claudeTasksResult = [
            ClaudeTask(
                id: "ct-1", subject: "X", description: nil,
                status: nil, blocks: [], blockedBy: [], rawFields: [:]
            )
        ]
        mockParserService.orphanedTasksResult = [
            OrphanedTask(filename: "x.json", errorMessage: "err", partialFields: [:], rawJSON: "{}")
        ]
        await sut.selectSession(session)
        XCTAssertFalse(sut.claudeTasks.isEmpty)

        // Act: load sessions for a product that has none.
        let product = Product(name: "Empty")
        mockSessionService.getRecentSessionsResult = .success([])
        await sut.loadSessions(for: product)

        XCTAssertNil(sut.selectedSession)
        XCTAssertTrue(sut.claudeTasks.isEmpty, "claudeTasks should clear when sessions list is empty")
        XCTAssertTrue(sut.orphanedTasks.isEmpty, "orphanedTasks should clear when sessions list is empty")
    }

}
