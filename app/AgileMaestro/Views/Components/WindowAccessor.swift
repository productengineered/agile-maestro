import SwiftUI
import AppKit

// MARK: - WindowAccessor

/// Reaches the concrete `NSWindow` behind a SwiftUI scene to set tabbing
/// properties that have no SwiftUI-native equivalent
/// (research-window-tabbing.md Claim 3, `[VERIFIED]`).
///
/// Placed in `.background { }` of a window's root content view so it has zero
/// visual footprint. Reads `view.window` after the view has been added to a
/// window (dispatched async to the next run loop turn) — more reliable than
/// caching `NSApp.keyWindow`, which can be stale or wrong when multiple windows
/// are opening concurrently (e.g. during a future tab-restore replay).
struct WindowAccessor: NSViewRepresentable {

    /// Applied once to the window this view is embedded in, as soon as it's available.
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                configure(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // No-op — configuration happens once at window creation. Live updates
        // (e.g. tab title on product rename) are driven via `.navigationTitle`
        // on the content view, not through this accessor.
    }
}
