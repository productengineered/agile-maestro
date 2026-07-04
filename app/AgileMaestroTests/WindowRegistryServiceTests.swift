import XCTest
@testable import AgileMaestro

// MARK: - WindowRegistryServiceTests

/// Verifies `WindowRegistryService`'s three R2.5 launch policies — fresh
/// install, legacy `selectedProductID` migration, and normal registry-present
/// restore — plus the R3 "no destructive write until confirmed" migration
/// safety contract (task AM-803-4).
final class WindowRegistryServiceTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var sut: WindowRegistryService!

    override func setUp() {
        super.setUp()
        // Isolated suite per test — never touches `.standard` and never
        // leaks state between tests.
        suiteName = "com.agilemaestro.tests.windowRegistry.\(UUID().uuidString)"
        // swiftlint:disable:next force_unwrapping
        defaults = UserDefaults(suiteName: suiteName)!
        sut = WindowRegistryService(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        sut = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Fresh Install (SM-TAB-800-T1)

    /// Neither a registry nor the legacy key exists: one window opens on
    /// SCR-EMPTY, and that single entry is also the active one.
    func testFreshInstallOpensOneEmptySentinelTab() {
        let plan = sut.loadLaunchPlan()

        guard case .freshInstall(let snapshot) = plan else {
            return XCTFail("Expected .freshInstall, got \(plan)")
        }
        XCTAssertEqual(snapshot.entries.count, 1)
        XCTAssertEqual(snapshot.entries.first?.identity, snapshot.activeIdentity)
        guard case .empty = snapshot.entries.first?.identity else {
            return XCTFail("Fresh install entry must be an empty-tab sentinel, not a product")
        }
    }

    /// Fresh install must never touch the legacy key (there isn't one, but
    /// this guards against `loadLaunchPlan` accidentally writing one).
    func testFreshInstallDoesNotWriteLegacyKey() {
        _ = sut.loadLaunchPlan()

        XCTAssertNil(defaults.string(forKey: "selectedProductID"))
    }

    // MARK: - Legacy Migration (IS-800-8, R3)

    /// A legacy `selectedProductID` key with no registry yet migrates to a
    /// single-entry snapshot showing exactly that product, active — no data
    /// loss, no empty window.
    func testLegacyMigrationOpensExactlyThatOneProductAsActive() {
        let legacyID = UUID()
        defaults.set(legacyID.uuidString, forKey: "selectedProductID")

        let plan = sut.loadLaunchPlan()

        guard case .migrateLegacy(let snapshot) = plan else {
            return XCTFail("Expected .migrateLegacy, got \(plan)")
        }
        XCTAssertEqual(snapshot.entries.count, 1, "Migration must open exactly one product, no empty window")
        XCTAssertEqual(snapshot.entries.first?.identity, .product(legacyID))
        XCTAssertEqual(snapshot.activeIdentity, .product(legacyID))
    }

    /// `loadLaunchPlan()` is a pure read: discovering the legacy key must not
    /// delete it. Only `confirmMigration(_:)` (after a verified write) may.
    func testLoadLaunchPlanNeverDeletesLegacyKeyItself() {
        let legacyID = UUID()
        defaults.set(legacyID.uuidString, forKey: "selectedProductID")

        _ = sut.loadLaunchPlan()

        XCTAssertEqual(defaults.string(forKey: "selectedProductID"), legacyID.uuidString)
    }

    /// The R3 mitigation end-to-end: after `confirmMigration` persists and
    /// verifies the new registry, the legacy key is cleared and the registry
    /// now round-trips as the source of truth.
    func testConfirmMigrationWritesRegistryThenClearsLegacyKeyOnce() {
        let legacyID = UUID()
        defaults.set(legacyID.uuidString, forKey: "selectedProductID")
        guard case .migrateLegacy(let snapshot) = sut.loadLaunchPlan() else {
            return XCTFail("Precondition: expected .migrateLegacy")
        }

        sut.confirmMigration(snapshot)

        XCTAssertNil(defaults.string(forKey: "selectedProductID"), "Legacy key must be cleared after confirmed write")
        guard case .restore(let restored) = sut.loadLaunchPlan() else {
            return XCTFail("Expected registry to now be present and restorable")
        }
        XCTAssertEqual(restored, snapshot)
    }

    /// `confirmMigration` is safe to call more than once (e.g. a retried
    /// launch-sequencing step in AM-803-5): the second call finds the legacy
    /// key already gone and the registry already matching, and leaves both
    /// exactly as they were — no crash, no duplicate entries.
    func testConfirmMigrationIsIdempotentWhenCalledTwice() {
        let legacyID = UUID()
        defaults.set(legacyID.uuidString, forKey: "selectedProductID")
        guard case .migrateLegacy(let snapshot) = sut.loadLaunchPlan() else {
            return XCTFail("Precondition: expected .migrateLegacy")
        }

        sut.confirmMigration(snapshot)
        sut.confirmMigration(snapshot)

        XCTAssertNil(defaults.string(forKey: "selectedProductID"))
        guard case .restore(let restored) = sut.loadLaunchPlan() else {
            return XCTFail("Expected registry to remain restorable after a repeated confirm")
        }
        XCTAssertEqual(restored, snapshot)
    }

    // MARK: - Normal Restore Path (Registry Present)

    /// When a registry already exists, `loadLaunchPlan()` restores it
    /// verbatim — including each entry's view mode and session selection —
    /// rather than treating it as a fresh install or migration.
    func testRestoresMultipleEntriesWithPerEntryViewModeAndSession() {
        let productA = UUID()
        let productB = UUID()
        let sessionForB = UUID()
        let entryA = WindowRegistryEntry(identity: .product(productA), viewMode: .kanban, selectedSessionID: nil)
        let entryB = WindowRegistryEntry(
            identity: .product(productB),
            viewMode: .team,
            selectedSessionID: sessionForB
        )
        let snapshot = WindowRegistrySnapshot(entries: [entryA, entryB], activeIdentity: .product(productB))
        sut.save(snapshot)

        let plan = sut.loadLaunchPlan()

        guard case .restore(let restored) = plan else {
            return XCTFail("Expected .restore, got \(plan)")
        }
        XCTAssertEqual(restored.entries.count, 2)
        XCTAssertEqual(restored.entries[0].viewMode, .kanban)
        XCTAssertNil(restored.entries[0].selectedSessionID)
        XCTAssertEqual(restored.entries[1].viewMode, .team)
        XCTAssertEqual(restored.entries[1].selectedSessionID, sessionForB)
        XCTAssertEqual(restored.activeIdentity, .product(productB))
    }

    /// A registry taking priority over a stale legacy key: once migrated,
    /// the registry is authoritative even if the legacy key still exists
    /// (e.g. cleared on a later run than expected).
    func testRegistryPresentTakesPriorityOverLegacyKey() {
        defaults.set(UUID().uuidString, forKey: "selectedProductID")
        let entry = WindowRegistryEntry(identity: .newEmptySentinel())
        let snapshot = WindowRegistrySnapshot(entries: [entry], activeIdentity: entry.identity)
        sut.save(snapshot)

        let plan = sut.loadLaunchPlan()

        guard case .restore(let restored) = plan else {
            return XCTFail("Expected .restore when a registry already exists, got \(plan)")
        }
        XCTAssertEqual(restored, snapshot)
    }

    // MARK: - WindowRegistryEntry ViewMode Accessor

    /// `viewMode` reads back exactly what was written via the typed
    /// initializer — verifies the raw-value bridge round-trips correctly.
    func testEntryViewModeAccessorRoundTripsThroughRawValue() {
        var entry = WindowRegistryEntry(identity: .newEmptySentinel(), viewMode: .treeDetail)
        XCTAssertEqual(entry.viewMode, .treeDetail)

        entry.viewMode = .kanban
        XCTAssertEqual(entry.viewModeRawValue, "kanban")

        entry.viewMode = nil
        XCTAssertNil(entry.viewModeRawValue)
    }
}
