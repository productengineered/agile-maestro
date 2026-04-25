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

    // MARK: - ViewModels

    // All five ViewModels are created at app level and injected via .environment()
    // so that any descendant view can access them with @Environment(Type.self).
    @State private var sessionViewModel = SessionViewModel()
    @State private var treeViewModel = TreeViewModel()
    @State private var kanbanViewModel = KanbanViewModel()
    @State private var detailViewModel = DetailViewModel()
    @State private var teamViewModel = TeamViewModel()

    // MARK: - Scene

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environment(sessionViewModel)
                .environment(treeViewModel)
                .environment(kanbanViewModel)
                .environment(detailViewModel)
                .environment(teamViewModel)
                // Minimum window size per FR-2.1 (800x600)
                .frame(minWidth: 800, minHeight: 600)
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
