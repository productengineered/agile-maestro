import SwiftUI

// MARK: - TechDebtOverviewContent

/// TechDebt overview: workflow + classification badges + regression risk +
/// files affected + impact + business justification + shared completion/checklist/blocked cards.
///
/// Note: StatsBarView is rendered by TaskDetailView above the tab pills — not here.
///
/// Implements journey J-DP3 and state machine SM-DP700-OVERVIEW-002.
struct TechDebtOverviewContent: View {
    let task: TaskItem

    /// Color for the regression risk badge per SM-DP700-OVERVIEW-002.
    private func regressionRiskColor(_ risk: String) -> Color {
        switch risk.lowercased() {
        case "high":   return .red
        case "medium": return .orange
        default:       return .green  // "low" or unknown
        }
    }

    var body: some View {
        let taskMeta = task.metadata.task

        // Status & Workflow card (approval, blocked)
        StatusWorkflowCard(task: task)

        // Labels chip row
        if !task.labels.isEmpty {
            LabelsChipRow(labels: task.labels)
        }

        // Parent context (story_id)
        if let storyId = taskMeta?.storyId {
            CardView(title: "Parent Story", icon: "doc.text", iconColor: .blue) {
                Text(storyId)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.accentColor)
                    .textSelection(.enabled)
            }
        }

        // Debt Classification card: debtType + debtCategory badges
        let hasDebtType = taskMeta?.debtType != nil
        let hasDebtCategory = taskMeta?.debtCategory != nil
        if hasDebtType || hasDebtCategory {
            CardView(title: "Classification", icon: "square.3.layers.3d", iconColor: .purple) {
                FlowLayout(spacing: 6) {
                    if let debtType = taskMeta?.debtType {
                        WorkflowChip(label: debtType.capitalized, color: .purple)
                            .accessibilityLabel("Debt type: \(debtType)")
                    }
                    if let debtCategory = taskMeta?.debtCategory {
                        WorkflowChip(label: debtCategory.capitalized, color: .indigo)
                            .accessibilityLabel("Debt category: \(debtCategory)")
                    }
                }
            }
        }

        // Regression Risk badge: color-coded per risk level
        if let regressionRisk = taskMeta?.regressionRisk {
            let riskColor = regressionRiskColor(regressionRisk)
            CardView(title: "Regression Risk", icon: "exclamationmark.triangle", iconColor: riskColor) {
                WorkflowChip(label: regressionRisk.capitalized, color: riskColor)
                    .accessibilityLabel("Regression risk: \(regressionRisk)")
            }
        }

        // Files Affected card
        if let filesAffected = taskMeta?.filesAffected, !filesAffected.isEmpty {
            CardView(title: "Files Affected", icon: "doc.badge.gearshape", iconColor: .secondary) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(filesAffected, id: \.self) { file in
                        Text(file)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }

        // Impact If Deferred card
        if let impact = taskMeta?.impactIfDeferred, !impact.isEmpty {
            CardView(title: "Impact if Deferred", icon: "exclamationmark.circle", iconColor: .orange) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                    Text(impact)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Impact if deferred: \(impact)")
            }
        }

        // Business Justification card (optional)
        if let justification = taskMeta?.businessJustification, !justification.isEmpty {
            CardView(title: "Business Justification", icon: "briefcase", iconColor: .blue) {
                Text(justification)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        // Discovered By (agent name chip)
        if let agent = taskMeta?.discoveredBy {
            CardView(
                title: "Discovered By",
                icon: "person.circle",
                iconColor: .secondary
            ) {
                Text(agent)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
        }

        // AI execution hints
        if let hints = taskMeta?.aiExecutionHints, !hints.isEmpty {
            DisclosureGroup(
                content: {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(hints, id: \.self) { hint in
                            Text(hint)
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.top, 6)
                },
                label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.purple)
                        Text("AI Execution Hints")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                }
            )
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }

        // Completion Signal & Validation Hint (shared with TaskOverviewContent)
        let hasSignal = taskMeta?.completionSignal != nil
        let hasHint = taskMeta?.validationHint != nil
        if hasSignal || hasHint {
            CardView(title: "Completion Criteria", icon: "checkmark.seal", iconColor: .green) {
                VStack(alignment: .leading, spacing: 8) {
                    if let signal = taskMeta?.completionSignal {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Done when", systemImage: "flag.checkered")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                            Text(signal)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let hint = taskMeta?.validationHint {
                        if hasSignal { Divider() }
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Verify by", systemImage: "magnifyingglass")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                            Text(hint)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }

        // Checklist card (implementation steps)
        if let checklist = taskMeta?.checklist, !checklist.isEmpty {
            CardView(title: "Checklist", icon: "checklist", iconColor: .accentColor) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(checklist.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1).")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 20, alignment: .trailing)
                            Text(step)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }

        // Dependencies & Assignment side-by-side
        let assignee = task.assignee ?? taskMeta?.claimedBy
        let hasBlockedBy = !task.blockedBy.isEmpty
        let hasAssignee = assignee != nil

        if hasBlockedBy || hasAssignee {
            HStack(alignment: .top, spacing: 12) {
                if hasBlockedBy {
                    CardView(
                        title: "Blocked By",
                        icon: "exclamationmark.octagon",
                        iconColor: .orange
                    ) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(task.blockedBy, id: \.self) { dep in
                                Text("• \(dep)")
                                    .font(.callout)
                                    .foregroundStyle(.orange)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                if let resolvedAssignee = assignee {
                    CardView(
                        title: "Assigned To",
                        icon: "person.circle",
                        iconColor: .accentColor
                    ) {
                        HStack(spacing: 8) {
                            AgentAvatarView(author: resolvedAssignee, size: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(resolvedAssignee)
                                    .font(.callout)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.primary)
                                if let claimedAt = taskMeta?.claimedAt {
                                    Text(claimedAt, style: .relative)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }

        // Blocks card — downstream items this task unblocks (SM-DP700-BLOCKS-006)
        BlocksCard(task: task)
    }
}
