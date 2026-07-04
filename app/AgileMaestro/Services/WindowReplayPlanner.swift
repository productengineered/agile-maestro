import Foundation

// MARK: - WindowReplayEntryPlan

/// One entry's slot in the launch-time replay sequence, paired with whether
/// its directory is known to be stale at plan time.
struct WindowReplayEntryPlan: Equatable, Sendable {
    let entry: WindowRegistryEntry
    let isStale: Bool
}

// MARK: - WindowReplayAction

/// One step in the ordered launch-time tab-restore sequence (AM-803-5).
enum WindowReplayAction: Equatable, Sendable {
    /// Open (or, for the very first action, convert this window in place
    /// into) the given entry.
    case open(WindowReplayEntryPlan)
    /// Bring the given identity's window/tab frontmost. `openWindow(value:)`'s
    /// dedup focuses the existing window rather than creating a duplicate
    /// (research-window-tabbing.md Claim 1), so this is always the last
    /// action and always targets an identity already opened above.
    case focus(ProductWindowIdentity)
}

// MARK: - WindowReplayPlanner

/// Builds the ordered sequence of actions the launch-time replay executor
/// (`ProductWindowContentView`) performs, given a `WindowRegistrySnapshot`.
///
/// Pure and synchronous — no `FileManager`, `UserDefaults`, or SwiftUI
/// dependency — so ordering and stale-flagging logic is unit-testable
/// without a live `Product` list or filesystem access.
enum WindowReplayPlanner {

    /// - Parameters:
    ///   - snapshot: The persisted registry snapshot to replay.
    ///   - isDirectoryStale: Injected predicate deciding whether a given
    ///     entry's identity should be flagged stale in the plan. Defaults to
    ///     "never stale" — the actual IS-800-9 skip-sessions/skip-watcher
    ///     behavior is driven at runtime by `SessionViewModel.staleProductIDs`
    ///     (computed after `loadProducts()` fetches the live list), not by
    ///     this flag; the flag exists so this pure function's ordering AND
    ///     stale-flagging logic are independently testable.
    /// - Returns: Ordered actions — one `.open` per entry (in snapshot order),
    ///   followed by a trailing `.focus` for the active identity if the
    ///   snapshot has one and it is among the opened entries.
    static func plan(
        for snapshot: WindowRegistrySnapshot,
        isDirectoryStale: (ProductWindowIdentity) -> Bool = { _ in false }
    ) -> [WindowReplayAction] {
        var actions: [WindowReplayAction] = snapshot.entries.map { entry in
            .open(WindowReplayEntryPlan(entry: entry, isStale: isDirectoryStale(entry.identity)))
        }
        if let active = snapshot.activeIdentity,
           snapshot.entries.contains(where: { $0.identity == active }) {
            actions.append(.focus(active))
        }
        return actions
    }
}
