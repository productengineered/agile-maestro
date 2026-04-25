import XCTest
@testable import AgileMaestro

// MARK: - TeamSection Tests

final class TeamSectionTests: XCTestCase {

    // MARK: - CaseIterable

    func testAllCasesExist() {
        let all = TeamSection.allCases
        XCTAssertEqual(all.count, 3)
        XCTAssertTrue(all.contains(.roster))
        XCTAssertTrue(all.contains(.pipeline))
        XCTAssertTrue(all.contains(.health))
    }

    // MARK: - title

    func testTitleMatchesRawValue() {
        let cases: [(TeamSection, String)] = [
            (.roster, "Team Roster"),
            (.pipeline, "Workflow"),
            (.health, "Directory Health")
        ]
        for (section, expected) in cases {
            XCTAssertEqual(section.title, expected, "title mismatch for .\(section)")
            XCTAssertEqual(section.title, section.rawValue, "title should alias rawValue for .\(section)")
        }
    }

    // MARK: - icon

    func testIconReturnsCorrectSFSymbol() {
        let cases: [(TeamSection, String)] = [
            (.roster, "person.3.fill"),
            (.pipeline, "arrow.triangle.branch"),
            (.health, "checkmark.shield.fill")
        ]
        for (section, expected) in cases {
            XCTAssertEqual(section.icon, expected, "icon mismatch for .\(section)")
        }
    }

}

// MARK: - TeamViewModel.ViewState Tests

@MainActor
final class TeamViewStateTests: XCTestCase {

    // MARK: - All Cases Exist

    func testAllCasesExist() {
        // Verify the SM-TEAM-001 state machine cases compile and can be instantiated.
        let idle: TeamViewModel.ViewState = .idle
        let loading: TeamViewModel.ViewState = .loading
        let loaded: TeamViewModel.ViewState = .loaded(AgentManifest.preview)
        let error: TeamViewModel.ViewState = .error("parse failed")

        // Each case is distinct — none are equal to another.
        XCTAssertNotEqual(idle, loading)
        XCTAssertNotEqual(idle, loaded)
        XCTAssertNotEqual(idle, error)
        XCTAssertNotEqual(loading, loaded)
        XCTAssertNotEqual(loading, error)
        XCTAssertNotEqual(loaded, error)
    }

    // MARK: - Equatable: same-case equality

    func testEqualToSelf_idle() {
        XCTAssertEqual(TeamViewModel.ViewState.idle, .idle)
    }

    func testEqualToSelf_loading() {
        XCTAssertEqual(TeamViewModel.ViewState.loading, .loading)
    }

    func testEqualToSelf_loaded() {
        let manifest = AgentManifest.preview
        XCTAssertEqual(TeamViewModel.ViewState.loaded(manifest), .loaded(manifest))
    }

    func testEqualToSelf_error() {
        XCTAssertEqual(TeamViewModel.ViewState.error("msg"), .error("msg"))
    }

    // MARK: - Equatable: cross-case inequality

    func testInequalityAcrossCases() {
        let manifest = AgentManifest.preview
        let cases: [TeamViewModel.ViewState] = [
            .idle,
            .loading,
            .loaded(manifest),
            .error("err")
        ]
        for idx in cases.indices {
            for jdx in cases.indices where idx != jdx {
                XCTAssertNotEqual(cases[idx], cases[jdx],
                    "Expected \(cases[idx]) != \(cases[jdx])")
            }
        }
    }

    // MARK: - Pattern matching

    func testPatternMatching() {
        let state: TeamViewModel.ViewState = .loaded(AgentManifest.preview)
        var matched = false
        if case .loaded = state {
            matched = true
        }
        XCTAssertTrue(matched, "Pattern matching for .loaded should succeed")
    }

}

// MARK: - Shared Test Helpers

/// Builds a Product with a claudeDirectoryPath pointing to a temp directory.
extension Product {
    static func testWithClaudeDir(_ dir: URL) -> Product {
        // `dir` is the .claude/ directory itself. Product.claudeDirectoryURL appends
        // ".claude" to claudeDirectoryPath, so we store the parent to avoid a
        // doubly-nested .claude/.claude path that fails the file-existence guard.
        Product(
            name: "Test Product",
            claudeDirectoryPath: dir.deletingLastPathComponent().path(percentEncoded: false)
        )
    }

    static func testWithoutClaudeDir() -> Product {
        Product(name: "Test Product", claudeDirectoryPath: nil)
    }
}

/// Builds a minimal AgentManifest with the given agents.
extension AgentManifest {
    static func testMake(
        agents: [AgentInfo] = [],
        pipelines: [WorkflowPipeline] = [],
        health: DirectoryHealth = DirectoryHealth(
            agentCount: 0, commandCount: 0, skillCount: 0, ruleCount: 0
        ),
        generatedAt: String = "2026-03-28T00:00:00Z"
    ) -> AgentManifest {
        AgentManifest(
            agents: agents,
            commands: [],
            skills: [],
            rules: [],
            directoryHealth: health,
            generatedAt: generatedAt,
            workflowPipelines: pipelines
        )
    }
}

/// Builds a minimal AgentInfo for tests.
extension AgentInfo {
    static func testMake(
        id: String = "test-agent",
        name: String = "Test Agent",
        description: String = "",
        skills: [String] = []
    ) -> AgentInfo {
        AgentInfo(
            id: id,
            name: name,
            model: "claude-sonnet-4-6",
            description: description,
            skills: skills,
            displayName: name,
            initials: nil,
            mcpServers: nil,
            tools: nil,
            file: nil
        )
    }
}

// MARK: - Shared Temp Directory Helper

/// Shared setup logic for tests that need a .claude/ temp directory with a manifest stub.
@MainActor
class TeamViewModelTestCase: XCTestCase {

    var sut: TeamViewModel!
    var mockService: MockManifestService!
    var tempClaudeDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        mockService = MockManifestService()
        sut = TeamViewModel(manifestService: mockService)

        tempClaudeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempClaudeDir,
            withIntermediateDirectories: true
        )
        // Create a team-manifest.json stub so the file-existence guard passes.
        let stubURL = tempClaudeDir.appendingPathComponent("team-manifest.json")
        try Data("{}".utf8).write(to: stubURL)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempClaudeDir)
        sut = nil
        mockService = nil
        tempClaudeDir = nil
        try await super.tearDown()
    }
}

// MARK: - TeamViewModel State Machine Tests (SM-TEAM-001)

@MainActor
final class TeamViewModelStateMachineTests: TeamViewModelTestCase {

    // MARK: - Initial State

    func testInitialStateIsIdle() {
        XCTAssertEqual(sut.viewState, .idle)
        XCTAssertFalse(sut.hasToolkitPath)
        XCTAssertFalse(sut.isManifestMissing)
        XCTAssertFalse(sut.isUpdating)
    }

    // MARK: - SM-TEAM-001: idle guard — no toolkit path

    func testLoadManifest_noClaudeDirPath_staysIdleHasToolkitPathFalse() async {
        let product = Product.testWithoutClaudeDir()
        await sut.loadManifest(for: product)

        XCTAssertEqual(sut.viewState, .idle)
        XCTAssertFalse(sut.hasToolkitPath,
            "hasToolkitPath must be false when no claudeDirectoryPath configured")
        XCTAssertFalse(sut.isManifestMissing)
        XCTAssertEqual(mockService.loadManifestCallCount, 0,
            "Service must not be called when no toolkit path")
    }

    // MARK: - SM-TEAM-001: idle guard — manifest file missing

    func testLoadManifest_manifestFileMissing_staysIdleIsManifestMissingTrue() async {
        // Remove the stub file so the guard triggers.
        let manifestURL = tempClaudeDir.appendingPathComponent("team-manifest.json")
        try? FileManager.default.removeItem(at: manifestURL)

        let product = Product.testWithClaudeDir(tempClaudeDir)
        await sut.loadManifest(for: product)

        XCTAssertEqual(sut.viewState, .idle)
        XCTAssertTrue(sut.hasToolkitPath)
        XCTAssertTrue(sut.isManifestMissing,
            "isManifestMissing must be true when manifest file is absent")
        XCTAssertEqual(mockService.loadManifestCallCount, 0,
            "Service must not be called when manifest file missing")
    }

    // MARK: - SM-TEAM-001: idle → loading → loaded

    func testLoadManifest_success_transitionsToLoaded() async {
        let manifest = AgentManifest.testMake(agents: [.testMake()])
        mockService.setManifest(manifest)

        let product = Product.testWithClaudeDir(tempClaudeDir)
        await sut.loadManifest(for: product)

        guard case .loaded(let loadedManifest) = sut.viewState else {
            return XCTFail("Expected .loaded but got \(sut.viewState)")
        }
        XCTAssertEqual(loadedManifest, manifest)
        XCTAssertTrue(sut.hasToolkitPath)
        XCTAssertFalse(sut.isManifestMissing)
        XCTAssertEqual(mockService.loadManifestCallCount, 1)
    }

    // MARK: - SM-TEAM-001: idle → loading → error

    func testLoadManifest_failure_transitionsToError() async {
        mockService.setError(ManifestError.directoryNotFound)

        let product = Product.testWithClaudeDir(tempClaudeDir)
        await sut.loadManifest(for: product)

        guard case .error(let message) = sut.viewState else {
            return XCTFail("Expected .error but got \(sut.viewState)")
        }
        XCTAssertFalse(message.isEmpty, "Error message must be non-empty")
    }

    // MARK: - SM-TEAM-001: loaded → loading (refresh)

    func testLoadManifest_calledAgainWhileLoaded_reloadsToLoaded() async {
        // Load once to reach .loaded.
        let manifest1 = AgentManifest.testMake(agents: [.testMake(id: "agent-1")])
        mockService.setManifest(manifest1)
        let product = Product.testWithClaudeDir(tempClaudeDir)
        await sut.loadManifest(for: product)

        guard case .loaded = sut.viewState else {
            return XCTFail("Setup: expected .loaded after first load")
        }

        // Load again (refresh) with a different manifest.
        let manifest2 = AgentManifest.testMake(
            agents: [.testMake(id: "agent-1"), .testMake(id: "agent-2")]
        )
        mockService.setManifest(manifest2)
        await sut.loadManifest(for: product)

        guard case .loaded(let loadedManifest) = sut.viewState else {
            return XCTFail("Expected .loaded after refresh but got \(sut.viewState)")
        }
        XCTAssertEqual(loadedManifest.agents.count, 2)
        XCTAssertEqual(mockService.loadManifestCallCount, 2)
    }

    // MARK: - SM-TEAM-001: error → loading (retry)

    func testLoadManifest_afterError_retriesAndCanSucceed() async {
        // First load → error.
        mockService.setError(ManifestError.directoryNotFound)
        let product = Product.testWithClaudeDir(tempClaudeDir)
        await sut.loadManifest(for: product)

        guard case .error = sut.viewState else {
            return XCTFail("Expected .error state after first load")
        }

        // Retry → success.
        let manifest = AgentManifest.testMake()
        mockService.setManifest(manifest)
        await sut.loadManifest(for: product)

        guard case .loaded = sut.viewState else {
            return XCTFail("Expected .loaded after retry but got \(sut.viewState)")
        }
        XCTAssertEqual(mockService.loadManifestCallCount, 2)
    }

    // MARK: - SM-TEAM-001: claudeDir URL passed to service

    func testLoadManifest_passesCorrectClaudeDirToService() async {
        let product = Product.testWithClaudeDir(tempClaudeDir)
        await sut.loadManifest(for: product)
        XCTAssertEqual(mockService.lastClaudeDir, tempClaudeDir)
    }

    // MARK: - Service call count

    func testServiceCallCount_incrementsOnEachLoad() async {
        let product = Product.testWithClaudeDir(tempClaudeDir)
        await sut.loadManifest(for: product)
        await sut.loadManifest(for: product)
        await sut.loadManifest(for: product)
        XCTAssertEqual(mockService.loadManifestCallCount, 3)
    }
}

// MARK: - TeamViewModel Product Change Tests

@MainActor
final class TeamViewModelProductChangeTests: TeamViewModelTestCase {

    func testProductChange_resetsStateAndReloads() async {
        // Load with product A.
        let productA = Product.testWithClaudeDir(tempClaudeDir)
        mockService.setManifest(AgentManifest.testMake(agents: [.testMake()]))
        await sut.loadManifest(for: productA)

        guard case .loaded = sut.viewState else {
            return XCTFail("Setup: expected .loaded after first load")
        }

        sut.searchQuery = "swift"
        sut.selectedSection = .health

        // Set up a second temp directory for product B.
        let secondDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(".claude", isDirectory: true)
        try? FileManager.default.createDirectory(at: secondDir, withIntermediateDirectories: true)
        let stub = secondDir.appendingPathComponent("team-manifest.json")
        try? Data("{}".utf8).write(to: stub)
        defer { try? FileManager.default.removeItem(at: secondDir) }

        let productB = Product.testWithClaudeDir(secondDir)
        mockService.setManifest(AgentManifest.testMake())
        await sut.loadManifest(for: productB)

        // searchQuery must be cleared on product change.
        XCTAssertEqual(sut.searchQuery, "",
            "searchQuery must be reset to empty on product change")
        XCTAssertFalse(sut.isUpdating)
        XCTAssertEqual(mockService.loadManifestCallCount, 2)
    }

    func testProductChange_hasToolkitPathResets_whenNewProductHasNoPath() async {
        let productA = Product.testWithClaudeDir(tempClaudeDir)
        mockService.setManifest(AgentManifest.testMake())
        await sut.loadManifest(for: productA)
        XCTAssertTrue(sut.hasToolkitPath)

        let productB = Product.testWithoutClaudeDir()
        await sut.loadManifest(for: productB)

        XCTAssertFalse(sut.hasToolkitPath,
            "hasToolkitPath must reset to false when new product has no claudeDirectoryPath")
        XCTAssertEqual(sut.viewState, .idle)
    }

    func testSameProduct_doesNotResetSearchQuery() async {
        let productA = Product.testWithClaudeDir(tempClaudeDir)
        mockService.setManifest(AgentManifest.testMake())
        await sut.loadManifest(for: productA)

        sut.searchQuery = "dev"
        mockService.resetCallTracking()
        mockService.setManifest(AgentManifest.testMake())
        await sut.loadManifest(for: productA)

        XCTAssertEqual(sut.searchQuery, "dev",
            "searchQuery must NOT be reset when reloading the same product")
        XCTAssertEqual(mockService.loadManifestCallCount, 1)
    }
}

// MARK: - TeamViewModel Default Properties Tests

@MainActor
final class TeamViewModelDefaultPropertiesTests: XCTestCase {

    private var sut: TeamViewModel!

    override func setUp() async throws {
        try await super.setUp()
        sut = TeamViewModel()
    }

    override func tearDown() async throws {
        sut = nil
        try await super.tearDown()
    }

    func testDefaultProperties() {
        XCTAssertEqual(sut.viewState, .idle)
        XCTAssertEqual(sut.searchQuery, "")
        XCTAssertEqual(sut.selectedSection, .roster)
        XCTAssertFalse(sut.showEditProduct)
        XCTAssertFalse(sut.hasToolkitPath)
        XCTAssertFalse(sut.isManifestMissing)
        XCTAssertFalse(sut.isUpdating)
    }

    func testSearchQuery_canBeSet() {
        sut.searchQuery = "swift"
        XCTAssertEqual(sut.searchQuery, "swift")
    }

    func testSelectedSection_canBeChanged() {
        sut.selectedSection = .pipeline
        XCTAssertEqual(sut.selectedSection, .pipeline)

        sut.selectedSection = .health
        XCTAssertEqual(sut.selectedSection, .health)
    }

    func testShowEditProduct_canBeToggled() {
        sut.showEditProduct = true
        XCTAssertTrue(sut.showEditProduct)

        sut.showEditProduct = false
        XCTAssertFalse(sut.showEditProduct)
    }
}
