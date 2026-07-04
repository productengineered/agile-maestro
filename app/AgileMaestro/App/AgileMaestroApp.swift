import SwiftUI
import AppKit

// MARK: - ProductWindowIdentity

/// Value-based identity used to key each window/tab opened by `AgileMaestroApp`'s
/// `WindowGroup(for:)` scene.
///
/// Two cases:
/// - `.product(Product.ID)`: a window showing a specific product. Value-equality
///   dedup (`openWindow(value:)` focuses an existing window whose bound value is
///   equal — research-window-tabbing.md Claim 1, `[VERIFIED]`) means opening the
///   same product id twice focuses the existing window/tab instead of creating a
///   new one.
/// - `.empty(UUID)`: a "New Tab" placeholder window (SCR-EMPTY) with no product
///   selected yet. The associated `UUID` is a **synthetic sentinel** — freshly
///   generated per empty tab via `newEmptySentinel()`, never a literal `nil` —
///   specifically so opening multiple empty tabs (Cmd+T) never dedupes them
///   against each other. A literal-nil (or otherwise shared) identity would
///   collide under `WindowGroup`'s value-equality dedup contract, silently
///   breaking Cmd+T after the first empty tab (would contradict
///   IS-TAB-NEW-800-6). See `planning/design/window-tabs-spec.md`
///   "Open Design Question" and the A3 spike recorded in task AM-803-1's
///   completion comment.
enum ProductWindowIdentity: Hashable, Codable {
    case product(Product.ID)
    case empty(UUID)

    /// A fresh sentinel identity for a new empty tab (SM-TAB-800-T6, Cmd+T).
    /// Always unique — guarantees no dedup collision with any other empty tab.
    static func newEmptySentinel() -> ProductWindowIdentity {
        .empty(UUID())
    }

    /// Decides the SM-EMPTY-800-T3 transition for selecting `product` from an
    /// empty tab's "Choose a Product" CTA (M-800-1), given the set of product
    /// ids already open in another tab/window.
    ///
    /// `openProductIDs` is populated from `WindowRegistrySaveCoordinator
    /// .shared.openProductIDs()` (IS-TAB-FOCUS-800-2, task AM-803-3) at the
    /// real call site in `ProductWindowContentView.selectProduct`. Tests may
    /// still pass an explicit set to exercise both branches directly.
    static func transitionForSelectingProduct(
        _ product: Product,
        openProductIDs: Set<Product.ID>
    ) -> EmptyTabSelectionOutcome {
        if openProductIDs.contains(product.id) {
            return .focusExisting
        }
        return .convertInPlace(.product(product.id))
    }
}

// MARK: - EmptyTabSelectionOutcome

/// Outcome of selecting a product from the empty-tab CTA (M-800-1): either
/// convert this tab's identity in place (Path A, SM-EMPTY-800-T3 "not already
/// open" branch), or defer to the focus-existing dedup path (SM-TAB-800-T8 /
/// IS-TAB-FOCUS-800-2 — implemented in AM-803-3).
enum EmptyTabSelectionOutcome: Equatable {
    case convertInPlace(ProductWindowIdentity)
    case focusExisting
}

// MARK: - AgileMaestroApp

@main
struct AgileMaestroApp: App {

    // AppKit bridge entry point — enables native window tabbing at launch
    // (research-window-tabbing.md Claim 3, `[VERIFIED]`).
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // Declaring `openWindow` directly on the App struct (rather than only inside
    // a View) is the pattern demonstrated for "New Window"-style commands in
    // WWDC22 "Bring multiple windows to your SwiftUI app" (session 10061) — the
    // same session already cited as a `[VERIFIED]` source for Claim 1 in
    // research-window-tabbing.md.
    @Environment(\.openWindow) private var openWindow

    /// Shared identifier so every product window/tab this app opens is eligible
    /// to merge into the same native tab group (research Claim 2/3, `[VERIFIED]`).
    private static let tabbingIdentifier = "com.agilemaestro.product-window"

    // MARK: - Console Integration

    /// Opens Console.app for the user to inspect system logs.
    ///
    /// Console.app does not support `--predicate` as a launch argument — that flag
    /// belongs to the `log` CLI tool. We open Console without arguments and let the
    /// user apply their own filters in its search field.
    ///
    /// Must be called on the main actor because NSWorkspace requires the main thread.
    @MainActor
    static func openConsoleApp() {
        let consolePath = "/System/Applications/Utilities/Console.app"
        let consoleURL = URL(fileURLWithPath: consolePath)

        NSWorkspace.shared.openApplication(
            at: consoleURL,
            configuration: NSWorkspace.OpenConfiguration(),
            completionHandler: nil
        )
    }

    // MARK: - Scene

    var body: some Scene {
        // Value-based WindowGroup: SwiftUI dedups on ProductWindowIdentity equality
        // automatically (research Claim 1, `[VERIFIED]`). The `defaultValue` closure
        // supplies a fresh empty-tab sentinel whenever SwiftUI needs to present a
        // window with no value available (first launch, File > New Window-style
        // opens) — `defaultLaunchBehavior(.presented)` ensures that actually happens
        // at first launch instead of the app starting with zero visible windows,
        // which is otherwise the documented behavior for value-based WindowGroups
        // with no restoration data.
        //
        // `.restorationBehavior(.disabled)` opts OUT of SwiftUI's own automatic
        // scene restoration (research Claim 4, Option B, `[VERIFIED]`) — a future
        // persisted tab registry (AM-803-4/AM-803-5) is the single restore owner,
        // avoiding the documented duplicate-window race from mixing both.
        WindowGroup(
            for: ProductWindowIdentity.self,
            content: { $identity in
                ProductWindowContentView(identity: $identity)
                    .frame(minWidth: 800, minHeight: 600)
                    // Bridges this SwiftUI window to AppKit for tabbing control —
                    // no SwiftUI-native tabbing modifier exists on macOS 26
                    // (research Claim 3, `[VERIFIED]`).
                    .background(
                        WindowAccessor { window in
                            window.tabbingMode = .preferred
                            window.tabbingIdentifier = Self.tabbingIdentifier

                            // Explicit merge (empirically required — see task
                            // AM-803-1's implementation comment for evidence):
                            // WindowAccessor's `configure` closure runs after the
                            // window may already be ordered front via SwiftUI's
                            // `openWindow(value:)` presentation path, which does not
                            // reliably trigger AppKit's automatic same-tabbingIdentifier
                            // merge the way a standard NSDocumentController "New Tab"
                            // flow would. `addTabbedWindow(_:ordered:)` (macOS 10.12+,
                            // not deprecated, `[VERIFIED]`) joins this window into an
                            // already-open window's tab group explicitly, regardless
                            // of that timing gap.
                            if let existing = NSApp.windows.first(where: {
                                $0 !== window && $0.tabbingIdentifier == Self.tabbingIdentifier
                            }) {
                                existing.addTabbedWindow(window, ordered: .above)
                            }
                        }
                    )
            },
            defaultValue: {
                // AM-803-5: consult the persisted tab registry synchronously
                // (UserDefaults-backed, no async work needed) BEFORE any
                // window exists, so the replay sequence is staged before the
                // very first `ProductWindowContentView.init` runs. This
                // closure always returns a throwaway sentinel — the actual
                // restore happens in `ProductWindowContentView`'s launch
                // replay `.task`, which converts this auto-presented window
                // in place into the plan's first real entry (Path A).
                let plan = WindowRegistryService.shared.loadLaunchPlan()
                if case .migrateLegacy(let snapshot) = plan {
                    WindowRegistryService.shared.confirmMigration(snapshot)
                }
                let actions = WindowReplayPlanner.plan(for: plan.snapshot)
                WindowRestoreDataStore.shared.prepareLaunchReplay(actions)
                return .newEmptySentinel()
            }
        )
        .defaultSize(width: 1200, height: 800)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.presented)
        .commands {
            // Replaces the default "New Window" (Cmd+N) with "New Tab" (Cmd+T) —
            // per ux-flows.md §7, this app's multi-window convention is tabs, not
            // separate windows, so Cmd+T is the expected shortcut.
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    openWindow(value: ProductWindowIdentity.newEmptySentinel())
                }
                .keyboardShortcut("t", modifiers: .command)
            }
            // Add "Refresh" to the Window menu arrangement group
            CommandGroup(after: .windowArrangement) {
                Button("Refresh") {
                    NotificationCenter.default.post(
                        name: .refreshRequested,
                        object: nil
                    )
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            // View menu: developer tools
            CommandMenu("View") {
                Button("View Log") {
                    AgileMaestroApp.openConsoleApp()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }
    }
}

// MARK: - ProductWindowContentView

/// Root content view for each window/tab opened by `AgileMaestroApp`'s
/// value-based `WindowGroup`.
///
/// Owns a single `WindowContext` instance as `@State`, so SwiftUI creates a fresh,
/// independent `WindowContext` — and therefore a fresh set of the five ViewModels —
/// every time the `WindowGroup` instantiates a new window (R2.1, established in
/// AM-802). Each ViewModel is injected into the environment individually via
/// `.environment(_:)` so that descendant views — starting with `MainWindowView` —
/// continue to read them with `@Environment(Type.self)`, exactly as before.
///
/// Branches on `identity`: a `.product` identity shows the existing app shell
/// (`MainWindowView`); an `.empty` sentinel identity shows the full SCR-EMPTY
/// experience (`EmptyNewTabView`, AM-803-2) — a "Choose a Product" CTA plus a
/// "New Product..." entry point into the existing `NewProductSheet`.
///
/// Selecting a product (existing or newly created) converts this window/tab
/// in place: mutating `identity` to `.product(id)` re-keys the `WindowGroup`
/// scene's dedup identity without opening a new window (Path A, confirmed by
/// the AM-803-1 spike — see that task's completion comment for the empirical
/// evidence). The "already open elsewhere" dedup branch is deferred to
/// AM-803-3 (`EmptyTabSelectionOutcome.focusExisting`).
struct ProductWindowContentView: View {

    /// The identity this window/tab was opened with. A binding so selecting a
    /// product from the empty-tab CTA can transition this tab into a product
    /// tab in place (Path A — see the "Open Design Question" in
    /// `planning/design/window-tabs-spec.md` and the A3 spike evidence in task
    /// AM-803-1's completion comment for which mechanism to use).
    @Binding var identity: ProductWindowIdentity

    /// This window's independent ViewModel graph. A new instance is created
    /// automatically whenever SwiftUI instantiates a new window for the
    /// `WindowGroup`.
    @State private var windowContext: WindowContext

    /// Controls the "New Product..." sheet reached from the empty-tab CTA
    /// (M-800-1 -> M-800-2). Local to this window/tab, mirroring
    /// `SessionViewModel.showingNewProductSheet`'s role for `MainWindowView`.
    @State private var showingNewProductSheet = false

    @Environment(\.openWindow) private var openWindow

    /// Consults `WindowRestoreDataStore` for THIS identity's staged entry
    /// (AM-803-5) at construction time, seeding `windowContext` with the
    /// restored view mode and `SessionViewModel` with the restored
    /// product/session — before `MainWindowView`'s `.task` ever runs. A
    /// window opened outside the replay (Cmd+T, "Open in New Tab") has no
    /// staged entry and gets today's defaults, unchanged.
    init(identity: Binding<ProductWindowIdentity>) {
        self._identity = identity
        let restoreEntry = WindowRestoreDataStore.shared.consumeRestoreEntry(for: identity.wrappedValue)
        var pendingRestore: PendingProductRestore?
        if case .product(let productID) = identity.wrappedValue, let restoreEntry {
            pendingRestore = PendingProductRestore(
                productID: productID,
                selectedSessionID: restoreEntry.selectedSessionID
            )
        }
        self._windowContext = State(
            wrappedValue: WindowContext(
                sessionViewModel: SessionViewModel(pendingRestore: pendingRestore),
                selectedViewMode: restoreEntry?.viewMode ?? .treeDetail
            )
        )
    }

    var body: some View {
        content
            .environment(windowContext.sessionViewModel)
            .environment(windowContext.treeViewModel)
            .environment(windowContext.kanbanViewModel)
            .environment(windowContext.detailViewModel)
            .environment(windowContext.teamViewModel)
            .environment(windowContext)
            .task {
                await runLaunchReplayIfNeeded()
            }
            .onAppear {
                WindowRegistrySaveCoordinator.shared.windowOpened(
                    identity: identity,
                    viewMode: windowContext.selectedViewMode,
                    selectedSessionID: windowContext.sessionViewModel.selectedSession?.id
                )
            }
            .onChange(of: identity) { oldValue, newValue in
                WindowRegistrySaveCoordinator.shared.windowIdentityChanged(
                    from: oldValue,
                    to: newValue,
                    viewMode: windowContext.selectedViewMode,
                    selectedSessionID: windowContext.sessionViewModel.selectedSession?.id
                )
            }
            .onChange(of: windowContext.selectedViewMode) { _, newValue in
                WindowRegistrySaveCoordinator.shared.windowUpdated(
                    identity: identity,
                    viewMode: newValue,
                    selectedSessionID: windowContext.sessionViewModel.selectedSession?.id
                )
            }
            .onChange(of: windowContext.sessionViewModel.selectedSession?.id) { _, newValue in
                WindowRegistrySaveCoordinator.shared.windowUpdated(
                    identity: identity,
                    viewMode: windowContext.selectedViewMode,
                    selectedSessionID: newValue
                )
            }
            .onDisappear {
                WindowRegistrySaveCoordinator.shared.windowClosed(identity: identity)
            }
    }

    /// Executes AM-803-5's launch-time tab replay exactly once per app run —
    /// `WindowRestoreDataStore.consumeLaunchReplayActions()` returns `nil` for
    /// every window after the first (including the ones this very method
    /// opens), so this is a cheap no-op the rest of the time.
    ///
    /// The first `.open` action converts THIS window in place (Path A) rather
    /// than opening a redundant extra window — this window is SwiftUI's
    /// auto-presented default for the `defaultValue` empty sentinel, so
    /// converting it avoids leaving a stray blank tab alongside the restored
    /// ones. Every subsequent `.open` action opens a new window via
    /// `openWindow(value:)`, each independently restoring its own entry via
    /// this type's `init`. The trailing `.focus` action (if present)
    /// re-invokes `openWindow(value:)` on the previously-active identity,
    /// which dedups to focusing that already-open window (SM-TAB-800-T4).
    private func runLaunchReplayIfNeeded() async {
        guard let actions = WindowRestoreDataStore.shared.consumeLaunchReplayActions() else { return }

        var hasConvertedThisWindow = false
        for action in actions {
            switch action {
            case .open(let entryPlan) where !hasConvertedThisWindow:
                hasConvertedThisWindow = true
                identity = entryPlan.entry.identity
                if case .product(let productID) = entryPlan.entry.identity {
                    await windowContext.sessionViewModel.restoreSpecificProduct(
                        productID: productID,
                        selectedSessionID: entryPlan.entry.selectedSessionID
                    )
                }
                windowContext.selectedViewMode = entryPlan.entry.viewMode ?? .treeDetail
            case .open(let entryPlan):
                openWindow(value: entryPlan.entry.identity)
            case .focus(let activeIdentity):
                openWindow(value: activeIdentity)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch identity {
        case .product:
            MainWindowView()
        case .empty:
            EmptyNewTabView(
                products: windowContext.sessionViewModel.products,
                staleProductIDs: windowContext.sessionViewModel.staleProductIDs,
                onSelectProduct: selectProduct,
                onNewProduct: { showingNewProductSheet = true }
            )
            .task {
                // Populates the CTA's product list only — no auto-selection,
                // so this tab stays on SCR-EMPTY until the user acts.
                await windowContext.sessionViewModel.loadProductsForSelection()
            }
            .onChange(of: windowContext.sessionViewModel.selectedProduct?.id) { _, newProductID in
                // Fires for both paths that can populate selectedProduct while
                // this tab is still empty: selectProduct(_:) below, and
                // NewProductSheet's create-success path (M-800-2, unchanged) —
                // a single place converts this tab once either succeeds.
                guard let newProductID else { return }
                identity = .product(newProductID)
            }
            .sheet(isPresented: $showingNewProductSheet) {
                NewProductSheet(sessionViewModel: windowContext.sessionViewModel)
            }
        }
    }

    /// Handles selecting an existing product from the empty-tab CTA
    /// (SM-EMPTY-800-T3). Loads the product into this tab's `SessionViewModel`
    /// when it is not already open elsewhere; the resulting identity flip is
    /// handled uniformly by the `onChange` above. When the product IS already
    /// open elsewhere, defers to the focus-existing dedup path
    /// (IS-TAB-FOCUS-800-2, task AM-803-3) instead — loading it into this
    /// (still-empty) tab too would leave two live contexts for the same
    /// product, since a direct `identity` mutation never goes through
    /// `openWindow(value:)`'s native dedup.
    private func selectProduct(_ product: Product) {
        let openProductIDs = WindowRegistrySaveCoordinator.shared.openProductIDs()
        switch ProductWindowIdentity.transitionForSelectingProduct(product, openProductIDs: openProductIDs) {
        case .convertInPlace:
            windowContext.sessionViewModel.selectProduct(product)
        case .focusExisting:
            // The product is already open in another tab/window — bring it
            // to front via openWindow(value:)'s native value-equality dedup
            // (research-window-tabbing.md Claim 1, `[VERIFIED]`) rather than
            // loading it into this tab, which would create a second live
            // WindowContext/SessionViewModel for the same product.
            openWindow(value: ProductWindowIdentity.product(product.id))
        }
    }
}
