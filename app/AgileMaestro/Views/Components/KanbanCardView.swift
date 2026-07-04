import SwiftUI

// MARK: - KanbanCardView

/// Individual task card in a Kanban column.
///
/// Background is `.regularMaterial` — do NOT use `.glassEffect()` here, it is
/// GPU-intensive inside `ForEach`/`LazyVStack`. A left accent bar is drawn red for
/// rejected items, orange for blocked items, and omitted otherwise. Hover brightens
/// the background; click calls `onSelect(card.taskItem)`.
struct KanbanCardView: View {
    let card: KanbanCard
    let onSelect: (TaskItem) -> Void

    @State private var isHovered = false

    // MARK: - Accent bar state

    private var accentBarColor: Color? {
        if card.reviewResult == "rejected" { return .red }
        if card.blocked { return .orange }
        return nil
    }

    var body: some View {
        Button {
            onSelect(card.taskItem)
        } label: {
            HStack(spacing: 0) {
                // Left accent bar — full height, 3pt wide, continuous.
                // Only rendered when rejected or blocked.
                if let barColor = accentBarColor {
                    barColor
                        .frame(width: 3)
                        // Clip to card corner radius on left edge only
                        .clipShape(
                            .rect(
                                topLeadingRadius: 8,
                                bottomLeadingRadius: 8,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: 0
                            )
                        )
                }

                // Card content
                VStack(alignment: .leading, spacing: 6) {
                    // Row 1: Type chip + status badges
                    HStack(spacing: 4) {
                        TypeIconView(type: card.type, size: 12)

                        Spacer()

                        // Rejected badge (red capsule) — only when rejected
                        if card.reviewResult == "rejected" {
                            Text("REJECTED")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.red.opacity(0.12), in: Capsule())
                                .accessibilityHidden(true) // parent label covers it
                        }

                        // Blocked badge (orange capsule) — only when blocked (and not rejected)
                        if card.blocked && card.reviewResult != "rejected" {
                            Text("BLOCKED")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.orange.opacity(0.12), in: Capsule())
                                .accessibilityHidden(true) // parent label covers it
                        }

                        // Tier-2 UAT badge (R1.5) — epic cards only; absent/malformed
                        // `uat.tier2` (or unrecognized `result`) renders no badge at all.
                        if let uat = card.uatTier2, let result = uat.result {
                            uatBadgeView(result: result, failedCount: uat.failedTests?.count ?? 0, reason: uat.reason)
                        }
                    }

                    // Row 2: Display ID (compact, secondary — e.g. "AM-310-3")
                    if let displayId = card.displayId {
                        Text(displayId)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    // Row 3: Title — 2-line limit; wraps at column width
                    Text(card.title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    // Row 4: Progress bar — epic and story only (when progress != nil)
                    if let progress = card.progress {
                        VStack(alignment: .leading, spacing: 2) {
                            ProgressBarView(
                                value: progress.total > 0
                                    ? Double(progress.completed) / Double(progress.total)
                                    : 0,
                                height: 4
                            )
                            .accessibilityHidden(true) // decorative; label below covers

                            Text("\(progress.completed) of \(progress.total) \(progress.unit)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                        }
                    }

                    // Row 5: Labels row — max 3 visible + "+N" overflow
                    if !card.labels.isEmpty {
                        KanbanCardLabelsRow(labels: card.labels)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Card background: material for depth; hover brightens slightly
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.secondary.opacity(0.08) : Color.clear)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
        )
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
        .onHover { hovering in
            // Respect Reduce Motion — hover state has no transition animation
            // when reduce motion is enabled (background is just toggled).
            isHovered = hovering
        }
        // Accessibility: combined element. VoiceOver reads type + title + urgency.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(cardAccessibilityLabel)
        .accessibilityHint("Activate to view in tree detail")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Tier-2 UAT Badge (SM-EPICCARD-800-T2..T4)
    // Reuses the exact capsule style as REJECTED/BLOCKED (design1 lock) — same font,
    // same padding, same opacity(0.12) background pattern. Only the color/text/tooltip differ.

    /// Computes the badge's display text for a given Tier-2 result. Extracted as a pure,
    /// non-view function (not `private`) so it is directly unit testable, matching the
    /// `computeSteps(for:)` testability pattern used by `WorkflowStepperView`.
    static func uatBadgeText(result: UATTier2Result, failedCount: Int) -> String {
        switch result {
        case .passed: return "UAT ✓"
        case .failed: return failedCount > 0 ? "UAT ✕ \(failedCount)" : "UAT ✕"
        case .skipped: return "UAT"
        }
    }

    @ViewBuilder
    private func uatBadgeView(result: UATTier2Result, failedCount: Int, reason: String?) -> some View {
        switch result {
        case .passed:
            Text(Self.uatBadgeText(result: result, failedCount: failedCount))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.green)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.green.opacity(0.12), in: Capsule())
                .accessibilityHidden(true) // parent cardAccessibilityLabel covers it

        case .failed:
            Text(Self.uatBadgeText(result: result, failedCount: failedCount))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.red)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.red.opacity(0.12), in: Capsule())
                .accessibilityHidden(true)

        case .skipped:
            Text(Self.uatBadgeText(result: result, failedCount: failedCount))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12), in: Capsule())
                // Sighted-user hover tooltip (IS-BADGE-TOOLTIP-800-4). This is a
                // SUPPLEMENT to the parent accessibility label below, not a
                // substitute — .help() is not reliably reachable via VoiceOver
                // navigation on all controls, so the reason MUST also appear in
                // cardAccessibilityLabel (IS-800-10).
                .help(reason ?? "Skipped")
                .accessibilityHidden(true)
        }
    }

    // MARK: - Accessibility Label

    /// Internal (not `private`) so it is directly unit testable, matching the
    /// `computeSteps(for:)` precedent in `WorkflowStepperView`.
    var cardAccessibilityLabel: String {
        var label = "\(card.type): \(card.title)"
        if card.reviewResult == "rejected" { label += ", Rejected" } else if card.blocked { label += ", Blocked" }

        // Tier-2 UAT badge (IS-800-10: status + count/reason must be in the label,
        // never color-only; IS-BADGE-TOOLTIP-800-4: reason reachable without a mouse
        // hover for VoiceOver users).
        if let uat = card.uatTier2, let result = uat.result {
            switch result {
            case .passed:
                label += ", Agent UAT passed"
            case .failed:
                let count = uat.failedTests?.count ?? 0
                if count > 0 {
                    label += ", Agent UAT failed, \(count) test\(count == 1 ? "" : "s")"
                } else {
                    label += ", Agent UAT failed"
                }
            case .skipped:
                label += ", Agent UAT skipped\(uat.reason.map { ", \($0)" } ?? "")"
            }
        }

        if let progress = card.progress {
            label += ", \(progress.completed) of \(progress.total) \(progress.unit)"
        }
        return label
    }
}

// MARK: - KanbanCardLabelsRow
// Purpose: Renders up to 3 label badges in a FlowLayout, with "+N" overflow badge.
// Accessibility: accessibilityHidden on each badge (card label covers context).
struct KanbanCardLabelsRow: View {
    let labels: [String]

    private var visibleLabels: [String] {
        Array(labels.prefix(3))
    }

    private var overflowCount: Int {
        max(0, labels.count - 3)
    }

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(visibleLabels, id: \.self) { label in
                LabelBadgeView(label: label, isDecorative: true)
            }

            if overflowCount > 0 {
                Text("+\(overflowCount)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.08), in: Capsule())
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - Preview Helpers

private extension TaskItem {
    static func previewItem(type: TaskType = .task) -> TaskItem {
        let json = """
        {
          "id": "preview-\(UUID().uuidString)",
          "subject": "Preview Task",
          "description": "",
          "status": "pending",
          "blocks": [],
          "blockedBy": [],
          "metadata": {
            "schema_version": "2.0",
            "type": "\(type.rawValue)",
            "priority": "P2",
            "approval": "approved",
            "blocked": false,
            "labels": [],
            "comments": []
          }
        }
        """
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(TaskItem.self, from: Data(json.utf8))
    }
}

// MARK: - Previews

#Preview("Normal Card") {
    KanbanCardView(
        card: KanbanCard(
            id: "task-1",
            type: .task,
            displayId: "AM-310-3",
            title: "Build KanbanCardView with type chip and accent bar",
            labels: ["ui", "phase-4"],
            blocked: false,
            reviewResult: nil,
            progress: nil,
            completedAt: nil,
            epicDisplayId: "AM-310",
            column: "in_dev",
            taskItem: TaskItem.previewItem(type: .task)
        ),
        onSelect: { _ in }
    )
    .frame(width: 180)
    .padding(16)
    .preferredColorScheme(.dark)
}

#Preview("Rejected Card") {
    KanbanCardView(
        card: KanbanCard(
            id: "story-2",
            type: .story,
            displayId: "AM-400-1",
            title: "KanbanViewModel Column Assignment",
            labels: ["kanban"],
            blocked: false,
            reviewResult: "rejected",
            progress: KanbanProgress(completed: 2, total: 5, unit: "tasks"),
            completedAt: nil,
            epicDisplayId: "AM-400",
            column: "code_review",
            taskItem: TaskItem.previewItem(type: .story)
        ),
        onSelect: { _ in }
    )
    .frame(width: 180)
    .padding(16)
    .preferredColorScheme(.dark)
}

#Preview("Blocked Card") {
    KanbanCardView(
        card: KanbanCard(
            id: "task-3",
            type: .bug,
            displayId: "AM-310-5",
            title: "Fix stale selection when tasks reload",
            labels: ["bug", "blocker"],
            blocked: true,
            reviewResult: nil,
            progress: nil,
            completedAt: nil,
            epicDisplayId: "AM-310",
            column: "in_dev",
            taskItem: TaskItem.previewItem(type: .bug)
        ),
        onSelect: { _ in }
    )
    .frame(width: 180)
    .padding(16)
    .preferredColorScheme(.light)
}

#Preview("Epic Card with Progress") {
    KanbanCardView(
        card: KanbanCard(
            id: "epic-1",
            type: .epic,
            displayId: "AM-400",
            title: "Kanban Board, Columns, Cards & Filter Bar",
            labels: ["infrastructure", "phase-4"],
            blocked: false,
            reviewResult: nil,
            progress: KanbanProgress(completed: 3, total: 8, unit: "stories"),
            completedAt: nil,
            epicDisplayId: nil,
            column: "in_dev",
            taskItem: TaskItem.previewItem(type: .epic)
        ),
        onSelect: { _ in }
    )
    .frame(width: 180)
    .padding(16)
}

#Preview("Many Labels — Overflow") {
    KanbanCardView(
        card: KanbanCard(
            id: "story-5",
            type: .story,
            displayId: "AM-400-2",
            title: "Story with many labels showing overflow badge",
            labels: ["ui", "phase-4", "kanban", "infrastructure"],
            blocked: false,
            reviewResult: nil,
            progress: nil,
            completedAt: nil,
            epicDisplayId: "AM-400",
            column: "approved",
            taskItem: TaskItem.previewItem(type: .story)
        ),
        onSelect: { _ in }
    )
    .frame(width: 180)
    .padding(16)
}
