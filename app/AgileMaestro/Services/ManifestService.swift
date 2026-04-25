import Foundation
import OSLog

// MARK: - ManifestError

/// Errors thrown by `ManifestService.loadManifest(from:)`.
enum ManifestError: Error, LocalizedError {
    /// The `.claude/` directory was not found at the given path.
    case directoryNotFound
    /// The output JSON could not be decoded into `AgentManifest`.
    case decodeFailed(Error)

    var errorDescription: String? {
        switch self {
        case .directoryNotFound:
            return "The .claude/ directory was not found at the given path."
        case .decodeFailed(let underlying):
            return "Failed to decode manifest: \(underlying.localizedDescription)"
        }
    }
}

// MARK: - ManifestService

/// Parses the `.claude/` directory using FileManager to build an `AgentManifest`.
///
/// Declared as an `actor` to serialise concurrent `loadManifest` calls and protect
/// mutable internal state (none currently, but the actor boundary ensures forward
/// compatibility as caching is added in a future phase).
actor ManifestService: ManifestServiceProtocol {

    // MARK: - Singleton

    static let shared = ManifestService()

    // MARK: - Private Properties

    private let logger = Logger.manifest
    private let fileManager = FileManager.default

    // MARK: - ManifestServiceProtocol

    func loadManifest(from claudeDir: URL) async throws -> AgentManifest {
        // 1. Verify the .claude/ directory exists.
        let claudePath = claudeDir.path(percentEncoded: false)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: claudePath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            logger.error("Claude directory not found at \(claudePath)")
            throw ManifestError.directoryNotFound
        }

        // 2. Parse agents, commands, skills, and rules concurrently.
        //    Each parse* call does synchronous FileManager I/O, so we run each
        //    on a detached background task to avoid blocking cooperative threads.
        async let agents = Task.detached(priority: .background) { [self] in
            await self.parseAgents(in: claudeDir)
        }.value
        async let commands = Task.detached(priority: .background) { [self] in
            await self.parseCommands(in: claudeDir)
        }.value
        async let skills = Task.detached(priority: .background) { [self] in
            await self.parseSkills(in: claudeDir)
        }.value
        async let rules = Task.detached(priority: .background) { [self] in
            await self.parseRules(in: claudeDir)
        }.value

        let (parsedAgents, parsedCommands, parsedSkills, parsedRules) =
            await (agents, commands, skills, rules)

        // 3. Build DirectoryHealth.
        let health = DirectoryHealth(
            agentCount: parsedAgents.count,
            commandCount: parsedCommands.count,
            skillCount: parsedSkills.count,
            ruleCount: parsedRules.count
        )

        // 4. Build hardcoded WorkflowPipeline matching the review cycle.
        let pipelines = buildWorkflowPipelines()

        // 5. Build the timestamp.
        let iso8601 = ISO8601DateFormatter()
        let generatedAt = iso8601.string(from: Date())

        logger.info(
            """
            Loaded manifest: \(parsedAgents.count) agent(s), \(parsedCommands.count) command(s), \
            \(parsedSkills.count) skill(s), \(parsedRules.count) rule(s)
            """
        )

        return AgentManifest(
            agents: parsedAgents,
            commands: parsedCommands,
            skills: parsedSkills,
            rules: parsedRules,
            directoryHealth: health,
            generatedAt: generatedAt,
            workflowPipelines: pipelines
        )
    }

    // MARK: - Agent Parsing

    /// Scans `.claude/agents/*.md` and extracts `AgentInfo` from each file.
    private func parseAgents(in claudeDir: URL) -> [AgentInfo] {
        let agentsDir = claudeDir.appendingPathComponent("agents")
        guard let files = mdFiles(in: agentsDir) else { return [] }

        return files.compactMap { url in
            guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                logger.warning("Could not read agent file: \(url.lastPathComponent)")
                return nil
            }
            return parseAgentInfo(from: content, fileURL: url)
        }
        .sorted(by: AgentInfo.sortComparator)
    }

    /// Parses a single agent `.md` file into an `AgentInfo`.
    ///
    /// Expects YAML front matter delimited by `---` at the top of the file.
    /// Extracts `name`, `description`, `model`, `mcpServers`, `tools`, and `skills`
    /// from the front matter.
    private func parseAgentInfo(from content: String, fileURL: URL) -> AgentInfo {
        let filename = fileURL.deletingPathExtension().lastPathComponent
        let frontMatter = extractFrontMatter(from: content)

        let name = frontMatter["name"] ?? filename
        let description = frontMatter["description"]?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"")) ?? ""
        let model = frontMatter["model"] ?? "unknown"
        let mcpServers = parseStringArray(frontMatter["mcpServers"] ?? frontMatter["mcp_servers"])
        let tools = parseCommaSeparated(frontMatter["tools"])
        let skills = parseCommaSeparated(frontMatter["skills"])

        return AgentInfo(
            id: filename,
            name: name,
            model: model,
            description: description,
            skills: skills,
            displayName: nil,
            initials: nil,
            mcpServers: mcpServers,
            tools: tools,
            file: fileURL.lastPathComponent
        )
    }

    // MARK: - Command Parsing

    /// Scans `.claude/commands/*.md` and builds `CommandInfo` for each file.
    private func parseCommands(in claudeDir: URL) -> [CommandInfo] {
        let commandsDir = claudeDir.appendingPathComponent("commands")
        guard let files = mdFiles(in: commandsDir) else { return [] }

        return files.map { url in
            let filename = url.deletingPathExtension().lastPathComponent
            let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let frontMatter = extractFrontMatter(from: content)
            let description = frontMatter["description"] ?? ""
            return CommandInfo(
                id: filename,
                name: "/\(filename)",
                description: description.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            )
        }
        .sorted { $0.name < $1.name }
    }

    // MARK: - Skill Parsing

    /// Scans `.claude/skills/*/SKILL.md` and builds `SkillInfo` for each match.
    private func parseSkills(in claudeDir: URL) -> [SkillInfo] {
        let skillsDir = claudeDir.appendingPathComponent("skills")
        guard fileManager.fileExists(atPath: skillsDir.path(percentEncoded: false)) else { return [] }

        var skills: [SkillInfo] = []
        let enumerator = fileManager.enumerator(
            at: skillsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        while let url = enumerator?.nextObject() as? URL {
            guard url.lastPathComponent == "SKILL.md" else { continue }
            let category = url.deletingLastPathComponent().lastPathComponent
            skills.append(SkillInfo(
                id: category,
                name: category
                    .split(separator: "-")
                    .map { $0.capitalized }
                    .joined(separator: " "),
                category: category
            ))
        }
        return skills.sorted { $0.name < $1.name }
    }

    // MARK: - Rule Parsing

    /// Scans `.claude/rules/**/*.md` recursively and builds `RuleInfo` for each file.
    private func parseRules(in claudeDir: URL) -> [RuleInfo] {
        let rulesDir = claudeDir.appendingPathComponent("rules")
        guard fileManager.fileExists(atPath: rulesDir.path(percentEncoded: false)) else { return [] }

        var rules: [RuleInfo] = []
        let enumerator = fileManager.enumerator(
            at: rulesDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "md" else { continue }
            let filename = url.deletingPathExtension().lastPathComponent
            let scope = url.deletingLastPathComponent().lastPathComponent
            rules.append(RuleInfo(
                id: filename,
                name: filename
                    .split(separator: "-")
                    .map { $0.capitalized }
                    .joined(separator: " "),
                scope: scope
            ))
        }
        return rules.sorted { $0.name < $1.name }
    }

    // MARK: - Workflow Pipelines

    /// Returns hardcoded `WorkflowPipeline` data matching the project's review cycle.
    private func buildWorkflowPipelines() -> [WorkflowPipeline] {
        [taskPipeline(), storyPipeline(), epicPipeline()]
    }

    private func taskPipeline() -> WorkflowPipeline {
        WorkflowPipeline(
            id: "task-pipeline",
            label: "Task",
            stages: [
                WorkflowStageDefinition(id: "pending", name: "Pending", kind: .agent, agentName: nil),
                WorkflowStageDefinition(
                    id: "in-progress", name: "In Progress",
                    kind: .agent, agentName: "macos-developer-agent"),
                WorkflowStageDefinition(id: "completed", name: "Completed", kind: .agent, agentName: nil)
            ]
        )
    }

    private func storyPipeline() -> WorkflowPipeline {
        WorkflowPipeline(
            id: "story-pipeline",
            label: "Story / Bug / Tech Debt",
            stages: [
                WorkflowStageDefinition(
                    id: "dev", name: "Dev",
                    kind: .agent, agentName: "macos-developer-agent"),
                WorkflowStageDefinition(
                    id: "code-review", name: "Code Review",
                    kind: .agent, agentName: "staff-engineer-agent"),
                WorkflowStageDefinition(
                    id: "qa", name: "QA",
                    kind: .agent, agentName: "qa-agent"),
                WorkflowStageDefinition(
                    id: "product-review", name: "Product Review",
                    kind: .agent, agentName: "pm-agent"),
                WorkflowStageDefinition(id: "completed", name: "Completed", kind: .human, agentName: nil)
            ]
        )
    }

    private func epicPipeline() -> WorkflowPipeline {
        WorkflowPipeline(
            id: "epic-pipeline",
            label: "Epic",
            stages: [
                WorkflowStageDefinition(
                    id: "design", name: "Design",
                    kind: .agent, agentName: "designer-agent"),
                WorkflowStageDefinition(
                    id: "dev", name: "Dev",
                    kind: .agent, agentName: "macos-developer-agent"),
                WorkflowStageDefinition(
                    id: "code-review", name: "Code Review",
                    kind: .agent, agentName: "staff-engineer-agent"),
                WorkflowStageDefinition(
                    id: "qa", name: "QA",
                    kind: .agent, agentName: "qa-agent"),
                WorkflowStageDefinition(
                    id: "security", name: "Security Audit",
                    kind: .agent, agentName: "security-audit-agent"),
                WorkflowStageDefinition(
                    id: "product-review", name: "Product Review",
                    kind: .agent, agentName: "pm-agent"),
                WorkflowStageDefinition(id: "human-uat", name: "Human UAT", kind: .human, agentName: nil),
                WorkflowStageDefinition(id: "completed", name: "Completed", kind: .human, agentName: nil)
            ]
        )
    }

    // MARK: - Parsing Helpers

    /// Returns all `.md` files in the given directory (non-recursive).
    private func mdFiles(in directory: URL) -> [URL]? {
        guard fileManager.fileExists(atPath: directory.path(percentEncoded: false)) else { return nil }
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        return contents.filter { $0.pathExtension == "md" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Extracts YAML front matter from a markdown file.
    ///
    /// Parses the block between the first and second `---` delimiters.
    /// Returns a dictionary of key→value pairs. Values are not deeply parsed.
    private func extractFrontMatter(from content: String) -> [String: String] {
        let lines = content.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return [:]
        }

        // Limit scan to 50 lines to guard against malformed files with no closing `---`.
        let maxScanLines = 50

        var result: [String: String] = [:]
        var inFrontMatter = false
        var closingFound = false
        var scannedLines = 0

        for line in lines {
            scannedLines += 1
            if scannedLines > maxScanLines { break }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" {
                if !inFrontMatter {
                    inFrontMatter = true
                    continue
                } else {
                    closingFound = true
                    break
                }
            }
            guard inFrontMatter else { continue }

            // Split on first colon only.
            if let colonIndex = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[trimmed.startIndex..<colonIndex])
                    .trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: colonIndex)...])
                    .trimmingCharacters(in: .whitespaces)
                if !key.isEmpty {
                    result[key] = value
                }
            }
        }

        return closingFound ? result : [:]
    }

    /// Parses a YAML inline array like `["xcode", "peekaboo"]` into `[String]`.
    /// Returns `nil` if the value is empty or absent.
    private func parseStringArray(_ value: String?) -> [String]? {
        guard let value, !value.isEmpty else { return nil }
        let stripped = value
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let items = stripped
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
            .filter { !$0.isEmpty }
        return items.isEmpty ? nil : items
    }

    /// Parses a comma-separated value string into `[String]`.
    private func parseCommaSeparated(_ value: String?) -> [String] {
        guard let value, !value.isEmpty else { return [] }
        return value
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
