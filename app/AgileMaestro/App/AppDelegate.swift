import AppKit

// MARK: - AppDelegate

/// AppKit bridge entry point for native window tabbing.
///
/// No SwiftUI-native tabbing modifier exists on macOS 26 — merging windows into
/// native title-bar tabs requires reaching the underlying `NSWindow` directly
/// (research-window-tabbing.md Claim 3, `[VERIFIED]`). This delegate's only job is
/// to permit tabbing at the application level; the per-window `.preferred` mode
/// that actually forces windows to merge is set by `WindowAccessor`.
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Left `true` (the default) — .preferred tabbingMode on individual windows
        // is what actually forces the merge; this class-level flag just permits it.
        // `NSWindow.allowsAutomaticWindowTabbing` introduced macOS 10.12, not
        // deprecated (research-window-tabbing.md Claim 2, `[VERIFIED]`).
        NSWindow.allowsAutomaticWindowTabbing = true
    }
}
