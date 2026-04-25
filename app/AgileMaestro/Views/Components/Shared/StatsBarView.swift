import SwiftUI

// MARK: - StatsBarView

/// Compact horizontal row of StatPillViews immediately below the toolbar divider.
///
/// Content varies by task type:
/// - Epic:    STORIES (story count or "--"), POINTS (estimate.value), SPRINT, SIZE (complexity), RISK
/// - Story:   POINTS (story metadata), TASKS (story metadata task count), SPRINT
/// - Task/Bug/TechDebt: EST (hoursEstimated), ACTUAL (hoursActual), STEPS (checklist count),
///   CHECKS (localChecks count)
///
/// Only rendered when `hasVisibleStats(task:)` returns true (guaranteed non-empty bar).
/// Full-width, 10pt vertical padding, 16pt horizontal padding.
/// Horizontal scroll to accommodate all stat pills without truncation.
struct StatsBarView: View {

    let task: TaskItem

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                statsContent
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.04))
    }

    // MARK: - Type-Specific Content

    @ViewBuilder
    private var statsContent: some View {
        switch task.type {
        case .epic:
            epicStats

        case .story:
            storyStats

        case .task, .bug, .techdebt:
            taskStats
        }
    }

    // MARK: - Epic Stats (stories, tasks, points)

    @ViewBuilder
    private var epicStats: some View {
        // Story count from metadata
        StatPillView(
            icon: "doc.text",
            iconColor: .blue,
            label: "STORIES",
            value: epicStoryCountText
        )

        // Estimate points
        if let estimateValue = task.metadata.epic?.estimate?.value {
            StatPillView(
                icon: "chart.bar",
                iconColor: .purple,
                label: "POINTS",
                value: String(estimateValue)
            )
        }

        // Sprint number
        if let sprint = task.metadata.epic?.sprint {
            StatPillView(
                icon: "bolt",
                iconColor: .orange,
                label: "SPRINT",
                value: String(sprint)
            )
        }

        // Complexity (size-based color: S=green, M=blue, L=orange, XL=red)
        if let complexity = task.metadata.epic?.complexity {
            StatPillView(
                icon: "square.3.layers.3d",
                iconColor: complexityColor(for: complexity),
                label: "SIZE",
                value: complexity
            )
        }

        // Risk level (low=green, medium=orange, high=red)
        if let riskLevel = task.metadata.epic?.riskLevel {
            StatPillView(
                icon: "exclamationmark.triangle",
                iconColor: riskColor(for: riskLevel),
                label: "RISK",
                value: riskLevel.capitalized
            )
        }
    }

    // MARK: - Color Helpers

    private func complexityColor(for complexity: String) -> Color {
        switch complexity.uppercased() {
        case "S": return .green
        case "M": return .blue
        case "L": return .orange
        case "XL": return .red
        default: return .secondary
        }
    }

    private func riskColor(for risk: String) -> Color {
        switch risk.lowercased() {
        case "low": return .green
        case "medium": return .orange
        case "high": return .red
        default: return .secondary
        }
    }

    // MARK: - Story Stats (points, tasks, sprint)

    @ViewBuilder
    private var storyStats: some View {
        // Points from story metadata
        if let points = task.metadata.story?.points {
            StatPillView(
                icon: "chart.bar",
                iconColor: .purple,
                label: "POINTS",
                value: String(points)
            )
        }

        // Child task count from story metadata
        if let taskCount = task.metadata.story?.tasks?.count, taskCount > 0 {
            StatPillView(
                icon: "checkmark.circle",
                iconColor: .blue,
                label: "TASKS",
                value: String(taskCount)
            )
        }

        // Sprint number from story metadata
        if let sprint = task.metadata.story?.sprint {
            StatPillView(
                icon: "bolt",
                iconColor: .orange,
                label: "SPRINT",
                value: String(sprint)
            )
        }

    }

    // MARK: - Task / Bug / TechDebt Stats

    @ViewBuilder
    private var taskStats: some View {
        // Estimated hours
        if let hours = task.metadata.task?.hoursEstimated {
            StatPillView(
                icon: "clock",
                iconColor: .orange,
                label: "EST",
                value: "\(hours)h"
            )
        }

        // Actual hours
        if let actual = task.metadata.task?.hoursActual {
            StatPillView(
                icon: "clock.badge.checkmark",
                iconColor: .green,
                label: "ACTUAL",
                value: "\(actual)h"
            )
        }

        // Steps (checklist count)
        let stepsCount = task.metadata.task?.checklist?.count ?? 0
        if stepsCount > 0 {
            StatPillView(
                icon: "list.number",
                iconColor: .blue,
                label: "STEPS",
                value: String(stepsCount)
            )
        }

        // Checks (local_checks count)
        let checksCount = task.metadata.task?.localChecks?.count ?? 0
        if checksCount > 0 {
            StatPillView(
                icon: "checkmark.shield",
                iconColor: .teal,
                label: "CHECKS",
                value: String(checksCount)
            )
        }
    }

    // MARK: - Helpers

    /// Story count text for epics: reads from `storyCount` metadata or falls back to "--".
    private var epicStoryCountText: String {
        if let count = task.metadata.epic?.storyCount {
            return String(count)
        }
        return "--"
    }

    /// Returns true when the bar would render at least one visible stat pill for the given task.
    /// Use this guard in TaskDetailView to avoid rendering an empty stats bar.
    static func hasVisibleStats(task: TaskItem) -> Bool {
        switch task.type {
        case .epic:
            // Epics always show the STORIES pill (even if "--")
            return true
        case .story:
            return task.metadata.story?.points != nil
                || (task.metadata.story?.tasks?.count ?? 0) > 0
                || task.metadata.story?.sprint != nil
        case .task, .bug, .techdebt:
            let meta = task.metadata.task
            return meta?.hoursEstimated != nil
                || meta?.hoursActual != nil
                || (meta?.checklist?.count ?? 0) > 0
                || (meta?.localChecks?.count ?? 0) > 0
        }
    }
}

// MARK: - Preview

#Preview("StatsBarView — Epic") {
    // Using placeholder TaskItem via SessionViewModel preview helper
    VStack(spacing: 16) {
        Text("Epic Stats:")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .padding()
}
