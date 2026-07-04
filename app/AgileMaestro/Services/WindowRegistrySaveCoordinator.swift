import Foundation

// MARK: - WindowRegistrySaveCoordinator

/// Tracks every currently open window/tab's identity, view mode, and selected
/// session, persisting a fresh `WindowRegistrySnapshot` via
/// `WindowRegistryService` any time a tab opens, closes, or its product/view
/// mode/session changes — the write half of AM-803-5 (the read half is
/// `WindowRegistryService.loadLaunchPlan()` plus the launch-time replay).
///
/// Each `ProductWindowContentView` reports its own lifecycle via
/// `windowOpened`/`windowUpdated`/`windowIdentityChanged`/`windowClosed` from
/// `.onAppear`/`.onChange`/`.onDisappear` — there is no other cross-window
/// channel today, so this coordinator is the one place that assembles the
/// multi-window snapshot.
///
/// **Active-window tracking is intentionally simple** (per this task's "keep
/// it simple and testable" scope): a window is marked active whenever it
/// reports itself opened or updated, a reasonable proxy that does NOT track
/// a user clicking between already-open native tabs without any SwiftUI
/// state change firing. Precise focus tracking would need an
/// `NSWindow.didBecomeKeyNotification` observer bridged through
/// `WindowAccessor` — a reasonable follow-up, out of scope here.
@MainActor
final class WindowRegistrySaveCoordinator {

    static let shared = WindowRegistrySaveCoordinator()

    private var order: [ProductWindowIdentity] = []
    private var entriesByIdentity: [ProductWindowIdentity: WindowRegistryEntry] = [:]
    private var activeIdentity: ProductWindowIdentity?
    private let registryService: WindowRegistryServiceProtocol

    init(registryService: WindowRegistryServiceProtocol = WindowRegistryService.shared) {
        self.registryService = registryService
    }

    /// A window newly appeared (or reappeared) — adds it to `order` if not
    /// already tracked, records its current state, and marks it active.
    func windowOpened(identity: ProductWindowIdentity, viewMode: ViewMode, selectedSessionID: UUID?) {
        if !order.contains(identity) {
            order.append(identity)
        }
        entriesByIdentity[identity] = WindowRegistryEntry(
            identity: identity,
            viewMode: viewMode,
            selectedSessionID: selectedSessionID
        )
        activeIdentity = identity
        persist()
    }

    /// An already-tracked window's view mode or session selection changed.
    func windowUpdated(identity: ProductWindowIdentity, viewMode: ViewMode, selectedSessionID: UUID?) {
        guard order.contains(identity) else { return }
        entriesByIdentity[identity] = WindowRegistryEntry(
            identity: identity,
            viewMode: viewMode,
            selectedSessionID: selectedSessionID
        )
        activeIdentity = identity
        persist()
    }

    /// A window converted its own identity in place (empty tab -> product,
    /// or the launch replay's first-entry conversion) — the dictionary key
    /// changes, so the old entry is removed and a new one added rather than
    /// updated in place.
    func windowIdentityChanged(
        from oldIdentity: ProductWindowIdentity,
        to newIdentity: ProductWindowIdentity,
        viewMode: ViewMode,
        selectedSessionID: UUID?
    ) {
        windowClosed(identity: oldIdentity)
        windowOpened(identity: newIdentity, viewMode: viewMode, selectedSessionID: selectedSessionID)
    }

    /// A window closed — removes it from tracking; if it was active, the
    /// most recently opened remaining window (if any) becomes active.
    func windowClosed(identity: ProductWindowIdentity) {
        order.removeAll { $0 == identity }
        entriesByIdentity.removeValue(forKey: identity)
        if activeIdentity == identity {
            activeIdentity = order.last
        }
        persist()
    }

    private func persist() {
        let snapshot = WindowRegistrySnapshot(
            entries: order.compactMap { entriesByIdentity[$0] },
            activeIdentity: activeIdentity
        )
        registryService.save(snapshot)
    }
}
