import XCTest
@testable import AgileMaestro

// MARK: - TeamViewModel Search Filtering Tests

@MainActor
final class TeamViewModelSearchFilteringTests: TeamViewModelTestCase {

    // MARK: - Setup

    override func setUp() async throws {
        try await super.setUp()

        // Pre-load a manifest with multiple agents for filtering tests.
        let agents: [AgentInfo] = [
            .testMake(
                id: "macos-developer-agent",
                name: "macOS Developer",
                description: "Builds SwiftUI views.",
                skills: ["SwiftUI", "Core Data"]
            ),
            .testMake(
                id: "qa-agent",
                name: "QA",
                description: "Runs targeted tests.",
                skills: ["XCTest"]
            ),
            .testMake(
                id: "planning-agent",
                name: "Planning",
                description: "Writes acceptance criteria.",
                skills: ["EARS", "Agile"]
            )
        ]
        mockService.setManifest(AgentManifest.testMake(agents: agents))
        await sut.loadManifest(for: Product.testWithClaudeDir(tempClaudeDir))
    }

    // MARK: - Empty query

    func testEmptySearchQuery_returnsAllAgents() {
        sut.searchQuery = ""
        XCTAssertEqual(sut.filteredAgents.count, 3)
    }

    // MARK: - Partial name match

    func testPartialNameMatch_returnsMatchingAgent() {
        sut.searchQuery = "mac"
        let result = sut.filteredAgents
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, "macos-developer-agent")
    }

    // MARK: - No match

    func testNoMatchQuery_returnsEmptyArray() {
        sut.searchQuery = "zzz-no-match-xyz"
        XCTAssertTrue(sut.filteredAgents.isEmpty)
    }

    // MARK: - Clear search

    func testClearingSearch_returnsAllAgents() {
        sut.searchQuery = "swift"
        XCTAssertEqual(sut.filteredAgents.count, 1,
            "Precondition: 'swift' should match 1 agent")
        sut.searchQuery = ""
        XCTAssertEqual(sut.filteredAgents.count, 3,
            "Clearing the search must restore all agents")
    }

    // MARK: - Case-insensitive matching

    func testCaseInsensitiveMatch_lowercase() {
        sut.searchQuery = "macos developer"
        XCTAssertEqual(sut.filteredAgents.count, 1)
    }

    func testCaseInsensitiveMatch_uppercase() {
        sut.searchQuery = "MACOS DEVELOPER"
        XCTAssertEqual(sut.filteredAgents.count, 1)
    }

    func testCaseInsensitiveMatch_mixedCase() {
        sut.searchQuery = "MacOs DeVeLoPeR"
        XCTAssertEqual(sut.filteredAgents.count, 1)
    }

    // MARK: - Description match

    func testDescriptionMatch_returnsMatchingAgent() {
        sut.searchQuery = "targeted tests"
        let result = sut.filteredAgents
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, "qa-agent")
    }

    // MARK: - Skills match

    func testSkillsMatch_returnsMatchingAgent() {
        sut.searchQuery = "EARS"
        let result = sut.filteredAgents
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, "planning-agent")
    }

    func testSkillsMatch_caseInsensitive() {
        sut.searchQuery = "xctest"
        let result = sut.filteredAgents
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, "qa-agent")
    }

    // MARK: - filteredAgents empty when not loaded

    func testFilteredAgents_notLoaded_returnsEmpty() {
        let fresh = TeamViewModel(manifestService: mockService)
        fresh.searchQuery = "swift"
        XCTAssertTrue(fresh.filteredAgents.isEmpty,
            "filteredAgents must be empty when viewState is not .loaded")
    }
}

// MARK: - TeamViewModel Computed Properties Tests

@MainActor
final class TeamViewModelComputedPropertiesTests: TeamViewModelTestCase {

    // MARK: - agents

    func testAgents_notLoaded_returnsEmptyArray() {
        XCTAssertTrue(sut.agents.isEmpty)
    }

    func testAgents_loaded_returnsManifestAgents() async {
        let agents: [AgentInfo] = [.testMake(id: "a"), .testMake(id: "b")]
        mockService.setManifest(AgentManifest.testMake(agents: agents))
        await sut.loadManifest(for: Product.testWithClaudeDir(tempClaudeDir))

        XCTAssertEqual(sut.agents.count, 2)
        let ids = sut.agents.map(\.id)
        XCTAssertTrue(ids.contains("a"))
        XCTAssertTrue(ids.contains("b"))
    }

    // MARK: - pipelines

    func testPipelines_notLoaded_returnsEmptyArray() {
        XCTAssertTrue(sut.pipelines.isEmpty)
    }

    func testPipelines_loaded_returnsManifestPipelines() async {
        let pipeline = WorkflowPipeline(id: "task-pipeline", label: "Task", stages: [])
        mockService.setManifest(AgentManifest.testMake(pipelines: [pipeline]))
        await sut.loadManifest(for: Product.testWithClaudeDir(tempClaudeDir))

        XCTAssertEqual(sut.pipelines.count, 1)
        XCTAssertEqual(sut.pipelines.first?.id, "task-pipeline")
    }

    // MARK: - health

    func testHealth_notLoaded_returnsNil() {
        XCTAssertNil(sut.health)
    }

    func testHealth_loaded_returnsManifestHealth() async throws {
        let health = DirectoryHealth(
            agentCount: 5, commandCount: 10, skillCount: 3, ruleCount: 8
        )
        mockService.setManifest(AgentManifest.testMake(health: health))
        await sut.loadManifest(for: Product.testWithClaudeDir(tempClaudeDir))

        let loadedHealth = try XCTUnwrap(sut.health)
        XCTAssertEqual(loadedHealth.agentCount, 5)
        XCTAssertEqual(loadedHealth.commandCount, 10)
        XCTAssertEqual(loadedHealth.skillCount, 3)
        XCTAssertEqual(loadedHealth.ruleCount, 8)
    }

    // MARK: - generatedAt

    func testGeneratedAt_notLoaded_returnsNil() {
        XCTAssertNil(sut.generatedAt)
    }

    func testGeneratedAt_loaded_returnsManifestTimestamp() async {
        let timestamp = "2026-03-28T12:00:00Z"
        mockService.setManifest(AgentManifest.testMake(generatedAt: timestamp))
        await sut.loadManifest(for: Product.testWithClaudeDir(tempClaudeDir))
        XCTAssertEqual(sut.generatedAt, timestamp)
    }

    // MARK: - Computed properties empty/nil after error

    func testComputedProperties_afterError_returnEmptyOrNil() async {
        mockService.setError(ManifestError.directoryNotFound)
        await sut.loadManifest(for: Product.testWithClaudeDir(tempClaudeDir))

        XCTAssertTrue(sut.agents.isEmpty, "agents must be empty in error state")
        XCTAssertTrue(sut.pipelines.isEmpty, "pipelines must be empty in error state")
        XCTAssertNil(sut.health, "health must be nil in error state")
        XCTAssertNil(sut.generatedAt, "generatedAt must be nil in error state")
    }
}

// MARK: - TeamViewModel Update Cycle Tests

@MainActor
final class TeamViewModelUpdateCycleTests: TeamViewModelTestCase {

    // MARK: - updateManifest(for:) — no toolkit path is a no-op

    func testUpdateManifest_noClaudeDirPath_isNoOp() async {
        let product = Product.testWithoutClaudeDir()
        await sut.updateManifest(for: product)

        XCTAssertEqual(sut.viewState, .idle)
        XCTAssertFalse(sut.isUpdating)
        XCTAssertEqual(mockService.loadManifestCallCount, 0)
    }

    // MARK: - updateManifest() no-arg overload is a no-op

    func testUpdateManifest_noArg_isNoOp() async {
        await sut.updateManifest()
        XCTAssertEqual(sut.viewState, .idle)
        XCTAssertFalse(sut.isUpdating)
        XCTAssertEqual(mockService.loadManifestCallCount, 0)
    }

    // MARK: - Initial isUpdating

    func testIsUpdating_defaultsFalse() {
        XCTAssertFalse(sut.isUpdating)
    }
}

// MARK: - TeamViewModel Multi-Load Tests

@MainActor
final class TeamViewModelMultiLoadTests: TeamViewModelTestCase {

    // MARK: - Loaded state holds correct manifest

    func testLoadedState_holdsCorrectManifestAfterMultipleLoads() async {
        let product = Product.testWithClaudeDir(tempClaudeDir)

        mockService.setManifest(AgentManifest.testMake(agents: [.testMake(id: "a1")]))
        await sut.loadManifest(for: product)

        mockService.setManifest(
            AgentManifest.testMake(agents: [.testMake(id: "b1"), .testMake(id: "b2")])
        )
        await sut.loadManifest(for: product)

        XCTAssertEqual(sut.agents.count, 2,
            "viewModel should reflect the most recent manifest")
        XCTAssertEqual(sut.agents.map(\.id).sorted(), ["b1", "b2"])
    }

    // MARK: - Error state message contains useful information

    func testErrorState_messageIsNonEmpty() async {
        struct TestError: LocalizedError {
            var errorDescription: String? { "JSON parse error at line 42" }
        }
        mockService.setError(TestError())
        let product = Product.testWithClaudeDir(tempClaudeDir)
        await sut.loadManifest(for: product)

        guard case .error(let message) = sut.viewState else {
            return XCTFail("Expected .error state")
        }
        XCTAssertFalse(message.isEmpty)
        XCTAssertTrue(
            message.contains("JSON parse error"),
            "Error message should propagate the underlying error description"
        )
    }

    // MARK: - hasToolkitPath after successful load

    func testHasToolkitPath_trueAfterSuccessfulLoad() async {
        let product = Product.testWithClaudeDir(tempClaudeDir)
        await sut.loadManifest(for: product)
        XCTAssertTrue(sut.hasToolkitPath)
    }

    // MARK: - isManifestMissing after successful load

    func testIsManifestMissing_falseAfterSuccessfulLoad() async {
        let product = Product.testWithClaudeDir(tempClaudeDir)
        await sut.loadManifest(for: product)
        XCTAssertFalse(sut.isManifestMissing)
    }
}
