import SwiftUI
import AppKit

// MARK: - AgileMaestroApp

@main
struct AgileMaestroApp: App {

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
        WindowGroup {
            AgileMaestroWindowContentView()
        }
        // Default window dimensions on first launch
        .defaultSize(width: 1200, height: 800)
        // Cmd+R refresh shortcut — active whenever the window is key
        .commands {
            // Remove the unused "New" item from the File menu
            CommandGroup(replacing: .newItem) { }
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

// MARK: - AgileMaestroWindowContentView

/// Root content view for each window opened by `AgileMaestroApp`'s `WindowGroup`.
///
/// Owns a single `WindowContext` instance as `@State`, so SwiftUI creates a fresh,
/// independent `WindowContext` — and therefore a fresh set of the five ViewModels —
/// every time the `WindowGroup` instantiates a new window. This is the ownership
/// change that gives each window its own product/session state (R2.1); previously
/// the five ViewModels lived on the `App` struct itself, a single instance shared
/// by every window.
///
/// Each ViewModel is injected into the environment individually via
/// `.environment(_:)` so that descendant views — starting with `MainWindowView` —
/// continue to read them with `@Environment(Type.self)`, exactly as before this
/// refactor.
struct AgileMaestroWindowContentView: View {

    /// This window's independent ViewModel graph. A new instance is created
    /// automatically whenever SwiftUI instantiates a new window for the
    /// `WindowGroup`.
    @State private var windowContext = WindowContext()

    var body: some View {
        MainWindowView()
            .environment(windowContext.sessionViewModel)
            .environment(windowContext.treeViewModel)
            .environment(windowContext.kanbanViewModel)
            .environment(windowContext.detailViewModel)
            .environment(windowContext.teamViewModel)
            // Minimum window size per FR-2.1 (800x600)
            .frame(minWidth: 800, minHeight: 600)
    }
}
