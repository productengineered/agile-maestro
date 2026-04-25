import SwiftUI

// MARK: - TeamWorkflowView
//
// Purpose: Three pipeline rail sections (Epic, Story, Task) showing workflow stages.
// Each section is a PipelineRailView — horizontal row of colored nodes with connectors.
//
// Layout: ScrollView(.vertical) > VStack > ForEach pipelines > PipelineRailSection
// Stagger: first .onAppear, nodes appear left-to-right with 30ms delay per node.
// Data: WorkflowPipeline from AgentManifest.workflowPipelines
//
// IS-TV-RAIL-001: Node diameter 28pt. Connector 1pt .quaternary.
// SM-TEAM-006: Stagger is first-load only (hasAnimated flag). Does not replay on sidebar nav.
struct TeamWorkflowView: View {
    let pipelines: [WorkflowPipeline]

    @State private var hasAnimated: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if pipelines.isEmpty {
                emptyState
            } else {
                pipelineContent
            }
        }
    }

    // MARK: - Pipeline Content

    private var pipelineContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // MARK: Header
                HStack {
                    Text("WORKFLOW PIPELINES")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(1.5)

                    Spacer()

                    // P1-4: .secondary instead of .tertiary — visible in dark mode.
                    Text("\(pipelines.count) pipelines")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                // P1-4: Reduced from 20pt to 12pt — tighter header gap.
                .padding(.bottom, 12)
                .accessibilityHidden(true)

                // MARK: Pipeline Sections
                ForEach(Array(pipelines.enumerated()), id: \.element.id) { pipelineIndex, pipeline in
                    PipelineRailSection(
                        pipeline: pipeline,
                        pipelineIndex: pipelineIndex,
                        hasAnimated: hasAnimated,
                        reduceMotion: reduceMotion,
                        stageOffset: stageOffset(for: pipelineIndex)
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }

                // MARK: Agent Legend (P1-5)
                // Fills empty space below pipelines with a purposeful, readable legend.
                agentLegend
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                Spacer(minLength: 24)
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .onAppear {
            if !hasAnimated {
                if reduceMotion {
                    hasAnimated = true
                } else {
                    // Small delay ensures view is laid out before animation fires.
                    // Without it, SwiftUI may skip the transition entirely.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation {
                            hasAnimated = true
                        }
                    }
                }
            }
        }
    }

    // MARK: - Agent Legend (P1-5)

    /// Unique agents across all pipelines, preserving first-seen order.
    private var uniqueAgents: [(name: String, color: Color)] {
        var seen = Set<String>()
        return pipelines.flatMap { $0.stages }
            .compactMap { stage -> (name: String, color: Color)? in
                guard let agentName = stage.agentName else { return nil }
                let key = agentName.lowercased()
                guard !seen.contains(key) else { return nil }
                seen.insert(key)
                return (name: agentName, color: agentAvatarColor(for: agentName))
            }
    }

    private var agentLegend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AGENT LEGEND")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            FlowLayout(spacing: 12) {
                ForEach(uniqueAgents, id: \.name) { agent in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(agent.color)
                            .frame(width: 10, height: 10)
                        Text(agentShortLabel(agent.name))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(agentShortLabel(agent.name))
                }
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Agent Color + Short Label (mirrored from PipelineRailView for legend use)

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

    private func agentShortLabel(_ name: String) -> String {
        let stripped = name.replacingOccurrences(of: "-agent", with: "")
        if let known = Self.agentShortLabels[stripped.lowercased()] { return known }
        return stripped.split(separator: "-").map { part in
            part.lowercased() == "macos" ? "macOS" : part.prefix(1).uppercased() + part.dropFirst().lowercased()
        }.joined(separator: " ")
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Workflow Data", systemImage: "arrow.triangle.branch")
        } description: {
            Text("Workflow pipeline data is missing from the manifest. Try updating the team info.")
        }
    }

    // MARK: - Helpers

    /// Total stage count across all pipelines before the given index.
    /// Used to calculate a continuous global stagger offset (Epic nodes 0-8, Story nodes 9-14, Task 15-17).
    private func stageOffset(for pipelineIndex: Int) -> Int {
        pipelines.prefix(pipelineIndex).reduce(0) { $0 + $1.stages.count }
    }
}

// MARK: - PipelineRailSection

// Purpose: One pipeline section — type header + horizontally-scrollable rail of nodes.
// The rail scrolls horizontally if the window is too narrow to show all nodes.
// Node minimum column width: 72pt (IS-TV-RAIL-001 spec, updated for 28pt nodes).
private struct PipelineRailSection: View {
    let pipeline: WorkflowPipeline
    let pipelineIndex: Int
    let hasAnimated: Bool
    let reduceMotion: Bool
    let stageOffset: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: Pipeline Type Label
            // P1-6: "Story / Bug / TechDebt" shortened to avoid horizontal competition.
            HStack(spacing: 8) {
                Text(pipelineShortLabel)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Text("·")
                    .foregroundStyle(.tertiary)

                Text("\(pipeline.stages.count) stages")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 4)

            // MARK: Rail Container
            // Horizontally scrollable — wide pipelines scroll within their card.
            // showsIndicators: false — overflow implied by content density.
            ScrollView(.horizontal, showsIndicators: false) {
                PipelineRailView(
                    stages: pipeline.stages,
                    hasAnimated: hasAnimated,
                    reduceMotion: reduceMotion,
                    stageOffset: stageOffset
                )
                .padding(.vertical, 8)
            }
            .scrollEdgeEffectStyle(.soft, for: .leading)
            .scrollEdgeEffectStyle(.soft, for: .trailing)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
        // P1-1: Colored left border distinguishes Epic / Story / Task cards in dark mode.
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(pipelineAccentColor)
                .frame(width: 3)
                .padding(.vertical, 10)
                .padding(.leading, 1)
        }
        // P2-4: Subtle 1pt border — more legible than shadow in dark mode.
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        // MARK: Accessibility for full pipeline section
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pipelineAccessibilityLabel)
    }

    // MARK: - Helpers

    /// Color accent for the pipeline type border and dot.
    /// index 0 = Epic (indigo), 1 = Story (blue), 2 = Task (green).
    private var pipelineAccentColor: Color {
        switch pipelineIndex {
        case 0: return .indigo  // Epic: heaviest pipeline, most stages
        case 1: return .blue    // Story: standard work pipeline
        case 2: return .green   // Task: leaf-level completion
        default: return Color.secondary
        }
    }

    /// P1-6: Short label — "Story · Bug · TD" is too wide; use the pipeline's own label directly.
    /// The label field on WorkflowPipeline already carries the correct short form.
    private var pipelineShortLabel: String { pipeline.label }

    private var pipelineAccessibilityLabel: String {
        let stageDescriptions = pipeline.stages.map { stage in
            let agent = stage.agentName ?? "Human"
            return "\(stage.name) assigned to \(agent)"
        }.joined(separator: ", ")
        return "Workflow pipeline for \(pipeline.label): \(stageDescriptions)"
    }
}

// MARK: - Previews

#Preview("Workflow View — Loaded") {
    TeamWorkflowView(pipelines: WorkflowPipeline.previewAll())
        .frame(width: 900, height: 600)
        .preferredColorScheme(.dark)
}

#Preview("Workflow View — Empty") {
    TeamWorkflowView(pipelines: [])
        .frame(width: 900, height: 600)
        .preferredColorScheme(.light)
}
