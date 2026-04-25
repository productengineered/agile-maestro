import SwiftUI

// MARK: - CriteriaTabView

/// Renders acceptance criteria, success metrics, and definition of done.
/// Available for epic and story types (not task, bug, techdebt).
///
/// SM-CRITERIA-001: Single-expand accordion — tapping one criterion collapses
/// the previously open one simultaneously via a shared `expandedCriterionId` state.
/// ERR-DETAIL-004: If all content absent → ContentUnavailableView.
struct CriteriaTabView: View {

    // MARK: - Properties

    let task: TaskItem

    // SM-CRITERIA-001: single-expand state — shared across all AcceptanceCriterionRow instances
    @State private var expandedCriterionId: String?

    // MARK: - Computed

    private var hasContent: Bool {
        switch task.type {
        case .epic:
            let hasTestCriteria = !(task.metadata.epic?.testCriteria?.isEmpty ?? true)
            let hasPrimaryMetrics = !(task.metadata.epic?.successMetrics?.primary?.isEmpty ?? true)
            let hasSecondaryMetrics = !(task.metadata.epic?.successMetrics?.secondary?.isEmpty ?? true)
            let hasAC = !(task.metadata.epic?.acceptanceCriteria?.isEmpty ?? true)
            return hasTestCriteria || hasPrimaryMetrics || hasSecondaryMetrics || hasAC
        case .story:
            let hasAC = !(task.metadata.story?.acceptanceCriteria?.isEmpty ?? true)
            let hasDoD = task.metadata.story?.definitionOfDone != nil
            return hasAC || hasDoD
        default:
            return false
        }
    }

    // MARK: - Body

    var body: some View {
        if !hasContent {
            // ERR-DETAIL-004: all criteria absent
            ContentUnavailableView(
                "No Criteria",
                systemImage: "checkmark.shield",
                description: Text("No acceptance criteria or success metrics have been defined for this item.")
            )
        } else {
            LazyVStack(alignment: .leading, spacing: 16) {
                switch task.type {
                case .epic:  epicCriteriaContent
                case .story: storyCriteriaContent
                default:     EmptyView()
                }
            }
        }
    }

    // MARK: - Epic Criteria Content

    @ViewBuilder
    private var epicCriteriaContent: some View {
        // Test Criteria card (newline-separated checklist format)
        if let testCriteria = task.metadata.epic?.testCriteria, !testCriteria.isEmpty {
            testCriteriaCard(testCriteria: testCriteria)
        }

        // Success Metrics — primary + secondary side-by-side
        let primaryMetrics   = task.metadata.epic?.successMetrics?.primary   ?? []
        let secondaryMetrics = task.metadata.epic?.successMetrics?.secondary ?? []

        if !primaryMetrics.isEmpty || !secondaryMetrics.isEmpty {
            successMetricsRow(primary: primaryMetrics, secondary: secondaryMetrics)
        }

        // Acceptance Criteria accordion (single-expand, SM-CRITERIA-001)
        if let criteria = task.metadata.epic?.acceptanceCriteria, !criteria.isEmpty {
            acceptanceCriteriaCard(criteria: criteria)
        }
    }

    // MARK: - Story Criteria Content

    @ViewBuilder
    private var storyCriteriaContent: some View {
        // Acceptance Criteria accordion
        if let criteria = task.metadata.story?.acceptanceCriteria, !criteria.isEmpty {
            acceptanceCriteriaCard(criteria: criteria)
        }

        // Definition of Done card
        if let dod = task.metadata.story?.definitionOfDone {
            DefinitionOfDoneCard(dod: dod)
        }
    }

    // MARK: - Component Builders

    private func testCriteriaCard(testCriteria: String) -> some View {
        let items = testCriteria
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return CardView(title: "Test Criteria", icon: "checkmark.circle", iconColor: .green) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.green)
                            .symbolRenderingMode(.hierarchical)
                        Text(item.hasPrefix("- ") ? String(item.dropFirst(2)) : item)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func successMetricsRow(primary: [String], secondary: [String]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if !primary.isEmpty {
                CardView(
                    title: "Primary Metrics",
                    icon: "chart.line.uptrend.xyaxis",
                    iconColor: .green
                ) {
                    metricsList(items: primary)
                }
                .frame(maxWidth: .infinity)
            }
            if !secondary.isEmpty {
                CardView(
                    title: "Secondary Metrics",
                    icon: "chart.bar",
                    iconColor: .secondary
                ) {
                    metricsList(items: secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func acceptanceCriteriaCard(criteria: [AcceptanceCriteriaItem]) -> some View {
        CardView(title: "Acceptance Criteria", icon: "list.bullet.clipboard", iconColor: .accentColor) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(criteria.enumerated()), id: \.element.id) { index, criterion in
                    if index > 0 {
                        Divider().padding(.vertical, 4)
                    }
                    AcceptanceCriterionRow(
                        criterion: criterion,
                        isExpanded: expandedCriterionId == criterion.id,
                        onToggle: {
                            // SM-CRITERIA-001: single-expand logic
                            withAnimation(.easeInOut(duration: 0.2)) {
                                expandedCriterionId = (expandedCriterionId == criterion.id)
                                    ? nil
                                    : criterion.id
                            }
                        }
                    )
                }
            }
        }
    }

    private func metricsList(items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 6) {
                    Circle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 5, height: 5)
                        .padding(.top, 6)
                    Text(item)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - AcceptanceCriterionRow

/// Single expandable row in the AC accordion (SM-CRITERIA-001).
///
/// Collapsed: chevron pointing right + criterion title (single line).
/// Expanded: chevron rotated 90° + title + Gherkin fields (Given, When, Then, Verify).
///
/// Does NOT own its own expand state — state is lifted to CriteriaTabView to enforce single-expand.
private struct AcceptanceCriterionRow: View {

    let criterion: AcceptanceCriteriaItem
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row — always visible
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.monochrome)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.2), value: isExpanded)
                        .frame(width: 14)

                    Text(criterion.title ?? "Criterion \(criterion.id)")
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            // Section 8 accessibility per UX Flows
            .accessibilityLabel(
                "\(criterion.title ?? "Criterion"), \(isExpanded ? "expanded" : "collapsed")"
            )
            .accessibilityHint(
                isExpanded ? "Tap to collapse acceptance criterion" : "Tap to expand acceptance criterion"
            )

            // Expanded: Gherkin scenario fields
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    gherkinField(label: "Given", value: criterion.given, color: .blue)
                    gherkinField(label: "When", value: criterion.when, color: .orange)
                    gherkinField(label: "Then", value: criterion.then, color: .green)
                    gherkinField(label: "Verify", value: criterion.verify, color: .purple)
                }
                .padding(.leading, 22)   // Indent below chevron (14pt frame + 8pt gap)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .scale(scale: 0, anchor: .top)))
            }
        }
    }

    // MARK: - Gherkin Field

    @ViewBuilder
    private func gherkinField(label: String, value: String?, color: Color) -> some View {
        if let value, !value.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(color)
                    .tracking(1.0)

                Text(value)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - DefinitionOfDoneCard

/// Card showing completion gates (numbered list) and generation hints (caption).
/// Used by story criteria content only.
private struct DefinitionOfDoneCard: View {

    let dod: DefinitionOfDone

    var body: some View {
        CardView(title: "Definition of Done", icon: "checkmark.seal", iconColor: .green) {
            VStack(alignment: .leading, spacing: 12) {

                // Purpose (optional intro text)
                if let purpose = dod.purpose, !purpose.isEmpty {
                    Text(purpose)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Completion gates — numbered list with accent index
                let gates = dod.completionGates ?? []
                if !gates.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("COMPLETION GATES")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .tracking(1.0)

                        ForEach(Array(gates.enumerated()), id: \.offset) { index, gate in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1).")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                                    .monospacedDigit()
                                    .frame(width: 20, alignment: .trailing)

                                Text(gate)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                // Generation hints — caption, tertiary, least prominent
                let hints = dod.generationHints ?? []
                if !hints.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("HINTS")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .tracking(1.0)

                        ForEach(hints, id: \.self) { hint in
                            Text(hint)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                // Quality gates source reference
                if let source = dod.qualityGatesSource, !source.isEmpty {
                    Text("Quality gates: \(source)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("CriteriaTabView — Component Cards") {
    // Full task-level previews available once TaskItem.previewEpic/Story helpers are added.
    // Preview shows individual sub-components in isolation.
    ScrollView {
        LazyVStack(alignment: .leading, spacing: 16) {
            // Test criteria card
            CardView(title: "Test Criteria", icon: "checkmark.circle", iconColor: .green) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.green)
                            .symbolRenderingMode(.hierarchical)
                        Text("All unit tests pass with ≥80% coverage")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.green)
                            .symbolRenderingMode(.hierarchical)
                        Text("No SwiftLint errors in new files")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Success metrics side-by-side
            HStack(alignment: .top, spacing: 12) {
                CardView(title: "Primary Metrics", icon: "chart.line.uptrend.xyaxis", iconColor: .green) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: 6) {
                            Circle().fill(Color.secondary.opacity(0.3)).frame(width: 5, height: 5).padding(.top, 6)
                            Text("Build success rate ≥ 99%").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                CardView(title: "Secondary Metrics", icon: "chart.bar", iconColor: .secondary) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: 6) {
                            Circle().fill(Color.secondary.opacity(0.3)).frame(width: 5, height: 5).padding(.top, 6)
                            Text("Agent cycle time < 2 min").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }

            // Definition of Done card
            DefinitionOfDoneCard(
                dod: DefinitionOfDone(
                    purpose: "All stories pass product review.",
                    completionGates: ["All stories closed", "No P0 bugs open"],
                    qualityGatesSource: "CLAUDE.md#quality-gates",
                    generationHints: ["Focus on e2e coverage"]
                )
            )
        }
        .padding(16)
    }
    .frame(width: 480, height: 700)
}
