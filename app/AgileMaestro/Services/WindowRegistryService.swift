import Foundation

// MARK: - WindowRegistryEntry

/// One persisted open window/tab: its `ProductWindowIdentity`, the content view
/// mode it was last showing, and (for product tabs) which session was selected.
///
/// `ProductWindowIdentity` (defined in `AgileMaestroApp.swift`) is already
/// `Codable`, so it round-trips through this entry unchanged — no separate
/// persistence-only identity type is needed.
struct WindowRegistryEntry: Codable, Equatable, Sendable {

    /// The window/tab's identity — a specific product, or an empty-tab sentinel.
    var identity: ProductWindowIdentity

    /// `ViewMode.rawValue` for the content area this tab was showing.
    ///
    /// Stored as a raw `String?` rather than embedding `ViewMode` directly so
    /// this file does not need to add `Codable` conformance to `ViewMode.swift`
    /// (out of this task's scope — see task AM-803-4's file list). `viewMode`
    /// below provides the typed accessor.
    var viewModeRawValue: String?

    /// Session selected within this product when the registry was last saved.
    /// `nil` for empty tabs and for product tabs with no session chosen yet.
    var selectedSessionID: UUID?

    init(identity: ProductWindowIdentity, viewMode: ViewMode? = nil, selectedSessionID: UUID? = nil) {
        self.identity = identity
        self.viewModeRawValue = viewMode?.rawValue
        self.selectedSessionID = selectedSessionID
    }

    /// Typed accessor over `viewModeRawValue`. Reads as `nil` if the stored raw
    /// value is missing or no longer a recognized `ViewMode` case (e.g. a
    /// future app version removed one) — callers should fall back to a
    /// sensible default (`.treeDetail`) rather than force-unwrapping.
    var viewMode: ViewMode? {
        get { viewModeRawValue.flatMap(ViewMode.init(rawValue:)) }
        set { viewModeRawValue = newValue?.rawValue }
    }
}

// MARK: - WindowRegistrySnapshot

/// The full persisted state of every open window/tab, plus which one is active.
///
/// This is the unit of persistence: `WindowRegistryService` encodes/decodes
/// exactly one `WindowRegistrySnapshot` to/from `UserDefaults` as a whole.
struct WindowRegistrySnapshot: Codable, Equatable, Sendable {

    /// Ordered open entries — order matches tab order left-to-right.
    var entries: [WindowRegistryEntry]

    /// Identity of the currently focused/active tab, if any.
    var activeIdentity: ProductWindowIdentity?
}

// MARK: - WindowRegistryLaunchPlan

/// The outcome of consulting `WindowRegistryService.loadLaunchPlan()` at app
/// launch — which of the three R2.5 launch policies applies, carrying the
/// snapshot the caller (AM-803-5, launch-time `openWindow` replay) should act on.
///
/// This type only decides *what data* the launch should restore; it does not
/// call `openWindow` itself — see `AM-803-5` for the scene-wiring consumer.
enum WindowRegistryLaunchPlan: Equatable, Sendable {

    /// A registry was already present on disk — restore these entries exactly
    /// (normal restart path).
    case restore(WindowRegistrySnapshot)

    /// No registry yet, but the legacy `SessionViewModel` `selectedProductID`
    /// key was found — migrate to a single-entry snapshot showing exactly that
    /// product, active (IS-800-8, no data loss, no empty window).
    case migrateLegacy(WindowRegistrySnapshot)

    /// Neither a registry nor the legacy key exists — fresh install. Opens one
    /// window on SCR-EMPTY (SM-TAB-800-T1).
    case freshInstall(WindowRegistrySnapshot)

    /// The snapshot to restore/open, regardless of which path produced it.
    var snapshot: WindowRegistrySnapshot {
        switch self {
        case .restore(let snapshot), .migrateLegacy(let snapshot), .freshInstall(let snapshot):
            return snapshot
        }
    }
}

// MARK: - WindowRegistryServiceProtocol

/// Persists the ordered set of open product windows/tabs, each entry's view
/// mode and session selection, and the active entry — with a safe,
/// non-destructive migration path from the legacy `selectedProductID` key
/// (R2.5, R3 epic risk mitigation).
///
/// Conforming types are the single source of truth AM-803-5's launch-time
/// `openWindow` replay reads from. This protocol only defines the persistence
/// contract — it does not open any windows itself.
protocol WindowRegistryServiceProtocol: Sendable {

    /// Determines which of the three R2.5 launch policies applies, purely by
    /// reading current `UserDefaults` state. Performs **no writes** — safe to
    /// call repeatedly (e.g. from a SwiftUI preview) without side effects.
    ///
    /// - Returns: `.restore` if a registry already exists; `.migrateLegacy` if
    ///   only the legacy `selectedProductID` key exists; `.freshInstall`
    ///   otherwise.
    func loadLaunchPlan() -> WindowRegistryLaunchPlan

    /// Persists `snapshot` as the new registry, overwriting any prior value.
    ///
    /// Pure write — does not touch the legacy key. Callers migrating from the
    /// legacy key should prefer `confirmMigration(_:)`, which additionally
    /// verifies the write before clearing the legacy key.
    func save(_ snapshot: WindowRegistrySnapshot)

    /// Completes a legacy-key migration: writes `snapshot` as the new
    /// registry, reads it back to verify the write succeeded, and only then
    /// removes the legacy `selectedProductID` key.
    ///
    /// This is the R3 risk mitigation in code: the legacy key is never deleted
    /// until the new registry write is confirmed, so a failed or partial write
    /// can never lose the user's last-open product.
    func confirmMigration(_ snapshot: WindowRegistrySnapshot)
}

// MARK: - WindowRegistryService

/// `UserDefaults`-backed implementation of `WindowRegistryServiceProtocol`.
///
/// Uses `JSONEncoder`/`JSONDecoder` over a single `Data` value stored under
/// `registryKey` — the same "encode the whole collection as one blob" pattern
/// `ProductService` uses for `products.json`, adapted to `UserDefaults` since
/// this data is small, app-shell-scoped state rather than user content.
final class WindowRegistryService: WindowRegistryServiceProtocol {

    // MARK: - Singleton

    static let shared = WindowRegistryService()

    // MARK: - Keys

    /// Namespaced with the app's reverse-DNS prefix, matching
    /// `AgileMaestroApp.tabbingIdentifier`'s convention, and versioned so a
    /// future incompatible schema change can migrate off `.v1` explicitly.
    private static let registryKey = "com.agilemaestro.windowRegistry.v1"

    /// `SessionViewModel.lastProductIDKey`'s literal value. Duplicated here
    /// (rather than imported) because `SessionViewModel` is not the new
    /// registry owner and should not be repurposed as one — see task
    /// AM-803-4's `ai_execution_hints`.
    private static let legacyProductIDKey = "selectedProductID"

    // MARK: - Private Properties

    // UserDefaults is not formally Sendable but is safe to use from multiple
    // contexts — matches the `nonisolated(unsafe)` convention already used for
    // FileManager in ProductService.
    nonisolated(unsafe) private let defaults: UserDefaults

    // MARK: - Init

    /// Creates a `WindowRegistryService` backed by `defaults`.
    ///
    /// - Parameter defaults: The `UserDefaults` suite to read/write. Tests
    ///   inject an isolated `UserDefaults(suiteName:)` instance so runs never
    ///   touch `.standard` or interfere with each other.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - WindowRegistryServiceProtocol

    func loadLaunchPlan() -> WindowRegistryLaunchPlan {
        if let snapshot = readRegistry() {
            return .restore(snapshot)
        }

        if let legacyProductID = readLegacyProductID() {
            let identity = ProductWindowIdentity.product(legacyProductID)
            let entry = WindowRegistryEntry(identity: identity)
            let snapshot = WindowRegistrySnapshot(entries: [entry], activeIdentity: identity)
            return .migrateLegacy(snapshot)
        }

        let sentinelEntry = WindowRegistryEntry(identity: .newEmptySentinel())
        let snapshot = WindowRegistrySnapshot(entries: [sentinelEntry], activeIdentity: sentinelEntry.identity)
        return .freshInstall(snapshot)
    }

    func save(_ snapshot: WindowRegistrySnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.registryKey)
    }

    func confirmMigration(_ snapshot: WindowRegistrySnapshot) {
        save(snapshot)

        // Only clear the legacy key once the write is verified by reading it
        // back — an encode/write failure (guarded inside `save`) leaves the
        // legacy key untouched, so the next launch simply re-migrates instead
        // of losing the user's last-open product (R3).
        guard readRegistry() == snapshot else { return }
        defaults.removeObject(forKey: Self.legacyProductIDKey)
    }

    // MARK: - Private Helpers

    private func readRegistry() -> WindowRegistrySnapshot? {
        guard let data = defaults.data(forKey: Self.registryKey) else { return nil }
        return try? JSONDecoder().decode(WindowRegistrySnapshot.self, from: data)
    }

    private func readLegacyProductID() -> UUID? {
        guard let rawID = defaults.string(forKey: Self.legacyProductIDKey) else { return nil }
        return UUID(uuidString: rawID)
    }
}
