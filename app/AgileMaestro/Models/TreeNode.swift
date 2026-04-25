import Foundation
import Observation

/// A node in the hierarchical task tree.
///
/// `TreeNode` wraps a `TaskItem` and manages expand/collapse state for the
/// tree sidebar. It is an `@Observable` class so SwiftUI can track changes
/// to `isExpanded` and `children` without additional wrappers.
@Observable
final class TreeNode: Identifiable {
    let id: String
    let task: TaskItem
    var children: [TreeNode]
    var isExpanded: Bool

    init(task: TaskItem, children: [TreeNode] = []) {
        self.id = task.id
        self.task = task
        self.children = children
        self.isExpanded = false
    }

    // MARK: - Computed Properties

    var hasChildren: Bool {
        !children.isEmpty
    }

    /// Total number of descendant nodes (recursive).
    var descendantCount: Int {
        children.reduce(0) { $0 + 1 + $1.descendantCount }
    }
}
