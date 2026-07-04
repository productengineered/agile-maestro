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
                .newEmptySentinel()
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
/// (`MainWindowView`); an `.empty` sentinel identity shows a minimal SCR-EMPTY
/// placeholder. Wiring the specific product id into `WindowContext`'s
/// `SessionViewModel` selection (so a window opened for product X actually shows
/// product X's data, plus the full empty-tab product-picker CTA) is deferred to
/// AM-803-2 ("Add open-in-new-tab flow + empty new-tab CTA") — this task's scope
/// is the scene/tabbing plumbing only.
struct ProductWindowContentView: View {

    /// The identity this window/tab was opened with. A binding so a future task
    /// can transition an empty tab into a product tab in place (see the "Open
    /// Design Question" in `planning/design/window-tabs-spec.md` and the A3 spike
    /// evidence in task AM-803-1's completion comment for which mechanism to use).
    @Binding var identity: ProductWindowIdentity

    /// This window's independent ViewModel graph. A new instance is created
    /// automatically whenever SwiftUI instantiates a new window for the
    /// `WindowGroup`.
    @State private var windowContext = WindowContext()

    var body: some View {
        content
            .environment(windowContext.sessionViewModel)
            .environment(windowContext.treeViewModel)
            .environment(windowContext.kanbanViewModel)
            .environment(windowContext.detailViewModel)
            .environment(windowContext.teamViewModel)
            .environment(windowContext)
    }

    @ViewBuilder
    private var content: some View {
        switch identity {
        case .product:
            MainWindowView()
        case .empty:
            EmptyProductTabPlaceholderView()
        }
    }
}
