import SwiftUI

// MARK: - DetailHeaderView

/// Shows breadcrumb trail (SM-BREADCRUMB-001) + item title + status pill + priority badge.
///
/// The breadcrumb trail walks the `parentId` chain through `DetailViewModel.breadcrumbSegments(for:)`.
/// Parent segments are tappable — tapping navigates the detail panel to that parent item and
/// updates the sidebar selection via `treeViewModel.revealTask(_:)` (IS-BREADCRUMB-001).
/// The current (last) segment is non-interactive.
///
/// Header layout (top to bottom):
/// 1. Breadcrumb trail (HStack of TypeIcon + title segments separated by chevrons)
/// 2. Item title (`.title2` semibold)
/// 3. Status + priority + review stage row (HStack) + display ID (right-aligned)
/// 4. Task JSON file path link (opens file in default app)
struct DetailHeaderView: View {

    @Environment(DetailViewModel.self) private var viewModel
    @Environment(TreeViewModel.self) private var treeViewModel
    @Environment(SessionViewModel.self) private var sessionViewModel

    let task: TaskItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            breadcrumbTrail
            titleText
            badgeRow
            metadataRow
            if let fileURL = taskFileURL {
                TaskFilePathLink(
                    fileName: fileURL.lastPathComponent,
                    fileURL: fileURL,
                    createdAt: task.metadata.createdAt ?? fileCreationDate
                )
            }
        }
    }

    // MARK: - File URL

    private var taskFileURL: URL? {
        guard let fileName = task.sourceFile,
              let sessionPath = sessionViewModel.selectedSession?.path else {
            return nil
        }
        return sessionPath.appendingPathComponent(fileName)
    }

    /// Falls back to the file's creation date on disk when metadata `created_at` is nil.
    private var fileCreationDate: Date? {
        guard let url = taskFileURL else { return nil }
        return (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
    }

    // MARK: - Title

    private var titleText: some View {
        Text(task.subject)
            .font(.title2)
            .fontWeight(.semibold)
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Badge Row

    private var badgeRow: some View {
        HStack(spacing: 8) {
            StatusPill(status: task.status)

            if let priority = task.priority {
                PriorityBadgeView(priority: priority)
            }

            if let stage = task.reviewStage {
                reviewStageBadge(stage: stage, result: task.reviewResult)
            }

            Spacer()

            if let displayId = task.displayId {
                Text(verbatim: displayId)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Metadata Row (SM-DP700-HEADER-004)

    /// Compact row below the badge row showing claimed_by agent and relative timestamps.
    /// Only renders when at least one field is non-nil.
    @ViewBuilder
    private var metadataRow: some View {
        let claimedBy = viewModel.resolvedClaimedBy(for: task)
        let updatedAt = viewModel.resolvedLastUpdatedAt(for: task)
        let createdAt = viewModel.resolvedCreatedAt(for: task)

        let hasAnything = (task.status == .inProgress && claimedBy != nil)
            || updatedAt != nil
            || createdAt != nil

        if hasAnything {
            HStack(spacing: 6) {
                if task.status == .inProgress, let agent = claimedBy {
                    Label {
                        Text(viewModel.formattedAgentName(agent))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } icon: {
                        Image(systemName: "person.circle")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .accessibilityLabel("Claimed by \(viewModel.formattedAgentName(agent))")

                    if updatedAt != nil || createdAt != nil {
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                            .accessibilityHidden(true)
                    }
                }

                if let date = updatedAt {
                    // Live-updating relative timestamp (style: .relative auto-refreshes)
                    HStack(spacing: 2) {
                        Text("Updated")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(date, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .accessibilityLabel("Last updated \(viewModel.absoluteDate(from: date))")

                    if createdAt != nil {
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                            .accessibilityHidden(true)
                    }
                }

                if let date = createdAt {
                    // Live-updating relative timestamp (style: .relative auto-refreshes)
                    HStack(spacing: 2) {
                        Text("Created")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(date, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .accessibilityLabel("Created \(viewModel.absoluteDate(from: date))")
                }

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Breadcrumb Trail (SM-BREADCRUMB-001)

    @ViewBuilder
    private var breadcrumbTrail: some View {
        let segments = viewModel.breadcrumbSegments(for: task)

        if !segments.isEmpty {
            HStack(spacing: 4) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    if index < segments.count - 1 {
                        // Tappable parent segment (IS-BREADCRUMB-001)
                        breadcrumbButton(segment: segment)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    } else {
                        // Current item — non-interactive
                        breadcrumbCurrent(segment: segment)
                    }
                }
            }
        }
    }

    // MARK: - Breadcrumb Segment Builders

    private func breadcrumbButton(segment: BreadcrumbSegment) -> some View {
        BreadcrumbButtonView(segment: segment) {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.navigate(to: segment.taskItem)
                treeViewModel.revealTask(segment.taskItem.id)
            }
        }
    }

    private func breadcrumbCurrent(segment: BreadcrumbSegment) -> some View {
        HStack(spacing: 4) {
            TypeIconView(type: segment.taskItem.type, size: 10)
                .accessibilityHidden(true)

            Text(segment.displayTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Review Stage Badge

    @ViewBuilder
    private func reviewStageBadge(stage: String, result: String?) -> some View {
        let isRejected = result == "rejected"
        let label = stage
            .replacingOccurrences(of: "-", with: " ")
            .capitalized

        Text(label)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(isRejected ? .red : .orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill((isRejected ? Color.red : Color.orange).opacity(0.12))
            )
            .accessibilityLabel("Review stage: \(label)\(isRejected ? ", rejected" : "")")
    }
}

// MARK: - TaskFilePathLink

/// A small tappable row showing the task JSON filename with a doc icon.
///
/// Clicking opens the file in the system's default application (typically a text editor).
/// The full file path is shown as a tooltip on hover.
private struct TaskFilePathLink: View {

    let fileName: String
    let fileURL: URL
    let createdAt: Date?

    @State private var isHovered = false

    private static let dateFormat: Date.FormatStyle = .dateTime
        .month(.twoDigits)
        .day(.twoDigits)
        .year(.twoDigits)
        .hour(.defaultDigits(amPM: .abbreviated))
        .minute(.twoDigits)

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.text")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Text(fileName)
                .font(.caption2)
                .foregroundStyle(isHovered ? .secondary : .tertiary)
                .underline(isHovered)
                .animation(.easeInOut(duration: 0.1), value: isHovered)

            if let date = createdAt {
                Text("- \(date.formatted(Self.dateFormat))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .onTapGesture {
            NSWorkspace.shared.open(fileURL)
        }
        .onHover { hovered in
            isHovered = hovered
            if hovered {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onDisappear {
            if isHovered {
                NSCursor.pop()
                isHovered = false
            }
        }
        .help(fileURL.path)
        .accessibilityLabel("Open task file \(fileName)")
        .accessibilityHint("Opens \(fileURL.path) in the default application")
    }
}

// MARK: - BreadcrumbButtonView

/// A tappable breadcrumb segment for a parent item (IS-BREADCRUMB-001).
///
/// Shows the type icon + truncated title. Underline appears on hover per spec.
/// Cursor changes to pointing hand on hover.
private struct BreadcrumbButtonView: View {

    let segment: BreadcrumbSegment
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                TypeIconView(type: segment.taskItem.type, size: 10)
                    .accessibilityHidden(true)

                Text(segment.displayTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .underline(isHovered)
                    .lineLimit(1)
                    .animation(.easeInOut(duration: 0.1), value: isHovered)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Navigate to \(segment.displayTitle)")
        .accessibilityHint("Shows \(segment.taskItem.type.rawValue) details")
        .onHover { hovered in
            isHovered = hovered
            if hovered {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onDisappear {
            if isHovered {
                NSCursor.pop()
                isHovered = false
            }
        }
    }
}

// MARK: - Preview

#Preview("DetailHeaderView — Epic with breadcrumb") {
    let json: [String: Any] = [
        "id": "epic-preview-1",
        "subject": "Epic: AM-300 Detail Panel",
        "description": "Build the task detail panel with tabs.",
        "status": "in_progress",
        "blocks": [],
        "blockedBy": [],
        "metadata": [
            "schema_version": "2.0",
            "type": "epic",
            "priority": "P1",
            "approval": "approved",
            "blocked": false,
            "review_stage": "code-review",
            "review_result": "awaiting",
            "labels": [],
            "comments": []
        ] as [String: Any]
    ]
    // swiftlint:disable:next force_try
    let task = try! JSONDecoder().decode(TaskItem.self, from: JSONSerialization.data(withJSONObject: json))
    let viewModel = DetailViewModel()
    viewModel.setTask(task, tasks: [task])
    let treeViewModel = TreeViewModel()
    let sessionViewModel = SessionViewModel()
    return DetailHeaderView(task: task)
        .environment(viewModel)
        .environment(treeViewModel)
        .environment(sessionViewModel)
        .padding(16)
        .frame(width: 600)
}
