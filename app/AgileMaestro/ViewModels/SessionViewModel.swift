import Foundation
import Observation
import OSLog

// MARK: - LoadingState

/// Represents the loading lifecycle of an async operation in the app shell.
///
/// Shared by `SessionViewModel` and future ViewModels that require
/// a loading/loaded/error state machine.
enum LoadingState: Equatable {
    case idle
    case loading
    case loaded
    case error(AgileMaestroError)

    // MARK: - Equatable

    static func == (lhs: LoadingState, rhs: LoadingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.loaded, .loaded):
            return true
        case (.error(let lhsErr), .error(let rhsErr)):
            return lhsErr.localizedDescription == rhsErr.localizedDescription
        default:
            return false
        }
    }
}

// MARK: - SessionViewModel

/// Drives product and session selection for the app shell toolbar.
///
/// `SessionViewModel` owns the canonical "which product and session are we looking
/// at" state. It discovers products via `ProductServiceProtocol`, discovers sessions
/// via `TaskSessionServiceProtocol`, and auto-selects the most recently modified
/// session on launch. `TreeViewModel` reads from `selectedSession` to build the
/// task tree.
///
/// ## Dependency Injection
/// All service dependencies are injected through initializer parameters, enabling
/// full unit-test isolation with mock implementations.
///
/// ## File watching
/// `FileWatcherService` triggers `refreshCurrentSession()` whenever the watched
/// session directory changes on disk. The watcher is started when `selectedSession`
/// is set and stopped when it changes or the object is deallocated.
@Observable
@MainActor
// swiftlint:disable:next type_body_length
final class SessionViewModel {

    // MARK: - State

    /// Current loading state for the view layer to react to.
    private(set) var state: LoadingState = .idle

    // MARK: - Products

    /// All registered products loaded from disk.
    private(set) var products: [Product] = []

    /// The currently selected product. Setting this triggers session discovery.
    private(set) var selectedProduct: Product?

    // MARK: - Sessions

    /// Sessions discovered for the currently selected product's task directory.
    private(set) var sessions: [TaskSession] = []

    /// The currently active task session. Changes trigger `TreeViewModel` refresh.
    private(set) var selectedSession: TaskSession?

    // MARK: - Tasks

    /// Tasks parsed from `selectedSession`. Populated by `refreshCurrentSession()`.
    private(set) var tasks: [TaskItem] = []

    /// Claude Code tasks (epics, stories, raw tasks) parsed from `selectedSession`.
    /// Populated by `refreshCurrentSession()`. Cleared when sessions change.
    private(set) var claudeTasks: [ClaudeTask] = []

    /// Task files that could not be parsed — either malformed JSON, missing required
    /// fields, or metadata that doesn't conform to the expected schema.
    /// Populated by `refreshCurrentSession()`. Cleared when sessions change.
    private(set) var orphanedTasks: [OrphanedTask] = []

    /// Number of tasks successfully parsed from the current session directory.
    private(set) var parsedCount: Int = 0

    /// Total JSON files found in the current session directory (including unparseable files).
    private(set) var totalCount: Int = 0

    // MARK: - Refresh

    /// The date of the last successful session refresh. Used for time-ago display.
    private(set) var lastRefreshed: Date?

    /// Whether a refresh is currently in progress. Drives `arrow.clockwise` rotation.
    private(set) var isRefreshing: Bool = false

    /// Relative time string for the last refresh ("just now", "2m ago", "1h ago").
    /// Returns an empty string if the session has never been refreshed.
    var lastRefreshedText: String {
        guard let date = lastRefreshed else { return "" }
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 60 {
            return "just now"
        } else if elapsed < 3600 {
            let minutes = Int(elapsed / 60)
            return "\(minutes)m ago"
        } else {
            let hours = Int(elapsed / 3600)
            return "\(hours)h ago"
        }
    }

    // MARK: - Stale Product Detection

    /// IDs of products whose `associatedSessionPath` no longer exists on disk.
    ///
    /// Updated by `checkProductStaleness()`. Views observe this set to render
    /// warning badges on chips whose backing directory is missing.
    private(set) var staleProductIDs: Set<UUID> = []

    // MARK: - Product CRUD Bindings

    /// Controls visibility of the New Product sheet in the toolbar.
    var showingNewProductSheet: Bool = false

    /// Controls visibility of the Edit Product sheet in the toolbar.
    var showingEditProductSheet: Bool = false

    /// Controls visibility of the Delete Product confirmation alert.
    var showingDeleteAlert: Bool = false

    // MARK: - Constants

    private static let lastProductIDKey = "selectedProductID"

    // MARK: - Private Properties

    private let productService: ProductServiceProtocol
    private let sessionService: TaskSessionServiceProtocol
    private let parserService: TaskParserServiceProtocol
    private let backupService: BackupServiceProtocol
    private let fileWatcher: FileWatcherService
    private let defaults: UserDefaults

    private let logger = Logger.app

    // MARK: - Init

    /// Creates a `SessionViewModel` with injected service dependencies.
    ///
    /// - Parameters:
    ///   - productService: Service for persisting and loading products.
    ///   - sessionService: Service for discovering Claude Code task sessions.
    ///   - parserService: Service for parsing task JSON files.
    ///   - backupService: Service for copying session JSON files to a product backup directory.
    ///   - fileWatcher: Service for watching session directories for changes.
    init(
        productService: ProductServiceProtocol = ProductService.shared,
        sessionService: TaskSessionServiceProtocol = TaskSessionService.shared,
        parserService: TaskParserServiceProtocol = TaskParserService.shared,
        backupService: BackupServiceProtocol = BackupService.shared,
        fileWatcher: FileWatcherService = FileWatcherService(),
        defaults: UserDefaults = .standard
    ) {
        self.productService = productService
        self.sessionService = sessionService
        self.parserService = parserService
        self.backupService = backupService
        self.fileWatcher = fileWatcher
        self.defaults = defaults

        setupFileWatcher()
    }

    // MARK: - Public API

    /// Checks which registered products have a missing task directory on disk.
    ///
    /// Iterates `products` and uses `FileManager` to verify each product's
    /// `associatedSessionPath` exists as a directory. Any product whose path is
    /// absent or not a directory is added to `staleProductIDs`.
    ///
    /// Call this after loading products, after selecting a product, and after
    /// refreshing the current session so the UI stays in sync.
    func checkProductStaleness() {
        var stale: Set<UUID> = []
        for product in products {
            guard let rawPath = product.associatedSessionPath else {
                // No path configured — treat as stale so the user can re-browse.
                stale.insert(product.id)
                continue
            }
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: rawPath, isDirectory: &isDir)
            if !exists || !isDir.boolValue {
                stale.insert(product.id)
            }
        }
        staleProductIDs = stale
        if !stale.isEmpty {
            logger.info("Stale products detected: \(stale.count)")
        }
    }

    /// Loads all registered products from disk and auto-selects the first one.
    ///
    /// After loading products, immediately loads sessions for the selected product.
    /// If no products are registered (Phase 1-5 state, no products.json), falls through
    /// to auto-discover sessions directly from `~/.claude/tasks/` via `TaskSessionService`.
    /// Transitions `state` through `.loading` → `.loaded` or `.error`.
    func loadProducts() async {
        state = .loading
        do {
            let loaded = try await productService.loadProducts()
            products = loaded
            logger.info("Loaded \(loaded.count) products")
            checkProductStaleness()

            if let restored = restoreProduct(from: loaded) ?? loaded.first {
                selectedProduct = restored
                saveSelectedProductID(restored)
                await loadSessions(for: restored)
            } else {
                // No products registered (Phase 1-5): auto-discover sessions directly.
                // Clear any stale product/session state before discovery so the UI
                // doesn't show leftover values from a previous loadProducts() call.
                selectedProduct = nil
                selectedSession = nil
                logger.info("No products found — falling through to direct session discovery")
                await loadSessionsWithoutProduct()
            }
        } catch let error as AgileMaestroError {
            logger.error("Failed to load products: \(error.localizedDescription)")
            state = .error(error)
        } catch {
            logger.error("Failed to load products: \(error.localizedDescription)")
            state = .error(.productSaveFailed(underlying: error))
        }
    }

    /// Discovers and enriches sessions directly from `~/.claude/tasks/` when no products
    /// are configured. This is the Phase 1-5 path where products.json doesn't exist yet.
    ///
    /// Auto-selects the most recently modified session. Transitions `state` through
    /// `.loading` → `.loaded` or `.error`.
    private func loadSessionsWithoutProduct() async {
        await loadAndHandleSessions(
            logContext: "Direct session discovery",
            errorFallback: .sessionDirectoryNotReadable(
                path: FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".claude/tasks")
            )
        ) {
            try await self.sessionService.getRecentSessions(maxSessions: 10)
        }
    }

    /// Discovers and enriches sessions for a given product.
    ///
    /// If the product has an `associatedSessionPath`, the path type is detected:
    /// - **Session directory** (contains .json files): A `TaskSession` is created directly
    ///   from the URL, matching the behaviour of `openDirectory(url:)`.
    /// - **Tasks root** (contains subdirectories): Subdirectories are scanned to find
    ///   individual sessions, which is the original discovery behaviour.
    ///
    /// This detection step is necessary because the user may select a session directory
    /// (e.g. `~/.claude/tasks/<list-id>/`) rather than the tasks root
    /// (`~/.claude/tasks/`). Without it, `TaskSessionService.getRecentSessions(from:)`
    /// would scan the selected directory for subdirectories, find none, and return an
    /// empty session list.
    ///
    /// Falls back to the global `sessionService` (i.e. `~/.claude/tasks/`) when no path
    /// is configured.
    ///
    /// Sessions are sorted by `modifiedDate` descending; the most recent is
    /// auto-selected. Transitions `state` through `.loading` → `.loaded` or `.error`.
    ///
    /// - Parameter product: The product whose associated Claude tasks directory is scanned.
    func loadSessions(for product: Product) async {
        let sessionPath: URL
        if let rawPath = product.associatedSessionPath {
            let candidateURL = URL(fileURLWithPath: rawPath).standardized.resolvingSymlinksInPath()
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidateURL.path, isDirectory: &isDir), isDir.boolValue {
                sessionPath = candidateURL
            } else {
                logger.warning("Product session path invalid or not a directory: \(rawPath) — falling back to default")
                sessionPath = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".claude/tasks")
            }
        } else {
            sessionPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/tasks")
        }

        // Detect whether sessionPath is itself a session directory (contains .json task
        // files) or a tasks root (contains subdirectories that are session directories).
        // The user may pick a session directory directly via the product picker, in which
        // case getRecentSessions(from:) would scan for subdirectories and return nothing.
        if isSessionDirectory(sessionPath) {
            logger.info("Product '\(product.name)' path is a session directory — loading directly")
            let directSession = TaskSession(id: UUID(), path: sessionPath, modifiedDate: Date())
            await loadAndHandleSessions(
                logContext: "Direct session for product '\(product.name)'",
                errorFallback: .sessionDirectoryNotReadable(path: sessionPath)
            ) { [directSession] in
                [directSession]
            }
        } else {
            await loadAndHandleSessions(
                logContext: "Discovered sessions for product '\(product.name)'",
                errorFallback: .sessionDirectoryNotReadable(path: sessionPath)
            ) { [sessionService] in
                try await sessionService.getRecentSessions(from: sessionPath, maxSessions: 10)
            }
        }
    }

    /// Returns `true` when `url` looks like a session directory, i.e. it contains
    /// at least one `.json` file at the top level.
    ///
    /// This heuristic distinguishes a session directory (individual task JSON files)
    /// from a tasks root (subdirectories, each being a session directory).
    private func isSessionDirectory(_ url: URL) -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return false }
        return contents.contains { $0.pathExtension == "json" }
    }

    /// Shared fetch-enrich-assign-select-error helper used by both session discovery paths.
    ///
    /// Fetches raw sessions via `fetch`, enriches them, assigns them to `sessions`,
    /// auto-selects the newest, and handles errors uniformly. Sets `state` to `.loading`
    /// at entry; resolves to `.loaded` or `.error` on exit.
    ///
    /// - Parameters:
    ///   - logContext: Label used in info/error log messages.
    ///   - errorFallback: The `AgileMaestroError` to use when a non-typed error is caught.
    ///   - fetch: Closure that performs the raw session fetch.
    private func loadAndHandleSessions(
        logContext: String,
        errorFallback: AgileMaestroError,
        fetch: @escaping () async throws -> [TaskSession]
    ) async {
        state = .loading
        do {
            let raw = try await fetch()
            let enriched = await sessionService.enrichSessions(raw, using: parserService)

            sessions = enriched
            logger.info("\(logContext): \(enriched.count) sessions found")

            if let newest = enriched.first {
                await selectSession(newest)
            } else {
                selectedSession = nil
                tasks = []
                claudeTasks = []
                orphanedTasks = []
                state = .loaded
            }
        } catch let error as AgileMaestroError {
            logger.error("\(logContext) failed: \(error.localizedDescription)")
            state = .error(error)
        } catch {
            logger.error("\(logContext) failed: \(error.localizedDescription)")
            state = .error(errorFallback)
        }
    }

    /// Selects a product and loads its sessions.
    ///
    /// Also re-runs staleness detection so the warning badge on the newly
    /// selected product chip reflects current filesystem state.
    ///
    /// - Parameter product: The product to select.
    func selectProduct(_ product: Product) {
        guard selectedProduct?.id != product.id else { return }
        selectedProduct = product
        saveSelectedProductID(product)
        logger.info("Selected product: \(product.name)")
        checkProductStaleness()
        Task {
            await loadSessions(for: product)
        }
    }

    /// Selects a session and loads its tasks from disk.
    ///
    /// Updates `selectedSession`, starts the file watcher on the session directory,
    /// and loads all tasks via `refreshCurrentSession()`.
    ///
    /// - Parameter session: The session to select.
    func selectSession(_ session: TaskSession) async {
        selectedSession = session
        logger.info("Selected session: \(session.displayName)")
        fileWatcher.start(watching: session.path)
        await refreshCurrentSession()
    }

    /// Reloads task data from the currently selected session directory.
    ///
    /// Updates `tasks`, `parsedCount`, `totalCount`, and `lastRefreshed`.
    /// Sets `state` to `.loaded` on success or `.error` on failure.
    /// Sets `isRefreshing` to `true` while the reload is in progress.
    func refreshCurrentSession() async {
        guard let session = selectedSession else {
            logger.debug("refreshCurrentSession called with no selected session — skipping")
            return
        }

        isRefreshing = true
        state = .loading
        defer { isRefreshing = false }
        do {
            let parseResult = try await parserService.loadTasks(from: session.path)
            let loaded = parseResult.structuredTasks
            tasks = loaded
            claudeTasks = parseResult.claudeTasks
            orphanedTasks = parseResult.orphanedTasks
            parsedCount = loaded.count
            totalCount = loaded.count
            lastRefreshed = Date()
            state = .loaded
            checkProductStaleness()
            let structured = loaded.count
            let claude = parseResult.claudeTasks.count
            let orphaned = parseResult.orphanedTasks.count
            logger.info("Refreshed: \(structured) structured, \(claude) claude, \(orphaned) orphaned")

            // Fire-and-forget backup: runs in the background without blocking the refresh.
            // Only backs up when a product is selected (provides the backup destination).
            if let product = selectedProduct {
                let source = session.path
                let destination = product.backupDirectoryURL
                let backupService = backupService
                Task {
                    do {
                        try await backupService.performBackup(from: source, to: destination)
                        Logger.backup.info("Backup succeeded for session '\(session.displayName)'")
                    } catch {
                        Logger.backup.error("Backup failed for session '\(session.displayName)': \(error)")
                    }
                }
            }
        } catch let error as AgileMaestroError {
            logger.error("Refresh failed: \(error.localizedDescription)")
            state = .error(error)
        } catch {
            logger.error("Refresh failed: \(error.localizedDescription)")
            state = .error(.noTasksFound(path: session.path))
        }
    }

    /// Opens an arbitrary directory URL as a transient (ad-hoc) task session.
    ///
    /// Creates a session directly from `url` without persisting it to the product
    /// list. Useful for drag-and-drop or the open-directory file panel.
    ///
    /// - Parameter url: The directory URL selected by the user.
    func openDirectory(url: URL) async {
        let transient = TaskSession(
            id: UUID(),
            path: url,
            modifiedDate: Date()
        )
        logger.info("Opening directory as transient session: \(url.path)")
        await selectSession(transient)
    }

    // MARK: - Product CRUD

    /// Creates a new product, persists it, and selects it.
    ///
    /// Builds a `Product` from the provided parameters, appends it to the current
    /// products array, saves the updated registry to `products.json`, and sets
    /// `selectedProduct` to the newly created product.
    ///
    /// - Parameters:
    ///   - name: Display name for the new product.
    ///   - taskDirectoryPath: Path to the Claude task list directory (`~/.claude/tasks/…`).
    ///   - toolkitDirectoryPath: Optional path to the `.claude/` toolkit directory.
    /// - Throws: If the save to `products.json` fails.
    func createProduct(
        name: String,
        taskDirectoryPath: String,
        toolkitDirectoryPath: String?
    ) async throws {
        let newProduct = Product(
            name: name,
            associatedSessionPath: taskDirectoryPath,
            claudeDirectoryPath: toolkitDirectoryPath
        )
        var updated = products
        updated.append(newProduct)
        try await productService.saveProducts(updated)
        products = updated
        selectedProduct = newProduct
        saveSelectedProductID(newProduct)
        logger.info("Created product '\(name)' (\(newProduct.id.uuidString))")
        await loadSessions(for: newProduct)
    }

    /// Updates an existing product's fields and persists the change.
    ///
    /// Replaces the entry in the `products` array whose `id` matches `product.id`.
    /// If the updated product is currently selected, `selectedProduct` is refreshed
    /// to reflect the new field values.
    ///
    /// - Parameter product: The product value carrying the updated fields.
    /// - Throws: `AgileMaestroError.productSaveFailed` if the product is not found,
    ///   or if the save to `products.json` fails.
    func updateProduct(_ product: Product) async throws {
        guard let index = products.firstIndex(where: { $0.id == product.id }) else {
            logger.error("updateProduct called with unknown product id \(product.id.uuidString)")
            throw AgileMaestroError.productSaveFailed(
                underlying: NSError(
                    domain: "AgileMaestro",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Product not found: \(product.id.uuidString)"]
                )
            )
        }
        var updated = products
        updated[index] = product
        try await productService.saveProducts(updated)
        products = updated
        if selectedProduct?.id == product.id {
            selectedProduct = product
        }
        logger.info("Updated product '\(product.name)' (\(product.id.uuidString))")
    }

    /// Removes a product from the registry and updates the selection.
    ///
    /// Removes the product from `products`, saves the updated registry to
    /// `products.json`, and updates `selectedProduct`: if the removed product was
    /// selected, selects the first remaining product or sets `selectedProduct` to
    /// `nil` when the list is empty.
    ///
    /// Only the `products.json` registry entry is modified; backup directories are
    /// preserved on disk and are not touched by this operation.
    ///
    /// - Parameter product: The product to remove.
    /// - Throws: If the save to `products.json` fails.
    func removeProduct(_ product: Product) async throws {
        let updated = products.filter { $0.id != product.id }
        try await productService.saveProducts(updated)
        products = updated
        if selectedProduct?.id == product.id {
            selectedProduct = updated.first
            saveSelectedProductID(updated.first)
            if let next = updated.first {
                await loadSessions(for: next)
            } else {
                sessions = []
                selectedSession = nil
                tasks = []
                claudeTasks = []
                orphanedTasks = []
                state = .idle
            }
        }
        logger.info("Removed product '\(product.name)' (\(product.id.uuidString))")
    }

    // MARK: - Private Helpers

    private func setupFileWatcher() {
        fileWatcher.onChange = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.refreshCurrentSession()
            }
        }
    }

    private func saveSelectedProductID(_ product: Product?) {
        defaults.set(product?.id.uuidString, forKey: Self.lastProductIDKey)
    }

    private func restoreProduct(from products: [Product]) -> Product? {
        guard let savedID = defaults.string(forKey: Self.lastProductIDKey),
              let uuid = UUID(uuidString: savedID) else { return nil }
        return products.first { $0.id == uuid }
    }
}
