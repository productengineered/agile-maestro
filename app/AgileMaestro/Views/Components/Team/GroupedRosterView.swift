import SwiftUI

// MARK: - GroupedRosterView
// Purpose: Agent roster grouped by AgentRoleCategory with inline accordion expand/collapse.
// Occupies the detail column of TeamView's NavigationSplitView.
//
// Layout: VStack containing a search header and a ScrollView with LazyVStack sections.
// Search: .searchable modifier on the outer VStack activates Cmd+F.
// Grouping: agents sorted and grouped by AgentRoleCategory (.coreTeam, .specialists, .security)
//
// Stagger animation: on first .onAppear, cards cascade in with 40ms delay per card.
// Reduce motion: @Environment(\.accessibilityReduceMotion) — stagger skipped when true.
//
// Data: Receives [AgentInfo] from TeamView (which reads from AgentManifest).
// SM-TEAM-003: accordion — only one card expanded at a time.
struct GroupedRosterView: View {
    let agents: [AgentInfo]

    @State private var searchQuery: String = ""
    @State private var expandedAgentId: String?
    @State private var hasAnimated: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Computed

    private var groupedAgents: [(label: String, agents: [AgentInfo])] {
        let filtered = filteredAgents
        let groups: [(AgentRoleCategory, String)] = [
            (.coreTeam, "Core Team"),
            (.specialists, "Specialists"),
            (.security, "Security")
        ]
        return groups.compactMap { category, label in
            let inGroup = filtered.filter { $0.roleCategory == category }
            guard !inGroup.isEmpty else { return nil }
            return (label: label, agents: inGroup.sorted(by: AgentInfo.sortComparator))
        }
    }

    private var filteredAgents: [AgentInfo] {
        guard !searchQuery.isEmpty else { return agents }
        let query = searchQuery.lowercased()
        return agents.filter { agent in
            agent.displayLabel.lowercased().contains(query) ||
            agent.description.lowercased().contains(query) ||
            agent.skills.contains { $0.lowercased().contains(query) }
        }
    }

    private var allFilteredCards: [AgentInfo] {
        groupedAgents.flatMap { $0.agents }
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Content
            if agents.isEmpty {
                emptyManifestState
            } else if allFilteredCards.isEmpty && !searchQuery.isEmpty {
                emptySearchState
            } else {
                rosterContent
            }
        }
        .searchable(
            text: $searchQuery,
            placement: .toolbar,
            prompt: "Search agents\u{2026}"
        )
        .onChange(of: searchQuery) { _, _ in
            // Accordion collapses when search changes (SM-TEAM-003 + SM-TEAM-004)
            withAnimation(.easeInOut(duration: 0.2)) {
                expandedAgentId = nil
            }
        }
    }

    // MARK: - Roster Content

    private var rosterContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                // MARK: Header Row
                HStack {
                    Text("TEAM ROSTER")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(1.5)

                    Spacer()

                    Text("\(allFilteredCards.count) agents")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .accessibilityValue("\(allFilteredCards.count) agents shown")
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

                // MARK: Role Groups
                ForEach(groupedAgents, id: \.label) { group in
                    AgentRoleGroupSection(
                        label: group.label,
                        agents: group.agents,
                        expandedAgentId: $expandedAgentId,
                        hasAnimated: $hasAnimated,
                        reduceMotion: reduceMotion,
                        cardIndexOffset: cardIndexOffset(for: group.label)
                    )
                }

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 16)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .onAppear {
            if !hasAnimated {
                hasAnimated = true
            }
        }
        .accessibilityLabel("Team roster")
    }

    // MARK: - Empty States

    private var emptyManifestState: some View {
        ContentUnavailableView {
            Label("No Agents Found", systemImage: "person.3")
        } description: {
            // swiftlint:disable:next line_length
            Text("The manifest was generated but contains no agents. Check that your .claude/agents/ directory contains agent files.")
        }
    }

    private var emptySearchState: some View {
        ContentUnavailableView.search(text: searchQuery)
    }

    // MARK: - Helpers

    private func cardIndexOffset(for label: String) -> Int {
        var offset = 0
        for group in groupedAgents {
            if group.label == label { break }
            offset += group.agents.count
        }
        return offset
    }
}

// MARK: - AgentRoleGroupSection

// Purpose: One collapsible role group — header row + list of AgentRowCards.
// The group header is a compact uppercase label with agent count badge.
// No expand/collapse on the GROUP itself (always visible) — accordion is per-CARD.
private struct AgentRoleGroupSection: View {
    let label: String
    let agents: [AgentInfo]
    @Binding var expandedAgentId: String?
    @Binding var hasAnimated: Bool
    let reduceMotion: Bool
    let cardIndexOffset: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // MARK: Group Header
            HStack(spacing: 6) {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.8)

                Text("(\(agents.count))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()

                Spacer()
            }
            .padding(.top, 16)
            .padding(.bottom, 4)
            .accessibilityHidden(true) // Role is conveyed via card accessibility label

            // MARK: Agent Cards
            ForEach(Array(agents.enumerated()), id: \.element.id) { index, agent in
                AgentRowCard(
                    agent: agent,
                    isExpanded: expandedAgentId == agent.id
                ) {
                    // SM-TEAM-003: accordion — toggle this card, collapse others
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if expandedAgentId == agent.id {
                            expandedAgentId = nil
                        } else {
                            expandedAgentId = agent.id
                        }
                    }
                }
                // MARK: Stagger Animation (J-TV1)
                // First load: opacity 0→1, scale 0.97→1.0, 40ms delay per card
                // Reduce motion: all cards appear instantly (animation nil)
                .opacity(hasAnimated ? 1 : 0)
                .scaleEffect(hasAnimated ? 1 : 0.97)
                .animation(
                    reduceMotion ? nil :
                        .spring(response: 0.35, dampingFraction: 0.85)
                        .delay(Double(cardIndexOffset + index) * 0.04),
                    value: hasAnimated
                )
                .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - AgentInfo Preview Extension

extension AgentInfo {
    /// All preview agents across all role categories for GroupedRosterView previews.
    static func previewAll() -> [AgentInfo] {
        previewCoreTeam() + previewSpecialists() + previewSecurity()
    }

    // swiftlint:disable:next function_body_length
    private static func previewCoreTeam() -> [AgentInfo] {
        [
            AgentInfo(
                id: "macos-developer-agent",
                name: "macOS Developer",
                model: "claude-sonnet-4-6",
                description: "Builds SwiftUI views, ViewModels, services, and Core Data models for the macOS app.",
                skills: ["SwiftUI", "Core Data", "async/await", "XCTest", "Alamofire"],
                displayName: "macOS Developer",
                initials: "DV",
                mcpServers: ["xcode", "peekaboo"],
                tools: ["Read", "Write", "Edit", "Bash", "Glob", "Grep"],
                file: ".claude/agents/macos-developer-agent.md"
            ),
            AgentInfo(
                id: "staff-engineer-agent",
                name: "Staff Engineer",
                model: "claude-opus-4",
                description: "Reviews code for architecture, standards compliance, and security.",
                skills: ["Architecture", "Code Review", "Swift", "SwiftUI"],
                displayName: "Staff Engineer",
                initials: "SE",
                mcpServers: nil,
                tools: ["Read", "Grep", "Bash"],
                file: ".claude/agents/staff-engineer-agent.md"
            ),
            AgentInfo(
                id: "qa-agent",
                name: "QA",
                model: "claude-sonnet-4-6",
                description: "Runs targeted tests, verifies acceptance criteria, and blocks regressions.",
                skills: ["XCTest", "UI Testing", "Test Plans"],
                displayName: "QA",
                initials: "QA",
                mcpServers: ["xcode"],
                tools: ["Bash"],
                file: ".claude/agents/qa-agent.md"
            ),
            AgentInfo(
                id: "pm-agent",
                name: "PM",
                model: "claude-haiku-4",
                description: "Conducts product review and verifies acceptance criteria.",
                skills: ["Product Review", "AC Verification"],
                displayName: "PM",
                initials: "PM",
                mcpServers: nil,
                tools: nil,
                file: ".claude/agents/pm-agent.md"
            ),
            AgentInfo(
                id: "build-engineer-agent",
                name: "Build Engineer",
                model: "claude-haiku-4",
                description: "Runs SwiftLint, xcodebuild, commits work, creates PRs, and archives releases.",
                skills: ["SwiftLint", "xcodebuild", "git", "CI"],
                displayName: "Build Engineer",
                initials: "BE",
                mcpServers: ["xcode"],
                tools: ["Bash"],
                file: ".claude/agents/build-engineer-agent.md"
            )
        ]
    }

    private static func previewSpecialists() -> [AgentInfo] {
        [
            AgentInfo(
                id: "planning-agent",
                name: "Planning",
                model: "claude-opus-4",
                description: "Breaks epics into stories and tasks. Writes acceptance criteria and execution hints.",
                skills: ["Planning", "Task Breakdown", "EARS"],
                displayName: "Planning",
                initials: "PL",
                mcpServers: nil,
                tools: ["Read", "TaskCreate", "TaskUpdate"],
                file: ".claude/agents/planning-agent.md"
            ),
            AgentInfo(
                id: "designer-agent",
                name: "Designer",
                model: "claude-sonnet-4-6",
                description: "Creates SwiftUI design specs, screen skeletons, and visual polish passes.",
                skills: ["SwiftUI", "Design Systems", "HIG", "Accessibility"],
                displayName: "Designer",
                initials: "DS",
                mcpServers: ["peekaboo"],
                tools: ["Read", "Write"],
                file: ".claude/agents/designer-agent.md"
            )
        ]
    }

    private static func previewSecurity() -> [AgentInfo] {
        [
            AgentInfo(
                id: "security-audit-agent",
                name: "Security Audit",
                model: "claude-opus-4",
                description: "Orchestrates security review across static analysis, reasoning, and platform checks.",
                skills: ["Security", "SAST", "SBOM", "Secrets Detection"],
                displayName: "Security Audit",
                initials: "SA",
                mcpServers: nil,
                tools: ["Bash", "Read"],
                file: ".claude/agents/security-audit-agent.md"
            )
        ]
    }
}

// MARK: - Previews

#Preview("Grouped Roster \u{2014} Loaded") {
    GroupedRosterView(agents: AgentInfo.previewAll())
        .frame(width: 720, height: 600)
        .preferredColorScheme(.dark)
}

#Preview("Grouped Roster \u{2014} Light") {
    GroupedRosterView(agents: AgentInfo.previewAll())
        .frame(width: 720, height: 600)
        .preferredColorScheme(.light)
}

#Preview("Grouped Roster \u{2014} No Agents") {
    GroupedRosterView(agents: [])
        .frame(width: 720, height: 600)
}
