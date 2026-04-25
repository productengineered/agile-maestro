import SwiftUI

// MARK: - AgentRowCard
// Purpose: Expandable agent card. Shows avatar, name, model, skills count, description excerpt.
// Tap anywhere on card to toggle expanded/collapsed state (IS-TV-CARD-001).
// Expanded: reveals full description (no lineLimit), tools list, skill chips, MCP servers, file path.
//
// Layout: VStack with collapsed header row + conditional expanded detail section.
// Material: .ultraThinMaterial in RoundedRectangle(cornerRadius: 8).
// Corner radius: 8pt (md) — small card, not a large panel.
//
// Accessibility: card is treated as a single button (.accessibilityAddTraits(.isButton)).
// Text selection enabled on description in expanded state (.textSelection(.enabled)).
//
// NOTE: The parent GroupedRosterView manages `expandedAgentId` state (SM-TEAM-003 accordion).
// This view is stateless re: expansion — it receives `isExpanded` as a Bool param.
struct AgentRowCard: View {
    let agent: AgentInfo
    let isExpanded: Bool
    let onTap: () -> Void

    @State private var isHovered: Bool = false

    // MARK: - Model Color Map
    // Opus = indigo, Sonnet = blue, Haiku = green, unknown = gray
    private var modelColor: Color {
        let lower = agent.model.lowercased()
        if lower.contains("opus") { return .indigo }
        if lower.contains("sonnet") { return .blue }
        if lower.contains("haiku") { return .green }
        return .gray
    }

    private var modelLabel: String {
        let lower = agent.model.lowercased()
        if lower.contains("opus") { return "Opus" }
        if lower.contains("sonnet") { return "Sonnet" }
        if lower.contains("haiku") { return "Haiku" }
        return agent.model.capitalized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: Collapsed Header (always visible)
            collapsedHeader

            // MARK: Expanded Detail (conditional)
            if isExpanded {
                expandedDetail
                    .transition(
                        .opacity.combined(with: .scale(scale: 0, anchor: .top))
                    )
            }
        }
        .padding(16) // md — card inner padding
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AnyShapeStyle(.ultraThinMaterial))
                .overlay(
                    // Hover highlight: 4% white tint overlay
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(isHovered ? 0.04 : 0))
                        .animation(.easeInOut(duration: 0.12), value: isHovered)
                )
        )
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture(perform: onTap)
        .onHover { hovered in
            isHovered = hovered
        }
        // MARK: Accessibility
        .accessibilityElement(children: .combine)
        .accessibilityLabel(cardAccessibilityLabel)
        .accessibilityHint(isExpanded ? "Tap to collapse" : "Tap to expand agent details")
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isExpanded ? "expanded" : "collapsed")
    }

    // MARK: - Collapsed Header

    private var collapsedHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            // MARK: Avatar (AgentAvatarView)
            // 28x28pt colored initials badge — existing shared component.
            // Color-coded by agent type via AgentAvatarView's internal color map.
            AgentAvatarView(author: agent.id, size: 28, isDecorative: true)
                .frame(width: 28, height: 28)

            // MARK: Agent Info Column
            VStack(alignment: .leading, spacing: 2) {
                // Row 1: Name + model dot + model label
                HStack(spacing: 6) {
                    Text(agent.displayLabel)
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    // Model dot: decorative, color paired with text label
                    Circle()
                        .fill(modelColor)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)

                    Text(modelLabel)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }

                // Row 2: Skills count + MCP badge (collapsed summary)
                HStack(spacing: 8) {
                    if !agent.skills.isEmpty {
                        Text("\(agent.skills.count) skills")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if let mcpServers = agent.mcpServers, !mcpServers.isEmpty {
                        // MCP badge — compact, secondary
                        Text("MCP: \(mcpServers.joined(separator: ", "))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 8)

            // MARK: Description Excerpt (collapsed — right of spacer)
            Text(agent.description)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 200, alignment: .trailing)

            // MARK: Chevron
            // Rotates 90° when expanded. Animates via withAnimation in parent.
            Image(systemName: "chevron.right")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .animation(.easeInOut(duration: 0.2), value: isExpanded)
                .frame(width: 16)
        }
    }

    // MARK: - Expanded Detail

    private var expandedDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .padding(.vertical, 4)

            // MARK: Full Description
            // No lineLimit — shows full text.
            // .textSelection(.enabled) per macOS convention.
            Text(agent.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            // MARK: Tools Section (only if agent.tools is non-empty)
            if let tools = agent.tools, !tools.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TOOLS")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.8)

                    // Tool chips in a wrapping HStack (FlowLayout)
                    FlowLayout(spacing: 6) {
                        ForEach(tools, id: \.self) { tool in
                            toolChip(tool)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // MARK: Skills Section
            if !agent.skills.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SKILLS")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.8)

                    FlowLayout(spacing: 6) {
                        ForEach(agent.skills, id: \.self) { skill in
                            skillChip(skill)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // MARK: MCP Servers Section (expanded detail)
            if let mcpServers = agent.mcpServers, !mcpServers.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MCP SERVERS")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.8)

                    FlowLayout(spacing: 6) {
                        ForEach(mcpServers, id: \.self) { server in
                            mcpChip(server)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // MARK: File Path (if present)
            if let file = agent.file {
                Text(file)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Chip Subviews

    private func toolChip(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.secondary.opacity(0.10))
            )
    }

    private func skillChip(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.accentColor.opacity(0.10))
            )
    }

    private func mcpChip(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.secondary.opacity(0.08))
            )
    }

    // MARK: - Accessibility Label

    private var cardAccessibilityLabel: String {
        let state = isExpanded ? "expanded" : "collapsed"
        return "\(agent.displayLabel), \(modelLabel) model, \(state)"
    }
}

// MARK: - AgentInfo Preview Extension

extension AgentInfo {
    static func previewMacosDev() -> AgentInfo {
        AgentInfo(
            id: "macos-developer-agent",
            name: "macOS Developer",
            model: "claude-sonnet-4-6",
            // swiftlint:disable:next line_length
            description: "Builds SwiftUI views, ViewModels, services, and Core Data models for the macOS app using MVVM architecture and async/await concurrency.",
            skills: ["SwiftUI", "Core Data", "async/await", "XCTest", "Alamofire"],
            displayName: "macOS Developer",
            initials: "DV",
            mcpServers: ["xcode", "peekaboo"],
            tools: ["Read", "Write", "Edit", "Bash", "Glob", "Grep"],
            file: ".claude/agents/macos-developer-agent.md"
        )
    }

    static func previewStaffEng() -> AgentInfo {
        AgentInfo(
            id: "staff-engineer-agent",
            name: "Staff Engineer",
            model: "claude-opus-4",
            // swiftlint:disable:next line_length
            description: "Reviews code for architecture, standards compliance, and security. Enforces patterns and blocks regressions.",
            skills: ["Architecture", "Code Review", "Swift", "SwiftUI"],
            displayName: "Staff Engineer",
            initials: "SE",
            mcpServers: nil,
            tools: ["Read", "Grep", "Bash"],
            file: ".claude/agents/staff-engineer-agent.md"
        )
    }

    static func previewPM() -> AgentInfo {
        AgentInfo(
            id: "pm-agent",
            name: "PM",
            model: "claude-haiku-4",
            description: "Conducts product review, verifies acceptance criteria, and approves stories for release.",
            skills: ["Product Review", "AC Verification"],
            displayName: "PM",
            initials: "PM",
            mcpServers: nil,
            tools: nil,
            file: ".claude/agents/pm-agent.md"
        )
    }
}

// MARK: - Previews

#Preview("Agent Card — Collapsed") {
    VStack(spacing: 8) {
        AgentRowCard(
            agent: AgentInfo.previewMacosDev(),
            isExpanded: false,
            onTap: {}
        )
        AgentRowCard(
            agent: AgentInfo.previewStaffEng(),
            isExpanded: false,
            onTap: {}
        )
    }
    .padding(16)
    .frame(width: 680)
    .preferredColorScheme(.dark)
}

#Preview("Agent Card — Expanded") {
    AgentRowCard(
        agent: AgentInfo.previewMacosDev(),
        isExpanded: true,
        onTap: {}
    )
    .padding(16)
    .frame(width: 680)
    .preferredColorScheme(.dark)
}

#Preview("Agent Card — No Tools") {
    AgentRowCard(
        agent: AgentInfo.previewPM(),
        isExpanded: true,
        onTap: {}
    )
    .padding(16)
    .frame(width: 680)
    .preferredColorScheme(.light)
}
