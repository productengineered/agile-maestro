import XCTest
@testable import AgileMaestro

// MARK: - ClaudeTaskTopologicalSortTests

/// Unit tests for `ClaudeTask.sortedByDependencyOrder(_:)`.
///
/// Each test builds lightweight in-memory `ClaudeTask` fixtures via JSON decoding
/// — no file I/O or networking required.
final class ClaudeTaskTopologicalSortTests: XCTestCase {

    // MARK: - Helpers

    /// Decodes a `ClaudeTask` from a minimal JSON literal.
    ///
    /// - Parameters:
    ///   - id: Task identifier string.
    ///   - subject: Human-readable title.
    ///   - blocks: IDs of tasks that *this* task blocks (i.e. dependents).
    ///   - blockedBy: IDs of tasks that must complete before this one can start.
    private func makeTask(
        id: String,
        subject: String = "",
        blocks: [String] = [],
        blockedBy: [String] = []
    ) throws -> ClaudeTask {
        let blocksJSON = blocks.map { "\"\($0)\"" }.joined(separator: ", ")
        let blockedByJSON = blockedBy.map { "\"\($0)\"" }.joined(separator: ", ")
        let json = """
        {
            "id": "\(id)",
            "subject": "\(subject)",
            "blocks": [\(blocksJSON)],
            "blockedBy": [\(blockedByJSON)]
        }
        """
        return try JSONDecoder().decode(ClaudeTask.self, from: Data(json.utf8))
    }

    // MARK: - Single Task

    func testSortedByDependencyOrder_singleTask_returnsSameTask() throws {
        let task = try makeTask(id: "1", subject: "Only task")

        let result = ClaudeTask.sortedByDependencyOrder([task])

        XCTAssertEqual(result.map(\.id), ["1"])
    }

    // MARK: - No Dependencies

    func testSortedByDependencyOrder_noDependencies_allTasksPresent() throws {
        let taskA = try makeTask(id: "A", subject: "Alpha")
        let taskB = try makeTask(id: "B", subject: "Beta")
        let taskC = try makeTask(id: "C", subject: "Gamma")

        let result = ClaudeTask.sortedByDependencyOrder([taskA, taskB, taskC])

        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result.map(\.id).contains("A"))
        XCTAssertTrue(result.map(\.id).contains("B"))
        XCTAssertTrue(result.map(\.id).contains("C"))
    }

    func testSortedByDependencyOrder_noDependencies_preservesInputOrder() throws {
        let taskA = try makeTask(id: "A")
        let taskB = try makeTask(id: "B")
        let taskC = try makeTask(id: "C")

        let result = ClaudeTask.sortedByDependencyOrder([taskA, taskB, taskC])

        XCTAssertEqual(result.map(\.id), ["A", "B", "C"])
    }

    // MARK: - Linear Chain

    /// A linear chain where each task blocks the next:
    ///   A → B → C → D → E   (A must finish first, E is last)
    func testSortedByDependencyOrder_linearChain_sortedDependenciesFirst() throws {
        // Build chain: A blocks B, B blocks C, etc.
        let taskA = try makeTask(id: "A", blocks: ["B"])
        let taskB = try makeTask(id: "B", blocks: ["C"], blockedBy: ["A"])
        let taskC = try makeTask(id: "C", blocks: ["D"], blockedBy: ["B"])
        let taskD = try makeTask(id: "D", blocks: ["E"], blockedBy: ["C"])
        let taskE = try makeTask(id: "E", blockedBy: ["D"])

        // Deliberately shuffle input to prove sort is non-trivial.
        let shuffled = [taskE, taskC, taskA, taskD, taskB]

        let result = ClaudeTask.sortedByDependencyOrder(shuffled)

        let ids = result.map(\.id)
        XCTAssertEqual(ids.count, 5)

        // A must precede B, B must precede C, etc.
        let posA = try XCTUnwrap(ids.firstIndex(of: "A"))
        let posB = try XCTUnwrap(ids.firstIndex(of: "B"))
        let posC = try XCTUnwrap(ids.firstIndex(of: "C"))
        let posD = try XCTUnwrap(ids.firstIndex(of: "D"))
        let posE = try XCTUnwrap(ids.firstIndex(of: "E"))

        XCTAssertLessThan(posA, posB, "A must precede B")
        XCTAssertLessThan(posB, posC, "B must precede C")
        XCTAssertLessThan(posC, posD, "C must precede D")
        XCTAssertLessThan(posD, posE, "D must precede E")
    }

    func testSortedByDependencyOrder_linearChain_rootAppearsFirst() throws {
        let taskA = try makeTask(id: "A", blocks: ["B"])
        let taskB = try makeTask(id: "B", blocks: ["C"], blockedBy: ["A"])
        let taskC = try makeTask(id: "C", blockedBy: ["B"])

        let result = ClaudeTask.sortedByDependencyOrder([taskB, taskC, taskA])

        XCTAssertEqual(result.first?.id, "A", "Root (no dependencies) should appear first")
        XCTAssertEqual(result.last?.id, "C", "Leaf (depends on all) should appear last")
    }

    // MARK: - Circular Reference

    /// Two tasks that mutually block each other.
    /// The sort must complete (no hang) and the cycle tasks must still appear in output.
    func testSortedByDependencyOrder_circularPair_noHangAndAllTasksReturned() throws {
        // A blocked by B, B blocked by A — direct 2-node cycle.
        let taskA = try makeTask(id: "A", blocks: ["B"], blockedBy: ["B"])
        let taskB = try makeTask(id: "B", blocks: ["A"], blockedBy: ["A"])

        let result = ClaudeTask.sortedByDependencyOrder([taskA, taskB])

        XCTAssertEqual(result.count, 2, "Both tasks must be returned despite cycle")
        XCTAssertTrue(result.map(\.id).contains("A"))
        XCTAssertTrue(result.map(\.id).contains("B"))
    }

    /// Larger cycle: A → B → C → A, with an independent task D that has no deps.
    /// D (independent) should be sorted ahead of the cyclic trio; all four tasks present.
    func testSortedByDependencyOrder_cycleWithIndependentTask_independentTaskBeforeCycle() throws {
        let taskA = try makeTask(id: "A", blocks: ["B"], blockedBy: ["C"])
        let taskB = try makeTask(id: "B", blocks: ["C"], blockedBy: ["A"])
        let taskC = try makeTask(id: "C", blocks: ["A"], blockedBy: ["B"])
        let taskD = try makeTask(id: "D")  // No dependencies — should sort first

        let result = ClaudeTask.sortedByDependencyOrder([taskC, taskA, taskD, taskB])

        let ids = result.map(\.id)
        XCTAssertEqual(ids.count, 4, "All four tasks must be returned")

        let posD = try XCTUnwrap(ids.firstIndex(of: "D"))
        let posA = try XCTUnwrap(ids.firstIndex(of: "A"))
        let posB = try XCTUnwrap(ids.firstIndex(of: "B"))
        let posC = try XCTUnwrap(ids.firstIndex(of: "C"))

        // D has no deps; it must appear before any cyclic task.
        XCTAssertLessThan(posD, posA, "Independent task D must precede cycle task A")
        XCTAssertLessThan(posD, posB, "Independent task D must precede cycle task B")
        XCTAssertLessThan(posD, posC, "Independent task D must precede cycle task C")
    }

    // MARK: - Missing References

    /// blockedBy references a task ID not in the input array. The dangling reference
    /// must be silently ignored; the task must still appear in the result.
    func testSortedByDependencyOrder_danglingBlockedByReference_taskStillSorted() throws {
        let taskA = try makeTask(id: "A", blockedBy: ["DOES_NOT_EXIST"])
        let taskB = try makeTask(id: "B")

        let result = ClaudeTask.sortedByDependencyOrder([taskA, taskB])

        XCTAssertEqual(result.count, 2, "Both tasks must appear despite dangling reference")
        XCTAssertTrue(result.map(\.id).contains("A"))
        XCTAssertTrue(result.map(\.id).contains("B"))
    }

    /// Mix of real and missing blockedBy IDs. Only the real dep should influence sort order.
    func testSortedByDependencyOrder_mixedRealAndMissingRefs_realDepOrderRespected() throws {
        // B is blocked by A (real) and GHOST (missing).
        let taskA = try makeTask(id: "A", blocks: ["B"])
        let taskB = try makeTask(id: "B", blockedBy: ["A", "GHOST"])

        let result = ClaudeTask.sortedByDependencyOrder([taskB, taskA])

        let ids = result.map(\.id)
        let posA = try XCTUnwrap(ids.firstIndex(of: "A"))
        let posB = try XCTUnwrap(ids.firstIndex(of: "B"))

        XCTAssertLessThan(posA, posB, "Real dependency A must precede B")
    }

    // MARK: - All Independent

    func testSortedByDependencyOrder_allIndependent_allTasksPresent() throws {
        let tasks = try (1...6).map { i in
            try makeTask(id: "\(i)", subject: "Task \(i)")
        }

        let result = ClaudeTask.sortedByDependencyOrder(tasks)

        XCTAssertEqual(result.count, 6, "All six independent tasks must appear")
        let resultIDs = Set(result.map(\.id))
        let inputIDs = Set(tasks.map(\.id))
        XCTAssertEqual(resultIDs, inputIDs)
    }

    // MARK: - Empty Input

    func testSortedByDependencyOrder_emptyArray_returnsEmpty() {
        let result = ClaudeTask.sortedByDependencyOrder([])
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Diamond Dependency

    /// Diamond: A → B, A → C, B → D, C → D.
    /// A must come first; D must come last; B and C anywhere in between.
    func testSortedByDependencyOrder_diamondDependency_topAndBottomOrdered() throws {
        let taskA = try makeTask(id: "A", blocks: ["B", "C"])
        let taskB = try makeTask(id: "B", blocks: ["D"], blockedBy: ["A"])
        let taskC = try makeTask(id: "C", blocks: ["D"], blockedBy: ["A"])
        let taskD = try makeTask(id: "D", blockedBy: ["B", "C"])

        let result = ClaudeTask.sortedByDependencyOrder([taskD, taskC, taskB, taskA])

        let ids = result.map(\.id)
        XCTAssertEqual(ids.count, 4)

        let posA = try XCTUnwrap(ids.firstIndex(of: "A"))
        let posB = try XCTUnwrap(ids.firstIndex(of: "B"))
        let posC = try XCTUnwrap(ids.firstIndex(of: "C"))
        let posD = try XCTUnwrap(ids.firstIndex(of: "D"))

        XCTAssertLessThan(posA, posB, "A must precede B")
        XCTAssertLessThan(posA, posC, "A must precede C")
        XCTAssertLessThan(posB, posD, "B must precede D")
        XCTAssertLessThan(posC, posD, "C must precede D")
    }
}
