import Foundation
import OSLog

extension ClaudeTask {

    // MARK: - Topological Sort

    /// Sorts an array of `ClaudeTask` values so that each task appears after all
    /// tasks it depends on (i.e. tasks listed in its `blockedBy` array).
    ///
    /// Uses Kahn's BFS-based topological sort. Cycle detection is a natural
    /// byproduct of the algorithm: if any tasks remain unprocessed after the BFS
    /// terminates, a dependency cycle must exist among them. In that case the
    /// remaining tasks are appended in their original input order and an `os_log`
    /// warning is emitted so the anomaly is visible in Console without crashing.
    ///
    /// Missing references — `blockedBy` IDs that point to tasks not present in
    /// the input array — are silently ignored. They do not affect the sort of the
    /// tasks that are present.
    ///
    /// - Parameter tasks: The unordered array of tasks to sort.
    /// - Returns: A new array sorted in dependency order.
    static func sortedByDependencyOrder(_ tasks: [ClaudeTask]) -> [ClaudeTask] {
        guard tasks.count > 1 else { return tasks }

        // Detect duplicate IDs: keep the first occurrence for graph sorting,
        // append later duplicates at the end in their original order with a warning.
        var seenIDs: Set<String> = []
        var uniqueTasks: [ClaudeTask] = []
        var duplicateTasks: [ClaudeTask] = []
        for task in tasks {
            if seenIDs.contains(task.id) {
                duplicateTasks.append(task)
            } else {
                seenIDs.insert(task.id)
                uniqueTasks.append(task)
            }
        }
        if !duplicateTasks.isEmpty {
            let dupeIDs = duplicateTasks.map(\.id).joined(separator: ", ")
            Logger.app.warning(
                "Topological sort: duplicate task IDs detected (kept first, appended rest): [\(dupeIDs)]"
            )
        }

        let idToTask = Dictionary(uniqueTasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let inputOrder = Dictionary(uniqueTasks.enumerated().map { ($0.element.id, $0.offset) },
                                   uniquingKeysWith: { first, _ in first })
        let (inDegree, adjacency) = buildGraph(tasks: uniqueTasks, knownIDs: Set(idToTask.keys))

        var queue = inDegree
            .filter { $0.value == 0 }
            .keys
            .sorted { (inputOrder[$0] ?? 0) < (inputOrder[$1] ?? 0) }
        var mutableInDegree = inDegree
        var sorted: [ClaudeTask] = []
        sorted.reserveCapacity(tasks.count)

        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard let task = idToTask[current] else { continue }
            sorted.append(task)

            let dependents = (adjacency[current] ?? [])
                .sorted { (inputOrder[$0] ?? 0) < (inputOrder[$1] ?? 0) }
            for dependent in dependents {
                mutableInDegree[dependent, default: 1] -= 1
                if mutableInDegree[dependent] == 0 { queue.append(dependent) }
            }
        }

        let processedIDs = Set(sorted.map(\.id))
        let cycleRemainder = uniqueTasks.filter { !processedIDs.contains($0.id) }
        if !cycleRemainder.isEmpty {
            let cycleIDs = cycleRemainder.map(\.id).joined(separator: ", ")
            Logger.app.warning("Topological sort cycle detected among tasks: [\(cycleIDs)]")
            sorted.append(contentsOf: cycleRemainder)
        }

        // Append duplicate-ID tasks at the end in their original order.
        sorted.append(contentsOf: duplicateTasks)

        return sorted
    }

    // MARK: - Private Helpers

    /// Builds the in-degree map and adjacency list needed for Kahn's algorithm.
    ///
    /// - Parameters:
    ///   - tasks: The full task array to process.
    ///   - knownIDs: The set of IDs present in the array; dangling `blockedBy` references
    ///     outside this set are silently skipped.
    /// - Returns: A tuple of `(inDegree, adjacency)` where `inDegree[id]` is the number of
    ///   unresolved dependencies for task `id`, and `adjacency[id]` lists tasks that must
    ///   come after `id` in the sorted output.
    private static func buildGraph(
        tasks: [ClaudeTask],
        knownIDs: Set<String>
    ) -> (inDegree: [String: Int], adjacency: [String: [String]]) {
        var inDegree: [String: Int] = [:]
        var adjacency: [String: [String]] = [:]

        for task in tasks {
            if inDegree[task.id] == nil { inDegree[task.id] = 0 }
            if adjacency[task.id] == nil { adjacency[task.id] = [] }

            for dep in task.blockedBy where knownIDs.contains(dep) {
                inDegree[task.id, default: 0] += 1
                adjacency[dep, default: []].append(task.id)
            }
        }

        return (inDegree, adjacency)
    }
}
