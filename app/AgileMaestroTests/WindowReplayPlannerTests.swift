import XCTest
@testable import AgileMaestro

// MARK: - WindowReplayPlannerTests

/// Verifies `WindowReplayPlanner.plan(for:isDirectoryStale:)` — the pure,
/// synchronously-testable ordering + stale-flagging logic AM-803-5's launch
/// replay executor consumes (task AM-803-5).
final class WindowReplayPlannerTests: XCTestCase {

    // MARK: - N-Entry Ordering

    /// N entries produce N `.open` actions in the same order as the
    /// snapshot, followed by a trailing `.focus` for the active identity.
    func testPlanProducesOpenActionsInSnapshotOrderFollowedByFocus() {
        let idA = UUID()
        let idB = UUID()
        let idC = UUID()
        let entryA = WindowRegistryEntry(identity: .product(idA))
        let entryB = WindowRegistryEntry(identity: .product(idB))
        let entryC = WindowRegistryEntry(identity: .product(idC))
        let snapshot = WindowRegistrySnapshot(entries: [entryA, entryB, entryC], activeIdentity: .product(idB))

        let actions = WindowReplayPlanner.plan(for: snapshot)

        XCTAssertEqual(actions.count, 4, "3 entries -> 3 opens + 1 trailing focus")
        guard case .open(let plan0) = actions[0], case .open(let plan1) = actions[1],
              case .open(let plan2) = actions[2], case .focus(let focused) = actions[3] else {
            return XCTFail("Expected [.open, .open, .open, .focus], got \(actions)")
        }
        XCTAssertEqual(plan0.entry.identity, .product(idA))
        XCTAssertEqual(plan1.entry.identity, .product(idB))
        XCTAssertEqual(plan2.entry.identity, .product(idC))
        XCTAssertEqual(focused, .product(idB))
    }

    /// A single-entry snapshot (fresh install) still produces exactly one
    /// `.open` plus a trailing `.focus` for that same entry.
    func testPlanHandlesSingleEntrySnapshot() {
        let entry = WindowRegistryEntry(identity: .newEmptySentinel())
        let snapshot = WindowRegistrySnapshot(entries: [entry], activeIdentity: entry.identity)

        let actions = WindowReplayPlanner.plan(for: snapshot)

        XCTAssertEqual(actions.count, 2)
        guard case .open(let plan) = actions[0], case .focus(let focused) = actions[1] else {
            return XCTFail("Expected [.open, .focus], got \(actions)")
        }
        XCTAssertEqual(plan.entry.identity, entry.identity)
        XCTAssertEqual(focused, entry.identity)
    }

    // MARK: - Active-Focus Selection

    /// No trailing `.focus` action when the snapshot has no active identity.
    func testPlanOmitsFocusActionWhenNoActiveIdentity() {
        let entry = WindowRegistryEntry(identity: .product(UUID()))
        let snapshot = WindowRegistrySnapshot(entries: [entry], activeIdentity: nil)

        let actions = WindowReplayPlanner.plan(for: snapshot)

        XCTAssertEqual(actions.count, 1)
        guard case .open = actions[0] else {
            return XCTFail("Expected a single .open action")
        }
    }

    /// An `activeIdentity` that doesn't match any entry (corrupted/stale
    /// registry data) must not produce a dangling `.focus` action.
    func testPlanOmitsFocusActionWhenActiveIdentityIsNotAmongEntries() {
        let entry = WindowRegistryEntry(identity: .product(UUID()))
        let danglingActive = ProductWindowIdentity.product(UUID())
        let snapshot = WindowRegistrySnapshot(entries: [entry], activeIdentity: danglingActive)

        let actions = WindowReplayPlanner.plan(for: snapshot)

        XCTAssertEqual(actions.count, 1, "Dangling activeIdentity must not produce a focus action")
    }

    // MARK: - Stale-Directory Path

    /// An entry flagged stale by the injected predicate opens with
    /// `isStale == true`; sibling entries are unaffected (`isStale == false`).
    func testPlanFlagsOnlyTheStaleEntryLeavingSiblingsUnaffected() {
        let freshID = UUID()
        let staleID = UUID()
        let otherFreshID = UUID()
        let entryFresh = WindowRegistryEntry(identity: .product(freshID))
        let entryStale = WindowRegistryEntry(identity: .product(staleID))
        let entryOtherFresh = WindowRegistryEntry(identity: .product(otherFreshID))
        let snapshot = WindowRegistrySnapshot(
            entries: [entryFresh, entryStale, entryOtherFresh],
            activeIdentity: nil
        )

        let actions = WindowReplayPlanner.plan(for: snapshot) { identity in
            identity == .product(staleID)
        }

        let plans: [WindowReplayEntryPlan] = actions.compactMap {
            if case .open(let plan) = $0 { return plan }
            return nil
        }
        XCTAssertEqual(plans.count, 3)
        XCTAssertEqual(plans[0].isStale, false, "Fresh sibling before the stale entry must be unaffected")
        XCTAssertEqual(plans[1].isStale, true, "The stale entry itself must be flagged")
        XCTAssertEqual(plans[2].isStale, false, "Fresh sibling after the stale entry must be unaffected")
    }

    /// Default predicate (no staleness check injected) never flags any entry.
    func testPlanDefaultsToNoEntriesStaleWhenNoPredicateInjected() {
        let entry = WindowRegistryEntry(identity: .product(UUID()))
        let snapshot = WindowRegistrySnapshot(entries: [entry], activeIdentity: nil)

        let actions = WindowReplayPlanner.plan(for: snapshot)

        guard case .open(let plan) = actions[0] else {
            return XCTFail("Expected a single .open action")
        }
        XCTAssertFalse(plan.isStale)
    }

    // MARK: - Empty Snapshot

    /// An empty entries list (should not happen per WindowRegistryService's
    /// contract, but defensively) produces no actions at all.
    func testPlanHandlesEmptyEntriesList() {
        let snapshot = WindowRegistrySnapshot(entries: [], activeIdentity: nil)

        let actions = WindowReplayPlanner.plan(for: snapshot)

        XCTAssertTrue(actions.isEmpty)
    }
}
