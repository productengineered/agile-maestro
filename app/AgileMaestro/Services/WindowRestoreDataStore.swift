import Foundation

// MARK: - WindowRestoreDataStore

/// Launch-scoped, in-memory channel between `AgileMaestroApp`'s
/// `WindowGroup(defaultValue:)` (which computes the AM-803-5 replay plan
/// synchronously, before any window exists) and each `ProductWindowContentView`
/// (which consumes its own staged entry at `init`, and the first window to
/// ask consumes the full replay sequence to execute it).
///
/// Single restore owner in practice: `consumeLaunchReplayActions()` returns
/// the staged sequence exactly once per app run — every other window's call
/// (including the ones the replay itself opens) gets `nil` immediately.
@MainActor
final class WindowRestoreDataStore {

    static let shared = WindowRestoreDataStore()

    private var pendingRestoreByIdentity: [ProductWindowIdentity: WindowRegistryEntry] = [:]
    private var launchReplayActions: [WindowReplayAction]?

    private init() {}

    /// Stages the full replay sequence — called once, synchronously, from
    /// `WindowGroup`'s `defaultValue` closure. Every `.open` action's entry
    /// is indexed by identity for per-window `consumeRestoreEntry(for:)`
    /// lookups; the full ordered `actions` list is stored for the launch
    /// executor to consume once via `consumeLaunchReplayActions()`.
    func prepareLaunchReplay(_ actions: [WindowReplayAction]) {
        for action in actions {
            if case .open(let plan) = action {
                pendingRestoreByIdentity[plan.entry.identity] = plan.entry
            }
        }
        launchReplayActions = actions
    }

    /// Returns the full replay sequence exactly once; `nil` on every
    /// subsequent call for the remainder of the app run.
    func consumeLaunchReplayActions() -> [WindowReplayAction]? {
        defer { launchReplayActions = nil }
        return launchReplayActions
    }

    /// Pops (removes) and returns the staged entry for `identity`, if any. A
    /// window opened outside the replay (Cmd+T, "Open in New Tab") has no
    /// staged entry and gets `nil` — falls back to existing default behavior.
    func consumeRestoreEntry(for identity: ProductWindowIdentity) -> WindowRegistryEntry? {
        pendingRestoreByIdentity.removeValue(forKey: identity)
    }

    #if DEBUG
    /// Test-only reset. Production code never calls this — the store is
    /// naturally launch-scoped and each piece of staged data is consumed
    /// exactly once per app run.
    func resetForTesting() {
        pendingRestoreByIdentity.removeAll()
        launchReplayActions = nil
    }
    #endif
}
