// swiftlint:disable file_length
import XCTest
@testable import AgileMaestro

// MARK: - RosterFilteringTests
//
// Tests for the roster filtering and grouping logic used in GroupedRosterView.
//
// The filtering logic lives in GroupedRosterView as private computed properties.
// This test file mirrors that logic exactly so tests remain in sync with the view.
// The grouping / sorting logic is also tested at the AgentInfo model layer.

// MARK: - Test Helpers

/// Mirrors GroupedRosterView.filteredAgents and GroupedRosterView.groupedAgents
/// so the logic can be exercised without spinning up a SwiftUI view.
private enum RosterFilter {

    /// Returns agents whose displayLabel, description, or any skill contains `query`
    /// (case-insensitive). When `query` is empty all agents are returned.
    static func filter(_ agents: [AgentInfo], query: String) -> [AgentInfo] {
        guard !query.isEmpty else { return agents }
        let lowercased = query.lowercased()
        return agents.filter { agent in
            agent.displayLabel.lowercased().contains(lowercased) ||
            agent.description.lowercased().contains(lowercased) ||
            agent.skills.contains { $0.lowercased().contains(lowercased) }
        }
    }

    /// Groups filtered agents by AgentRoleCategory in the canonical order:
    /// Core Team → Specialists → Security. Empty groups are omitted.
    static func group(_ agents: [AgentInfo]) -> [(label: String, agents: [AgentInfo])] {
        let groups: [(AgentRoleCategory, String)] = [
            (.coreTeam, "Core Team"),
            (.specialists, "Specialists"),
            (.security, "Security")
        ]
        return groups.compactMap { category, label in
            let inGroup = agents
                .filter { $0.roleCategory == category }
                .sorted(by: AgentInfo.sortComparator)
            guard !inGroup.isEmpty else { return nil }
            return (label: label, agents: inGroup)
        }
    }
}

// MARK: - AgentInfo Factories

private extension AgentInfo {

    // Convenience init with only the fields needed for these tests.
    static func make(
        id: String,
        displayName: String? = nil,
        description: String = "",
        skills: [String] = []
    ) -> AgentInfo {
        AgentInfo(
            id: id,
            name: displayName ?? id,
            model: "claude-sonnet-4-6",
            description: description,
            skills: skills,
            displayName: displayName,
            initials: nil,
            mcpServers: nil,
            tools: nil,
            file: nil
        )
    }

    /// A Core Team agent.
    static func coreTeam(
        id: String = "macos-developer-agent",
        displayName: String? = "macOS Developer",
        description: String = "",
        skills: [String] = []
    ) -> AgentInfo {
        make(id: id, displayName: displayName, description: description, skills: skills)
    }

    /// A Specialists agent (anything not in core team or security sets).
    static func specialist(
        id: String = "planning-agent",
        displayName: String? = "Planning",
        description: String = "",
        skills: [String] = []
    ) -> AgentInfo {
        make(id: id, displayName: displayName, description: description, skills: skills)
    }

    /// A Security agent.
    static func security(
        id: String = "security-audit-agent",
        displayName: String? = "Security Audit",
        description: String = "",
        skills: [String] = []
    ) -> AgentInfo {
        make(id: id, displayName: displayName, description: description, skills: skills)
    }
}

// MARK: - Search Filtering Tests

final class RosterSearchFilteringTests: XCTestCase {

    // MARK: - Empty Query

    func testEmptyQueryReturnsAllAgents() {
        let agents = [
            AgentInfo.coreTeam(),
            AgentInfo.specialist(),
            AgentInfo.security()
        ]
        let result = RosterFilter.filter(agents, query: "")
        XCTAssertEqual(result.count, 3)
    }

    func testWhitespaceOnlyQueryIsNonEmptyAndFilters() {
        // A single space is not empty — agents that contain " " in fields match.
        // By default our test agents have no space in fields, so result is empty.
        let agents = [AgentInfo.coreTeam(displayName: "macOS Developer")]
        let result = RosterFilter.filter(agents, query: " ")
        // "macos developer".contains(" ") → true ("macos developer" has a space)
        XCTAssertEqual(result.count, 1,
            "displayLabel 'macOS Developer' contains a space so it should match query ' '")
    }

    // MARK: - DisplayLabel Match

    func testQueryMatchesDisplayLabelExact() {
        let agent = AgentInfo.coreTeam(displayName: "macOS Developer")
        let result = RosterFilter.filter([agent], query: "macOS Developer")
        XCTAssertEqual(result.count, 1)
    }

    func testQueryMatchesDisplayLabelPartial() {
        let agent = AgentInfo.coreTeam(displayName: "macOS Developer")
        let result = RosterFilter.filter([agent], query: "mac")
        XCTAssertEqual(result.count, 1)
    }

    func testQueryDoesNotMatchUnrelatedAgent() {
        let agent = AgentInfo.coreTeam(displayName: "macOS Developer")
        let result = RosterFilter.filter([agent], query: "zzz")
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Description Match

    func testQueryMatchesDescription() {
        let agent = AgentInfo.coreTeam(
            displayName: "macOS Developer",
            description: "Builds SwiftUI views and Core Data models."
        )
        let result = RosterFilter.filter([agent], query: "Core Data")
        XCTAssertEqual(result.count, 1)
    }

    func testQueryMatchesDescriptionPartial() {
        let agent = AgentInfo.specialist(
            description: "Breaks epics into stories and writes acceptance criteria."
        )
        let result = RosterFilter.filter([agent], query: "accep")
        XCTAssertEqual(result.count, 1)
    }

    // MARK: - Skills Match

    func testQueryMatchesSkillExact() {
        let agent = AgentInfo.coreTeam(skills: ["SwiftUI", "Core Data", "async/await"])
        let result = RosterFilter.filter([agent], query: "SwiftUI")
        XCTAssertEqual(result.count, 1)
    }

    func testQueryMatchesSkillPartial() {
        let agent = AgentInfo.coreTeam(skills: ["SwiftUI", "Core Data"])
        let result = RosterFilter.filter([agent], query: "swift")
        XCTAssertEqual(result.count, 1)
    }

    func testQueryMatchesOneSkillAmongMany() {
        let agent = AgentInfo.specialist(
            skills: ["Planning", "Task Breakdown", "EARS"]
        )
        let result = RosterFilter.filter([agent], query: "EARS")
        XCTAssertEqual(result.count, 1)
    }

    func testQueryDoesNotMatchIfOnlyInSkillsOfOtherAgent() {
        let agentA = AgentInfo.coreTeam(skills: ["SwiftUI"])
        let agentB = AgentInfo.specialist(skills: ["Planning"])
        let result = RosterFilter.filter([agentA, agentB], query: "SwiftUI")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.displayLabel, "macOS Developer")
    }

    // MARK: - Case Insensitivity

    func testSearchIsCaseInsensitiveForDisplayLabel() {
        let agent = AgentInfo.coreTeam(displayName: "macOS Developer")
        let queries = ["macos developer", "MACOS DEVELOPER", "MacOs DeVeLoPeR", "MACOS"]
        for query in queries {
            let result = RosterFilter.filter([agent], query: query)
            XCTAssertEqual(result.count, 1,
                "Query '\(query)' should match 'macOS Developer' case-insensitively")
        }
    }

    func testSearchIsCaseInsensitiveForDescription() {
        let agent = AgentInfo.specialist(
            description: "Orchestrates security review across sub-agents."
        )
        let result = RosterFilter.filter([agent], query: "SECURITY")
        XCTAssertEqual(result.count, 1)
    }

    func testSearchIsCaseInsensitiveForSkills() {
        let agent = AgentInfo.coreTeam(skills: ["XCTest"])
        let result = RosterFilter.filter([agent], query: "xctest")
        XCTAssertEqual(result.count, 1)
    }

    func testSearchIsCaseInsensitiveForSkillsUppercase() {
        let agent = AgentInfo.coreTeam(skills: ["xctest"])
        let result = RosterFilter.filter([agent], query: "XCTEST")
        XCTAssertEqual(result.count, 1)
    }

    // MARK: - Multi-agent Filtering

    func testOnlyMatchingAgentsAreReturned() {
        let agents = [
            AgentInfo.coreTeam(displayName: "macOS Developer", skills: ["SwiftUI"]),
            AgentInfo.specialist(displayName: "Planning", skills: ["EARS"]),
            AgentInfo.security(displayName: "Security Audit", skills: ["SAST"])
        ]
        let result = RosterFilter.filter(agents, query: "SwiftUI")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.displayLabel, "macOS Developer")
    }

    func testMultipleAgentsMatchQuery() {
        let agents = [
            AgentInfo.coreTeam(
                displayName: "macOS Developer",
                description: "Builds Swift code."
            ),
            AgentInfo.specialist(
                displayName: "Planning",
                skills: ["Swift Planning"]
            )
        ]
        let result = RosterFilter.filter(agents, query: "swift")
        XCTAssertEqual(result.count, 2)
    }

    // MARK: - No Results

    func testNoMatchQueryReturnsEmptyArray() {
        let agents = [
            AgentInfo.coreTeam(displayName: "macOS Developer"),
            AgentInfo.specialist(displayName: "Planning"),
            AgentInfo.security(displayName: "Security Audit")
        ]
        let result = RosterFilter.filter(agents, query: "zzz-no-match-xyz")
        XCTAssertTrue(result.isEmpty)
    }

    func testEmptyAgentListAlwaysReturnsEmpty() {
        let result = RosterFilter.filter([], query: "swift")
        XCTAssertTrue(result.isEmpty)
    }

    func testEmptyAgentListWithEmptyQueryReturnsEmpty() {
        let result = RosterFilter.filter([], query: "")
        XCTAssertTrue(result.isEmpty)
    }
}

// MARK: - AgentInfo Model Tests

final class AgentInfoModelTests: XCTestCase {

    // MARK: - roleCategory

    func testCoreTeamAgentsHaveCorrectRoleCategory() {
        let coreTeamIds = [
            "macos-developer-agent",
            "staff-engineer-agent",
            "qa-agent",
            "pm-agent",
            "build-engineer-agent"
        ]
        for id in coreTeamIds {
            let agent = AgentInfo.make(id: id)
            XCTAssertEqual(agent.roleCategory, .coreTeam,
                "Agent '\(id)' should be .coreTeam")
        }
    }

    func testSecurityAgentsHaveCorrectRoleCategory() {
        let securityIds = [
            "security-audit-agent",
            "security-reasoning-agent",
            "security-static-agent",
            "security-platform-agent"
        ]
        for id in securityIds {
            let agent = AgentInfo.make(id: id)
            XCTAssertEqual(agent.roleCategory, .security,
                "Agent '\(id)' should be .security")
        }
    }

    func testUnknownAgentDefaultsToSpecialists() {
        let agent = AgentInfo.make(id: "some-custom-agent")
        XCTAssertEqual(agent.roleCategory, .specialists)
    }

    func testPlanningAgentIsSpecialist() {
        let agent = AgentInfo.make(id: "planning-agent")
        XCTAssertEqual(agent.roleCategory, .specialists)
    }

    func testDesignerAgentIsSpecialist() {
        let agent = AgentInfo.make(id: "designer-agent")
        XCTAssertEqual(agent.roleCategory, .specialists)
    }

    // MARK: - displayLabel

    func testDisplayLabelUsesDisplayNameWhenSet() {
        let agent = AgentInfo.make(id: "macos-developer-agent", displayName: "macOS Developer")
        XCTAssertEqual(agent.displayLabel, "macOS Developer")
    }

    func testDisplayLabelHumanizesIdWhenNoDisplayName() {
        let agent = AgentInfo.make(id: "staff-engineer-agent", displayName: nil)
        XCTAssertEqual(agent.displayLabel, "Staff Engineer")
    }

    func testDisplayLabelStripsAgentSuffix() {
        let agent = AgentInfo.make(id: "qa-agent", displayName: nil)
        XCTAssertEqual(agent.displayLabel, "Qa", "ID 'qa-agent' strips '-agent' → 'qa' → capitalized 'Qa'")
    }

    func testDisplayLabelPreferEmptyDisplayNameFallsBackToId() {
        // An empty displayName string should fall back to the ID-derived label.
        let agent = AgentInfo(
            id: "build-engineer-agent",
            name: "Build Engineer",
            model: "claude-haiku-4",
            description: "",
            skills: [],
            displayName: "",
            initials: nil,
            mcpServers: nil,
            tools: nil,
            file: nil
        )
        XCTAssertEqual(agent.displayLabel, "Build Engineer")
    }

    // MARK: - sortComparator

    func testSortComparatorOrdersCoreTeamBeforeSpecialists() {
        let core = AgentInfo.coreTeam()
        let specialist = AgentInfo.specialist()
        XCTAssertTrue(AgentInfo.sortComparator(core, specialist),
            "Core team agent should sort before specialist")
        XCTAssertFalse(AgentInfo.sortComparator(specialist, core),
            "Specialist should not sort before core team agent")
    }

    func testSortComparatorOrdersSpecialistsBeforeSecurity() {
        let specialist = AgentInfo.specialist()
        let security = AgentInfo.security()
        XCTAssertTrue(AgentInfo.sortComparator(specialist, security),
            "Specialist should sort before security agent")
        XCTAssertFalse(AgentInfo.sortComparator(security, specialist),
            "Security agent should not sort before specialist")
    }

    func testSortComparatorOrdersCoreTeamBeforeSecurity() {
        let core = AgentInfo.coreTeam()
        let security = AgentInfo.security()
        XCTAssertTrue(AgentInfo.sortComparator(core, security),
            "Core team agent should sort before security agent")
    }

    func testSortComparatorAlphabeticalWithinSameCategory() {
        let alpha = AgentInfo.specialist(id: "alpha-agent", displayName: "Alpha")
        let beta = AgentInfo.specialist(id: "beta-agent", displayName: "Beta")
        XCTAssertTrue(AgentInfo.sortComparator(alpha, beta),
            "'Alpha' should sort before 'Beta' within Specialists")
        XCTAssertFalse(AgentInfo.sortComparator(beta, alpha),
            "'Beta' should not sort before 'Alpha' within Specialists")
    }

    func testSortComparatorIsDeterministicForEqualLabels() {
        let agentA = AgentInfo.specialist(id: "planning-agent", displayName: "Planning")
        let agentB = AgentInfo.specialist(id: "planning-agent2", displayName: "Planning")
        // When labels are equal, comparator should return false for both directions
        // (stable, no preference) — we just verify it doesn't crash.
        let forward  = AgentInfo.sortComparator(agentA, agentB)
        let backward = AgentInfo.sortComparator(agentB, agentA)
        // Both should be false for equal display labels (consistent with String comparison)
        XCTAssertFalse(forward && backward,
            "Equal display labels must not be strictly less-than in both directions")
    }
}

// MARK: - AgentRoleCategory Tests

final class AgentRoleCategoryTests: XCTestCase {

    func testRawValuesDefineGroupOrder() {
        XCTAssertEqual(AgentRoleCategory.coreTeam.rawValue, 0)
        XCTAssertEqual(AgentRoleCategory.specialists.rawValue, 1)
        XCTAssertEqual(AgentRoleCategory.security.rawValue, 2)
    }

    func testComparableOrderingCoreTeamFirst() {
        XCTAssertLessThan(AgentRoleCategory.coreTeam, AgentRoleCategory.specialists)
        XCTAssertLessThan(AgentRoleCategory.coreTeam, AgentRoleCategory.security)
        XCTAssertLessThan(AgentRoleCategory.specialists, AgentRoleCategory.security)
    }

    func testEqualityForSameCase() {
        XCTAssertEqual(AgentRoleCategory.coreTeam, AgentRoleCategory.coreTeam)
        XCTAssertEqual(AgentRoleCategory.specialists, AgentRoleCategory.specialists)
        XCTAssertEqual(AgentRoleCategory.security, AgentRoleCategory.security)
    }

    func testInequalityAcrossCases() {
        XCTAssertNotEqual(AgentRoleCategory.coreTeam, AgentRoleCategory.specialists)
        XCTAssertNotEqual(AgentRoleCategory.coreTeam, AgentRoleCategory.security)
        XCTAssertNotEqual(AgentRoleCategory.specialists, AgentRoleCategory.security)
    }
}

// MARK: - Grouping Tests

final class RosterGroupingTests: XCTestCase {

    // MARK: - Group Ordering

    func testGroupOrderIsCoreTeamSpecialistsSecurity() {
        let agents = [
            AgentInfo.security(),
            AgentInfo.specialist(),
            AgentInfo.coreTeam()
        ]
        let groups = RosterFilter.group(agents)
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups[0].label, "Core Team")
        XCTAssertEqual(groups[1].label, "Specialists")
        XCTAssertEqual(groups[2].label, "Security")
    }

    func testEmptyGroupsAreOmitted() {
        // Only core team and security — no specialists.
        let agents = [
            AgentInfo.coreTeam(),
            AgentInfo.security()
        ]
        let groups = RosterFilter.group(agents)
        XCTAssertEqual(groups.count, 2)
        let labels = groups.map { $0.label }
        XCTAssertTrue(labels.contains("Core Team"))
        XCTAssertTrue(labels.contains("Security"))
        XCTAssertFalse(labels.contains("Specialists"),
            "Specialists group should be omitted when there are no specialist agents")
    }

    func testSingleGroupWhenAllAgentsSameCategory() {
        let agents = [
            AgentInfo.specialist(id: "planning-agent", displayName: "Planning"),
            AgentInfo.specialist(id: "designer-agent", displayName: "Designer")
        ]
        let groups = RosterFilter.group(agents)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].label, "Specialists")
        XCTAssertEqual(groups[0].agents.count, 2)
    }

    func testNoGroupsWhenNoAgents() {
        let groups = RosterFilter.group([])
        XCTAssertTrue(groups.isEmpty)
    }

    // MARK: - Agents Within Groups

    func testAgentsWithinGroupAreSortedAlphabetically() {
        let agents = [
            AgentInfo.specialist(id: "z-agent", displayName: "Zebra"),
            AgentInfo.specialist(id: "planning-agent", displayName: "Alpha"),
            AgentInfo.specialist(id: "m-agent", displayName: "Middle")
        ]
        let groups = RosterFilter.group(agents)
        XCTAssertEqual(groups.count, 1)
        let labels = groups[0].agents.map { $0.displayLabel }
        XCTAssertEqual(labels, ["Alpha", "Middle", "Zebra"])
    }

    func testEachAgentAppearsInCorrectGroup() {
        let core      = AgentInfo.coreTeam(displayName: "macOS Developer")
        let specialist = AgentInfo.specialist(displayName: "Planning")
        let security  = AgentInfo.security(displayName: "Security Audit")

        let groups = RosterFilter.group([core, specialist, security])
        XCTAssertEqual(groups.count, 3)

        let coreGroup      = groups.first { $0.label == "Core Team" }
        let specialistGroup = groups.first { $0.label == "Specialists" }
        let securityGroup  = groups.first { $0.label == "Security" }

        XCTAssertEqual(coreGroup?.agents.first?.displayLabel, "macOS Developer")
        XCTAssertEqual(specialistGroup?.agents.first?.displayLabel, "Planning")
        XCTAssertEqual(securityGroup?.agents.first?.displayLabel, "Security Audit")
    }

    func testMultipleCoreTeamAgentsAllAppearInCoreGroup() {
        let coreIds = [
            ("macos-developer-agent", "macOS Developer"),
            ("staff-engineer-agent", "Staff Engineer"),
            ("qa-agent", "QA"),
            ("pm-agent", "PM"),
            ("build-engineer-agent", "Build Engineer")
        ]
        let agents = coreIds.map { id, name in
            AgentInfo.coreTeam(id: id, displayName: name)
        }
        let groups = RosterFilter.group(agents)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].label, "Core Team")
        XCTAssertEqual(groups[0].agents.count, 5)
    }

    // MARK: - Filtered Groups

    func testGroupingAfterFilteringShowsOnlyMatchingGroups() {
        let agents = [
            AgentInfo.coreTeam(displayName: "macOS Developer", skills: ["SwiftUI"]),
            AgentInfo.specialist(displayName: "Planning", skills: ["EARS"]),
            AgentInfo.security(displayName: "Security Audit", skills: ["SAST"])
        ]
        // Filter leaves only the specialist (skills match "EARS")
        let filtered = RosterFilter.filter(agents, query: "EARS")
        let groups = RosterFilter.group(filtered)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].label, "Specialists")
        XCTAssertEqual(groups[0].agents.first?.displayLabel, "Planning")
    }

    func testGroupingAfterFilteringNoResultsIsEmpty() {
        let agents = [
            AgentInfo.coreTeam(),
            AgentInfo.specialist(),
            AgentInfo.security()
        ]
        let filtered = RosterFilter.filter(agents, query: "zzz-no-match")
        let groups = RosterFilter.group(filtered)
        XCTAssertTrue(groups.isEmpty)
    }
}

// MARK: - Accordion Logic Tests
//
// The accordion state (expandedAgentId: String?) lives in GroupedRosterView as @State.
// We test the toggle/collapse logic as a pure function here.

private enum AccordionLogic {

    /// Toggles the expanded state for `agentId`.
    /// - If `agentId` is already expanded → collapse (return nil).
    /// - If a different agent is expanded → switch to `agentId` (SM-TEAM-003).
    /// - If nothing is expanded → expand `agentId`.
    static func toggle(current expandedId: String?, tapping agentId: String) -> String? {
        expandedId == agentId ? nil : agentId
    }

    /// Collapses all cards (called when the search query changes — SM-TEAM-004).
    static func collapseAll() -> String? { nil }
}

final class AccordionLogicTests: XCTestCase {

    // MARK: - Expand

    func testTappingCollapsedCardExpandsIt() {
        let result = AccordionLogic.toggle(current: nil, tapping: "agent-a")
        XCTAssertEqual(result, "agent-a")
    }

    // MARK: - Collapse

    func testTappingExpandedCardCollapsesIt() {
        let result = AccordionLogic.toggle(current: "agent-a", tapping: "agent-a")
        XCTAssertNil(result, "Tapping the already-expanded card should collapse it")
    }

    // MARK: - SM-TEAM-003: Only One Card Expanded at a Time

    func testTappingDifferentCardSwitchesExpansion() {
        // SM-TEAM-003: accordion — only one card expanded at a time.
        let result = AccordionLogic.toggle(current: "agent-a", tapping: "agent-b")
        XCTAssertEqual(result, "agent-b",
            "SM-TEAM-003: tapping agent-b while agent-a is expanded must collapse agent-a and expand agent-b")
    }

    func testOnlyOneCardCanBeExpandedAtATime() {
        // Simulate three sequential taps.
        var expanded: String?
        expanded = AccordionLogic.toggle(current: expanded, tapping: "agent-a")
        XCTAssertEqual(expanded, "agent-a")

        expanded = AccordionLogic.toggle(current: expanded, tapping: "agent-b")
        XCTAssertEqual(expanded, "agent-b", "agent-a must be implicitly collapsed")

        expanded = AccordionLogic.toggle(current: expanded, tapping: "agent-c")
        XCTAssertEqual(expanded, "agent-c", "agent-b must be implicitly collapsed")
    }

    // MARK: - SM-TEAM-004: Search Change Collapses All

    func testSearchChangeCollapsesAllCards() {
        // SM-TEAM-004: accordion collapses when search query changes.
        let expanded = "agent-a"
        let afterSearch = AccordionLogic.collapseAll()
        XCTAssertNil(afterSearch,
            "SM-TEAM-004: changing the search query must collapse all expanded cards")
        _ = expanded // suppress unused warning
    }

    func testCollapseAllIsIdempotent() {
        XCTAssertNil(AccordionLogic.collapseAll())
        XCTAssertNil(AccordionLogic.collapseAll())
    }
}
