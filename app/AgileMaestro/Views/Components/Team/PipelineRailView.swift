import SwiftUI

// MARK: - PipelineRailView
//
// Purpose: Horizontal rail of colored circles (pipeline nodes) connected by thin lines.
// Each node represents one workflow stage with stage name above and agent name below.
//
// IS-TV-RAIL-001 spec:
//   - Node diameter: 28pt (increased from 22pt for better color perception)
//   - Node fill: agent avatar color (matching AgentAvatarView.agentColorMap)
//   - Null-agent fill: .secondary.opacity(0.3), overlaid with person.fill icon
//   - Connector: 1pt, Color.primary.opacity(0.1) (~.quaternary), at node vertical center
//   - Stage name: 10pt semibold uppercase tracking 0.4, above node, 2-line max, fixed 28pt slot
//   - Agent name: caption2 .secondary, below node, fixed 20pt slot, short-form labels
//   - Min column width: 72pt
//
// SM-TEAM-006 stagger animation:
//   - First appearance only (hasAnimated gate)
//   - opacity 0→1, scale 0.8→1.0
//   - 30ms delay per node (using globalIndex = stageOffset + localIndex)
//   - reduceMotion: no animation, all nodes appear instantly

struct PipelineRailView: View {
    let stages: [WorkflowStageDefinition]
    let hasAnimated: Bool
    let reduceMotion: Bool
    /// Global offset for stagger delay continuity across pipeline sections.
    let stageOffset: Int

    // Column layout constants for consistent connector alignment.
    // Total column height = stageLabelHeight + innerSpacing + nodeSize + innerSpacing + agentLabelHeight
    // = 28 + 6 + 28 + 6 + 20 = 88pt. Node center is at 28 + 6 + 14 = 48pt from top.
    private let stageLabelHeight: CGFloat = 28
    private let agentLabelHeight: CGFloat = 20
    private let nodeSize: CGFloat = 28
    private let innerSpacing: CGFloat = 6
    private let columnMinWidth: CGFloat = 72

    /// Distance from the top of the stage column to the vertical center of the node.
    private var nodeTopOffset: CGFloat { stageLabelHeight + innerSpacing + nodeSize / 2 }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
                HStack(alignment: .top, spacing: 0) {
                    // MARK: Connector line (before every node except the first)
                    // Offset by nodeTopOffset to align the 1pt line with the node circle center.
                    if index > 0 {
                        Rectangle()
                            .fill(Color.primary.opacity(0.1))
                            .frame(height: 1)
                            .frame(minWidth: 12, maxWidth: 24)
                            .padding(.top, nodeTopOffset)
                    }

                    // MARK: Stage Column (name / circle / agent)
                    stageColumn(stage: stage, index: index)
                        .frame(minWidth: columnMinWidth)
                        // SM-TEAM-006: stagger reveal
                        .opacity(nodeOpacity(for: index))
                        .scaleEffect(nodeScale(for: index))
                        .animation(
                            nodeAnimation(for: index),
                            value: hasAnimated
                        )
                }
            }
        }
        // MARK: Accessibility — full rail as combined element
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(railAccessibilityLabel)
    }

    // MARK: - Stage Column

    private func stageColumn(stage: WorkflowStageDefinition, index: Int) -> some View {
        VStack(spacing: innerSpacing) {
            // Stage name — 10pt semibold uppercase with tracking.
            // Fixed 28pt height slot ensures all columns align even when labels wrap.
            // P0-1: lineLimit(2) + fixedSize prevents truncation; .primary improves dark-mode legibility (P1-3).
            Text(stage.name.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.primary)
                .tracking(0.4)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: columnMinWidth, height: stageLabelHeight, alignment: .bottom)
                .accessibilityHidden(true)

            // Node circle — 28pt for better color perception (P1-2).
            // Human/terminal nodes show a person.fill icon overlay (P2-1).
            nodeCircle(for: stage)
                .accessibilityHidden(true)

            // Agent name — caption2, secondary. Fixed 20pt height slot.
            // P0-2: uses agentShortLabel for readable, non-truncating short forms.
            Text(agentDisplayLabel(for: stage))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .frame(width: columnMinWidth, height: agentLabelHeight, alignment: .top)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Node Circle (P1-2, P2-1, P2-2, P2-3)

    private func nodeCircle(for stage: WorkflowStageDefinition) -> some View {
        let color = nodeColor(for: stage)
        let isHuman = stage.agentName == nil
        let agentLabel = agentDisplayLabel(for: stage)
        let tooltipLabel = isHuman
            ? "Stage: \(stage.name) · Human"
            : "Stage: \(stage.name) · Agent: \(agentLabel)"

        return ZStack {
            Circle()
                .fill(color)
                .frame(width: nodeSize, height: nodeSize)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: color.opacity(0.25), radius: 4, y: 2)

            // P2-1: Human/terminal nodes show a person.fill icon.
            if isHuman {
                Image(systemName: "person.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        // P2-2: Hover tooltip showing stage and agent.
        .help(tooltipLabel)
    }

    // MARK: - Node Color

    /// Maps agent name to its avatar color, mirroring AgentAvatarView.agentColorMap.
    private func nodeColor(for stage: WorkflowStageDefinition) -> Color {
        guard let agentName = stage.agentName else {
            return Color.secondary.opacity(0.3)
        }
        return agentAvatarColor(for: agentName)
    }

    // MARK: - Agent Avatar Color Map
    // Must stay in sync with AgentAvatarView.agentColorMap.
    // Ordered lookup: more-specific keys must precede broader ones.
    private static let agentColorEntries: [(String, Color)] = [
        ("macos-developer", .orange),
        ("staff-engineer", .blue),
        ("data-architect", .teal),
        ("build-engineer", .gray),
        ("documentation", .mint),
        ("coordinator", .indigo),
        ("discovery", .cyan),
        ("security", .red),
        ("planning", .indigo),
        ("designer", .pink),
        ("devops", .gray),
        ("human", Color(.systemGray)),
        ("test", .green),
        ("rca", .brown),
        ("qa", .green),
        ("pm", .purple)
    ]

    private func agentAvatarColor(for agentName: String) -> Color {
        let raw = agentName.lowercased()
        return Self.agentColorEntries.first { raw.contains($0.0) }?.1 ?? .gray
    }

    // MARK: - Agent Display Label

    private func agentDisplayLabel(for stage: WorkflowStageDefinition) -> String {
        guard let agentName = stage.agentName else {
            // Human/terminal stages — show "Human" for known decision points
            switch stage.kind {
            case .human, .terminal: return "Human"
            case .agent: return ""
            }
        }
        return agentShortLabel(agentName)
    }

    /// P0-2: Short-form label map — dictionary lookup avoids cyclomatic complexity violations.
    private static let agentShortLabels: [String: String] = [
        "macos-developer": "macOS Dev",
        "staff-engineer": "Staff Eng",
        "build-engineer": "Build Eng",
        "data-architect": "Data Arch",
        "security-audit": "Security",
        "security": "Security",
        "pm": "PM",
        "qa": "QA",
        "visual-qa": "Visual QA",
        "designer": "Designer",
        "planning": "Planning",
        "human": "Human",
        "coordinator": "Coordinator",
        "documentation": "Docs",
        "rca": "RCA"
    ]

    /// Converts "macos-developer-agent" → "macOS Dev", "qa-agent" → "QA", etc.
    private func agentShortLabel(_ name: String) -> String {
        let stripped = name.replacingOccurrences(of: "-agent", with: "")
        if let known = Self.agentShortLabels[stripped.lowercased()] { return known }
        return stripped.split(separator: "-").map { part in
            part.lowercased() == "macos" ? "macOS" : part.prefix(1).uppercased() + part.dropFirst().lowercased()
        }.joined(separator: " ")
    }

    // MARK: - Animation Helpers (SM-TEAM-006)

    private func nodeOpacity(for index: Int) -> Double {
        (hasAnimated || reduceMotion) ? 1.0 : 0.0
    }

    private func nodeScale(for index: Int) -> CGFloat {
        (hasAnimated || reduceMotion) ? 1.0 : 0.8
    }

    private func nodeAnimation(for index: Int) -> Animation? {
        guard !reduceMotion else { return nil }
        let globalIndex = stageOffset + index
        return .spring(response: 0.3, dampingFraction: 0.8)
            .delay(Double(globalIndex) * 0.03)
    }

    // MARK: - Accessibility Label

    private var railAccessibilityLabel: String {
        stages.map { stage in
            let agent = stage.agentName.map { agentShortLabel($0) } ?? "Human"
            return "\(stage.name) assigned to \(agent)"
        }.joined(separator: ", ")
    }
}

// MARK: - WorkflowPipeline Preview Data

extension WorkflowPipeline {
    /// All three pipelines for previews.
    static func previewAll() -> [WorkflowPipeline] {
        [previewEpic(), previewStory(), previewTask()]
    }

    /// Epic pipeline preview stages.
    static func previewEpic() -> WorkflowPipeline {
        WorkflowPipeline(
            id: "epic",
            label: "Epic",
            stages: [
                WorkflowStageDefinition(id: "backlog", name: "Backlog", kind: .human, agentName: nil),
                WorkflowStageDefinition(id: "approved", name: "Approved", kind: .human, agentName: nil),
                WorkflowStageDefinition(id: "design", name: "Design", kind: .agent, agentName: "designer-agent"),
                WorkflowStageDefinition(id: "dev", name: "Dev", kind: .agent, agentName: "macos-developer-agent"),
                WorkflowStageDefinition(
                    id: "code-review", name: "Code Review", kind: .agent, agentName: "staff-engineer-agent"),
                WorkflowStageDefinition(id: "qa", name: "QA", kind: .agent, agentName: "qa-agent"),
                WorkflowStageDefinition(
                    id: "security", name: "Security", kind: .agent, agentName: "security-audit-agent"),
                WorkflowStageDefinition(
                    id: "product-review", name: "Product Review", kind: .agent, agentName: "pm-agent"),
                WorkflowStageDefinition(id: "human-uat", name: "Human UAT", kind: .human, agentName: nil)
            ]
        )
    }

    /// Story pipeline preview stages.
    static func previewStory() -> WorkflowPipeline {
        WorkflowPipeline(
            id: "story",
            label: "Story",
            stages: [
                WorkflowStageDefinition(id: "pending", name: "Pending", kind: .human, agentName: nil),
                WorkflowStageDefinition(
                    id: "dev-story", name: "Dev", kind: .agent, agentName: "macos-developer-agent"),
                WorkflowStageDefinition(
                    id: "code-review-story", name: "Code Review", kind: .agent, agentName: "staff-engineer-agent"),
                WorkflowStageDefinition(id: "qa-story", name: "QA", kind: .agent, agentName: "qa-agent"),
                WorkflowStageDefinition(
                    id: "product-review-story", name: "Product Review", kind: .agent, agentName: "pm-agent"),
                WorkflowStageDefinition(id: "done-story", name: "Done", kind: .terminal, agentName: nil)
            ]
        )
    }

    /// Task pipeline preview stages.
    static func previewTask() -> WorkflowPipeline {
        WorkflowPipeline(
            id: "task",
            label: "Task",
            stages: [
                WorkflowStageDefinition(id: "pending-task", name: "Pending", kind: .human, agentName: nil),
                WorkflowStageDefinition(
                    id: "in-progress-task", name: "In Progress", kind: .agent, agentName: "macos-developer-agent"),
                WorkflowStageDefinition(id: "completed-task", name: "Completed", kind: .terminal, agentName: nil)
            ]
        )
    }
}

// MARK: - Previews

#Preview("Pipeline Rail — Epic") {
    let epicPipeline = WorkflowPipeline.previewEpic()
    return PipelineRailView(
        stages: epicPipeline.stages,
        hasAnimated: true,
        reduceMotion: false,
        stageOffset: 0
    )
    .padding(24)
    .frame(width: 800)
    .background(.ultraThinMaterial)
    .preferredColorScheme(.dark)
}

#Preview("Pipeline Rail — Story") {
    let storyPipeline = WorkflowPipeline.previewStory()
    return PipelineRailView(
        stages: storyPipeline.stages,
        hasAnimated: true,
        reduceMotion: false,
        stageOffset: 9
    )
    .padding(24)
    .frame(width: 600)
    .background(.ultraThinMaterial)
    .preferredColorScheme(.light)
}

#Preview("Pipeline Rail — Reduce Motion") {
    let epicPipeline = WorkflowPipeline.previewEpic()
    return PipelineRailView(
        stages: epicPipeline.stages,
        hasAnimated: false,
        reduceMotion: true,
        stageOffset: 0
    )
    .padding(24)
    .frame(width: 800)
    .background(.ultraThinMaterial)
}
