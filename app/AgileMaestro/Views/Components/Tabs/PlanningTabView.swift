import SwiftUI

// MARK: - PlanningTabView

/// Epic-only tab. Execution plan + risks + DoD + out of scope.
///
/// Implements ERR-DETAIL-008: shows ContentUnavailableView when all planning
/// fields are absent. Stats row is always visible when any content is present.
struct PlanningTabView: View {
    let task: TaskItem

    private var hasContent: Bool {
        let hasExecutionPlan = !(task.metadata.epic?.executionPlan?.phases?.isEmpty ?? true)
        let hasRisks = !(task.metadata.epic?.risks?.isEmpty ?? true)
        let hasDod: Bool = {
            guard let dod = task.metadata.epic?.definitionOfDone else { return false }
            return !(dod.completionGates?.isEmpty ?? true) ||
                   (dod.purpose != nil) ||
                   (dod.qualityGatesSource != nil)
        }()
        let hasOutOfScope = !(task.metadata.epic?.outOfScope?.isEmpty ?? true)
        return hasExecutionPlan || hasRisks || hasDod || hasOutOfScope
    }

    var body: some View {
        if !hasContent {
            // ERR-DETAIL-008: empty state when all planning fields absent
            ContentUnavailableView(
                "No Planning Data",
                systemImage: "calendar",
                description: Text("No execution plan, risks, or scope information has been defined for this epic.")
            )
        } else {
            LazyVStack(alignment: .leading, spacing: 16) {
                // Stats row (always visible when content present)
                planningStatsRow

                // Execution plan card (conditional)
                if let plan = task.metadata.epic?.executionPlan,
                   let phases = plan.phases, !phases.isEmpty {
                    ExecutionPlanCard(phases: phases)
                }

                // Risks card (conditional)
                if let risks = task.metadata.epic?.risks, !risks.isEmpty {
                    RisksCard(risks: risks)
                }

                // Definition of done card (conditional)
                if let dod = task.metadata.epic?.definitionOfDone {
                    PlanningDodCard(dod: dod)
                }

                // Out of scope card (conditional)
                if let outOfScope = task.metadata.epic?.outOfScope, !outOfScope.isEmpty {
                    OutOfScopeCard(items: outOfScope)
                }
            }
        }
    }

    // MARK: - Stats Row

    private var planningStatsRow: some View {
        HStack(spacing: 8) {
            let storyCount = task.metadata.epic?.storyCount ?? 0
            StatPillView(
                icon: "doc.text",
                iconColor: .blue,
                label: "STORIES",
                value: "\(storyCount)"
            )

            if let estimate = task.metadata.epic?.estimate,
               let points = estimate.value {
                StatPillView(
                    icon: "chart.bar",
                    iconColor: .purple,
                    label: "POINTS",
                    value: "\(points)"
                )
            }

            Spacer()
        }
    }
}

// MARK: - ExecutionPlanCard

/// Numbered phases with vertical connector lines. Each phase shows:
/// phase number in accent-colored circle, intent/name, story ID chips, deliverables.
private struct ExecutionPlanCard: View {
    let phases: [ExecutionPhase]

    var body: some View {
        CardView(title: "Execution Plan", icon: "list.number", iconColor: .accentColor) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(phases.enumerated()), id: \.element.id) { index, phase in
                    ExecutionPhaseRow(
                        phase: phase,
                        phaseNumber: index + 1,
                        isLast: index == phases.count - 1
                    )
                }
            }
        }
    }
}

// MARK: - ExecutionPhaseRow

private struct ExecutionPhaseRow: View {
    let phase: ExecutionPhase
    let phaseNumber: Int
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Left column: number circle + vertical connector
            VStack(spacing: 0) {
                // Phase number circle (accent, filled)
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 28, height: 28)
                    Text("\(phaseNumber)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }

                // Vertical connector line (all but last)
                if !isLast {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.20))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                        .padding(.top, 4)
                }
            }
            .frame(width: 28)

            // Right column: phase content
            VStack(alignment: .leading, spacing: 8) {
                // Phase intent or name
                if let intent = phase.intent, !intent.isEmpty {
                    Text(intent)
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                } else if let phaseName = phase.phase, !phaseName.isEmpty {
                    Text(phaseName)
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }

                // Story ID chips (FlowLayout)
                if let stories = phase.stories, !stories.isEmpty {
                    FlowLayout(spacing: 4) {
                        ForEach(stories, id: \.self) { storyId in
                            Text(storyId)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.10), in: Capsule())
                        }
                    }
                }

                // Deliverables
                if let deliverables = phase.deliverables, !deliverables.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(deliverables, id: \.self) { deliverable in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .symbolRenderingMode(.monochrome)
                                Text(deliverable)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, isLast ? 0 : 16)
        }
    }
}

// MARK: - RisksCard

/// Risk register: each risk shows description + impact badge + probability badge + mitigation.
private struct RisksCard: View {
    let risks: [RiskItem]

    var body: some View {
        CardView(title: "Risks", icon: "exclamationmark.triangle", iconColor: .orange) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(risks) { risk in
                    RiskRow(risk: risk)
                    if risk.id != risks.last?.id {
                        Divider()
                    }
                }
            }
        }
    }
}

// MARK: - RiskRow

private struct RiskRow: View {
    let risk: RiskItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Description + impact/probability badges
            HStack(alignment: .top, spacing: 8) {
                Text(risk.description ?? "Unknown risk")
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if let impact = risk.impact {
                        ImpactBadgeView(level: impact)
                    }
                    if let probability = risk.probability {
                        Text("P: \(probability.capitalized)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.10), in: Capsule())
                    }
                }
            }

            // Mitigation
            if let mitigation = risk.mitigation, !mitigation.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "shield")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.green)
                        .symbolRenderingMode(.hierarchical)
                    Text(mitigation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - PlanningDodCard

/// Definition of Done for epic in planning tab. Shows purpose, numbered
/// completion gates, and the quality gates source reference.
private struct PlanningDodCard: View {
    let dod: DefinitionOfDone

    var body: some View {
        CardView(title: "Definition of Done", icon: "checkmark.seal", iconColor: .green) {
            VStack(alignment: .leading, spacing: 12) {
                if let purpose = dod.purpose, !purpose.isEmpty {
                    Text(purpose)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

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
                                    .foregroundStyle(.green)
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

// MARK: - OutOfScopeCard

private struct OutOfScopeCard: View {
    let items: [String]

    var body: some View {
        CardView(title: "Out of Scope", icon: "xmark.circle", iconColor: .red) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.red)
                            .symbolRenderingMode(.hierarchical)
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
}

// MARK: - Preview Helpers (preview-only, not for production use)

private enum PlanningPreviewFactory {

    /// Creates a TaskItem with epic metadata including execution plan, risks, DoD, and out-of-scope.
    static func makeEpic() -> TaskItem {
        let json: [String: Any] = [
            "id": "preview-epic-1",
            "subject": "Epic: Preview Planning Tab",
            "description": "Preview epic for PlanningTabView development.",
            "status": "in_progress",
            "blocks": [],
            "blockedBy": [],
            "metadata": epicMetadata()
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let item = try? JSONDecoder().decode(TaskItem.self, from: data) else {
            fatalError("PlanningTabView preview: failed to construct TaskItem fixture")
        }
        return item
    }

    private static func epicMetadata() -> [String: Any] {
        [
            "schema_version": "2.0",
            "type": "epic",
            "approval": "approved",
            "blocked": false,
            "story_count": 4,
            "estimate": ["primary_unit": "points", "value": 21] as [String: Any],
            "execution_plan": [
                "shape": "sequential",
                "phases": [
                    [
                        "phase": "Phase 1",
                        "intent": "Data layer and models",
                        "stories": ["AM-101", "AM-102"],
                        "deliverables": ["Core Data schema", "Model decoders"]
                    ] as [String: Any],
                    [
                        "phase": "Phase 2",
                        "intent": "Views and navigation",
                        "stories": ["AM-103", "AM-104"],
                        "deliverables": ["TreeView", "DetailPanel"]
                    ] as [String: Any]
                ]
            ] as [String: Any],
            "risks": [
                [
                    "id": "risk-1",
                    "description": "Complex JSON decoding may break on schema changes",
                    "probability": "medium",
                    "impact": "high",
                    "mitigation": "Use resilient decoding with fallback empty models"
                ] as [String: Any]
            ],
            "definition_of_done": [
                "purpose": "All features are shippable and tested",
                "completion_gates": ["Build passes", "Tests green", "Design review passed"],
                "quality_gates_source": "CLAUDE.md#quality-gates"
            ] as [String: Any],
            "out_of_scope": ["Multi-user sync", "Cloud backup"],
            "labels": [],
            "comments": []
        ]
    }

    /// Creates a minimal TaskItem with no planning data (triggers empty state).
    static func makeEmpty() -> TaskItem {
        let json: [String: Any] = [
            "id": "preview-empty-1",
            "subject": "Epic: Empty",
            "description": "",
            "status": "pending",
            "blocks": [],
            "blockedBy": [],
            "metadata": [
                "schema_version": "2.0",
                "type": "epic",
                "approval": "pending",
                "blocked": false,
                "labels": [],
                "comments": []
            ] as [String: Any]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let item = try? JSONDecoder().decode(TaskItem.self, from: data) else {
            fatalError("PlanningTabView preview: failed to construct empty TaskItem fixture")
        }
        return item
    }
}

// MARK: - Preview

#Preview("PlanningTabView — Full") {
    ScrollView {
        PlanningTabView(task: PlanningPreviewFactory.makeEpic())
            .padding(16)
    }
    .frame(width: 420, height: 700)
    .background(Color(.windowBackgroundColor))
}

#Preview("PlanningTabView — Empty") {
    ScrollView {
        PlanningTabView(task: PlanningPreviewFactory.makeEmpty())
            .padding(16)
    }
    .frame(width: 420, height: 300)
    .background(Color(.windowBackgroundColor))
}
