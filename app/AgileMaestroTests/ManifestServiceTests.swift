import XCTest
@testable import AgileMaestro

// MARK: - ManifestServiceTests

final class ManifestServiceTests: XCTestCase {

    // MARK: - Properties

    private var sut: ManifestService!
    private var tempClaudeDir: URL!
    private let fileManager = FileManager.default

    // MARK: - Setup / Teardown

    override func setUp() {
        super.setUp()
        sut = ManifestService()
        tempClaudeDir = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(".claude", isDirectory: true)
        try? fileManager.createDirectory(at: tempClaudeDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? fileManager.removeItem(at: tempClaudeDir)
        sut = nil
        tempClaudeDir = nil
        super.tearDown()
    }

    // MARK: - Directory Not Found

    func testMissingDirectoryThrowsDirectoryNotFound() async {
        let missingDir = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(".claude", isDirectory: true)

        do {
            _ = try await sut.loadManifest(from: missingDir)
            XCTFail("Expected ManifestError.directoryNotFound to be thrown")
        } catch ManifestError.directoryNotFound {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Empty Directory

    func testEmptyClaudeDirectoryReturnsZeroCounts() async throws {
        // tempClaudeDir exists but has no subdirectories
        let manifest = try await sut.loadManifest(from: tempClaudeDir)

        XCTAssertTrue(manifest.agents.isEmpty, "No agents directory — agents should be empty")
        XCTAssertTrue(manifest.commands.isEmpty, "No commands directory — commands should be empty")
        XCTAssertTrue(manifest.skills.isEmpty, "No skills directory — skills should be empty")
        XCTAssertTrue(manifest.rules.isEmpty, "No rules directory — rules should be empty")

        XCTAssertEqual(manifest.directoryHealth.agentCount, 0)
        XCTAssertEqual(manifest.directoryHealth.commandCount, 0)
        XCTAssertEqual(manifest.directoryHealth.skillCount, 0)
        XCTAssertEqual(manifest.directoryHealth.ruleCount, 0)
    }

    func testEmptyClaudeDirectoryReturnsNonEmptyGeneratedAt() async throws {
        let manifest = try await sut.loadManifest(from: tempClaudeDir)
        XCTAssertFalse(manifest.generatedAt.isEmpty, "generatedAt should be a non-empty ISO8601 string")
    }

    // MARK: - Agent Parsing

    func testParsesAgentFromFrontMatter() async throws {
        createAgentsDir()
        writeFile(
            """
            ---
            name: macOS Developer
            description: "Builds SwiftUI views and ViewModels."
            model: claude-sonnet-4-6
            mcpServers: ["xcode", "peekaboo"]
            skills: SwiftUI, Core Data
            ---
            # macOS Developer Agent
            """,
            named: "macos-developer-agent.md",
            in: agentsDir()
        )

        let manifest = try await sut.loadManifest(from: tempClaudeDir)

        XCTAssertEqual(manifest.agents.count, 1)
        let agent = try XCTUnwrap(manifest.agents.first)
        XCTAssertEqual(agent.id, "macos-developer-agent")
        XCTAssertEqual(agent.name, "macOS Developer")
        XCTAssertEqual(agent.model, "claude-sonnet-4-6")
        XCTAssertEqual(agent.description, "Builds SwiftUI views and ViewModels.")
        XCTAssertEqual(agent.mcpServers, ["xcode", "peekaboo"])
        XCTAssertEqual(agent.skills, ["SwiftUI", "Core Data"])
        XCTAssertEqual(agent.file, "macos-developer-agent.md")
    }

    func testAgentWithNoFrontMatterUsesFilename() async throws {
        createAgentsDir()
        writeFile(
            "# Just a heading\nNo front matter here.",
            named: "my-agent.md",
            in: agentsDir()
        )

        let manifest = try await sut.loadManifest(from: tempClaudeDir)

        XCTAssertEqual(manifest.agents.count, 1)
        let agent = try XCTUnwrap(manifest.agents.first)
        XCTAssertEqual(agent.id, "my-agent")
        XCTAssertEqual(agent.name, "my-agent", "Should fall back to filename when name is absent")
        XCTAssertEqual(agent.model, "unknown", "Should default to 'unknown' when model is absent")
    }

    func testMultipleAgentsAreSortedByRoleThenName() async throws {
        createAgentsDir()
        writeFile(
            "---\nname: QA Agent\nmodel: claude-haiku\n---\n",
            named: "qa-agent.md",
            in: agentsDir()
        )
        writeFile(
            "---\nname: macOS Developer\nmodel: claude-sonnet-4-6\n---\n",
            named: "macos-developer-agent.md",
            in: agentsDir()
        )
        writeFile(
            "---\nname: Custom Specialist\nmodel: claude-sonnet-4-6\n---\n",
            named: "custom-specialist-agent.md",
            in: agentsDir()
        )

        let manifest = try await sut.loadManifest(from: tempClaudeDir)
        XCTAssertEqual(manifest.agents.count, 3)

        // Core team first: macos-developer-agent (coreTeam) and qa-agent (coreTeam)
        // Specialists last: custom-specialist-agent
        let lastAgent = manifest.agents.last
        XCTAssertEqual(lastAgent?.id, "custom-specialist-agent")
    }

    func testDirectoryHealthAgentCountMatchesAgentArray() async throws {
        createAgentsDir()
        writeFile("---\nname: Agent One\n---\n", named: "agent-one.md", in: agentsDir())
        writeFile("---\nname: Agent Two\n---\n", named: "agent-two.md", in: agentsDir())

        let manifest = try await sut.loadManifest(from: tempClaudeDir)
        XCTAssertEqual(manifest.directoryHealth.agentCount, manifest.agents.count)
        XCTAssertEqual(manifest.directoryHealth.agentCount, 2)
    }

    // MARK: - Command Parsing

    func testParsesCommandsFromMdFiles() async throws {
        createCommandsDir()
        writeFile(
            "---\ndescription: \"Build the current epic\"\n---\n",
            named: "build.md",
            in: commandsDir()
        )
        writeFile(
            "---\ndescription: \"Run QA checks\"\n---\n",
            named: "qa.md",
            in: commandsDir()
        )

        let manifest = try await sut.loadManifest(from: tempClaudeDir)

        XCTAssertEqual(manifest.commands.count, 2)
        let ids = manifest.commands.map(\.id)
        XCTAssertTrue(ids.contains("build"))
        XCTAssertTrue(ids.contains("qa"))
        // Names should have slash prefix
        XCTAssertTrue(manifest.commands.map(\.name).contains("/build"))
        XCTAssertTrue(manifest.commands.map(\.name).contains("/qa"))
    }

    func testCommandDescriptionStripsQuotes() async throws {
        createCommandsDir()
        writeFile(
            "---\ndescription: \"Run the QA agent\"\n---\n",
            named: "qa.md",
            in: commandsDir()
        )

        let manifest = try await sut.loadManifest(from: tempClaudeDir)
        let cmd = try XCTUnwrap(manifest.commands.first { $0.id == "qa" })
        XCTAssertEqual(cmd.description, "Run the QA agent")
    }

    func testDirectoryHealthCommandCountMatchesCommandArray() async throws {
        createCommandsDir()
        writeFile("---\n---\n", named: "cmd-a.md", in: commandsDir())
        writeFile("---\n---\n", named: "cmd-b.md", in: commandsDir())
        writeFile("---\n---\n", named: "cmd-c.md", in: commandsDir())

        let manifest = try await sut.loadManifest(from: tempClaudeDir)
        XCTAssertEqual(manifest.directoryHealth.commandCount, manifest.commands.count)
        XCTAssertEqual(manifest.directoryHealth.commandCount, 3)
    }

    // MARK: - Skill Parsing

    func testParsesSkillsFromSKILLMdFiles() async throws {
        createSkillDir(named: "design-system")
        createSkillDir(named: "xcode-mcp")

        let manifest = try await sut.loadManifest(from: tempClaudeDir)

        XCTAssertEqual(manifest.skills.count, 2)
        let categories = manifest.skills.map(\.category)
        XCTAssertTrue(categories.contains("design-system"))
        XCTAssertTrue(categories.contains("xcode-mcp"))
    }

    func testSkillNameIsHumanizedFromCategory() async throws {
        createSkillDir(named: "design-system")

        let manifest = try await sut.loadManifest(from: tempClaudeDir)
        let skill = try XCTUnwrap(manifest.skills.first { $0.id == "design-system" })
        XCTAssertEqual(skill.name, "Design System")
    }

    func testDirectoryHealthSkillCountMatchesSkillArray() async throws {
        createSkillDir(named: "skill-a")
        createSkillDir(named: "skill-b")

        let manifest = try await sut.loadManifest(from: tempClaudeDir)
        XCTAssertEqual(manifest.directoryHealth.skillCount, manifest.skills.count)
        XCTAssertEqual(manifest.directoryHealth.skillCount, 2)
    }

    // MARK: - Rule Parsing

    func testParsesRulesRecursively() async throws {
        createRuleFile(named: "git-workflow.md", scope: "workflow")
        createRuleFile(named: "task-hygiene.md", scope: "global")

        let manifest = try await sut.loadManifest(from: tempClaudeDir)

        XCTAssertEqual(manifest.rules.count, 2)
        let ids = manifest.rules.map(\.id)
        XCTAssertTrue(ids.contains("git-workflow"))
        XCTAssertTrue(ids.contains("task-hygiene"))
    }

    func testRuleNameIsHumanizedFromFilename() async throws {
        createRuleFile(named: "git-workflow.md", scope: "workflow")

        let manifest = try await sut.loadManifest(from: tempClaudeDir)
        let rule = try XCTUnwrap(manifest.rules.first { $0.id == "git-workflow" })
        XCTAssertEqual(rule.name, "Git Workflow")
        XCTAssertEqual(rule.scope, "workflow")
    }

    func testDirectoryHealthRuleCountMatchesRuleArray() async throws {
        createRuleFile(named: "rule-a.md", scope: "global")
        createRuleFile(named: "rule-b.md", scope: "workflow")
        createRuleFile(named: "rule-c.md", scope: "global")

        let manifest = try await sut.loadManifest(from: tempClaudeDir)
        XCTAssertEqual(manifest.directoryHealth.ruleCount, manifest.rules.count)
        XCTAssertEqual(manifest.directoryHealth.ruleCount, 3)
    }

    // MARK: - Workflow Pipelines

    func testWorkflowPipelinesAreAlwaysPresent() async throws {
        let manifest = try await sut.loadManifest(from: tempClaudeDir)
        XCTAssertFalse(manifest.workflowPipelines.isEmpty, "Hardcoded pipelines should always be returned")
        let ids = manifest.workflowPipelines.map(\.id)
        XCTAssertTrue(ids.contains("task-pipeline"))
        XCTAssertTrue(ids.contains("story-pipeline"))
        XCTAssertTrue(ids.contains("epic-pipeline"))
    }

    // MARK: - Protocol Interface

    func testManifestServiceConformsToProtocol() {
        // Verifies that ManifestService satisfies ManifestServiceProtocol
        // This is a compile-time check; if ManifestService breaks the protocol the build fails.
        let service: any ManifestServiceProtocol = ManifestService()
        XCTAssertNotNil(service)
    }

    func testMockConformsToProtocol() {
        let mock: any ManifestServiceProtocol = MockManifestService()
        XCTAssertNotNil(mock)
    }

    // MARK: - MockManifestService Behavior

    func testMockTracksCallCount() async throws {
        let mock = MockManifestService()
        XCTAssertEqual(mock.loadManifestCallCount, 0)

        _ = try await mock.loadManifest(from: tempClaudeDir)
        XCTAssertEqual(mock.loadManifestCallCount, 1)

        _ = try await mock.loadManifest(from: tempClaudeDir)
        XCTAssertEqual(mock.loadManifestCallCount, 2)
    }

    func testMockRecordsLastClaudeDir() async throws {
        let mock = MockManifestService()
        _ = try await mock.loadManifest(from: tempClaudeDir)
        XCTAssertEqual(mock.lastClaudeDir, tempClaudeDir)
    }

    func testMockThrowsConfiguredError() async {
        let mock = MockManifestService()
        mock.setError(ManifestError.directoryNotFound)

        do {
            _ = try await mock.loadManifest(from: tempClaudeDir)
            XCTFail("Expected error to be thrown")
        } catch ManifestError.directoryNotFound {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMockReturnsConfiguredManifest() async throws {
        let mock = MockManifestService()
        let customManifest = AgentManifest(
            agents: [],
            commands: [],
            skills: [],
            rules: [],
            directoryHealth: DirectoryHealth(agentCount: 42, commandCount: 7, skillCount: 3, ruleCount: 5),
            generatedAt: "2026-01-01T00:00:00Z",
            workflowPipelines: []
        )
        mock.setManifest(customManifest)

        let result = try await mock.loadManifest(from: tempClaudeDir)
        XCTAssertEqual(result.directoryHealth.agentCount, 42)
        XCTAssertEqual(result.generatedAt, "2026-01-01T00:00:00Z")
    }

    func testMockResetCallTrackingPreservesResult() async throws {
        let mock = MockManifestService()
        _ = try await mock.loadManifest(from: tempClaudeDir)
        mock.resetCallTracking()

        XCTAssertEqual(mock.loadManifestCallCount, 0)
        XCTAssertNil(mock.lastClaudeDir)

        // Result is still configured
        _ = try await mock.loadManifest(from: tempClaudeDir)
        XCTAssertEqual(mock.loadManifestCallCount, 1)
    }

    // MARK: - Private Helpers

    private func agentsDir() -> URL {
        tempClaudeDir.appendingPathComponent("agents", isDirectory: true)
    }

    private func commandsDir() -> URL {
        tempClaudeDir.appendingPathComponent("commands", isDirectory: true)
    }

    private func createAgentsDir() {
        try? fileManager.createDirectory(at: agentsDir(), withIntermediateDirectories: true)
    }

    private func createCommandsDir() {
        try? fileManager.createDirectory(at: commandsDir(), withIntermediateDirectories: true)
    }

    private func createSkillDir(named name: String) {
        let skillDir = tempClaudeDir
            .appendingPathComponent("skills", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try? fileManager.createDirectory(at: skillDir, withIntermediateDirectories: true)
        writeFile("# \(name) Skill\n", named: "SKILL.md", in: skillDir)
    }

    private func createRuleFile(named name: String, scope: String) {
        let scopeDir = tempClaudeDir
            .appendingPathComponent("rules", isDirectory: true)
            .appendingPathComponent(scope, isDirectory: true)
        try? fileManager.createDirectory(at: scopeDir, withIntermediateDirectories: true)
        writeFile("# Rule: \(name)\n", named: name, in: scopeDir)
    }

    private func writeFile(_ content: String, named name: String, in directory: URL) {
        let url = directory.appendingPathComponent(name)
        try? content.data(using: .utf8)?.write(to: url)
    }
}
