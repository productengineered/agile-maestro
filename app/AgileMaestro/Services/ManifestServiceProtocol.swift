import Foundation

/// Protocol defining manifest loading operations for the agent team roster.
///
/// Conforming types scan the `.claude/` directory tree using `FileManager`,
/// parse agent/command/skill/rule files, and construct an `AgentManifest`
/// without any external dependencies.
protocol ManifestServiceProtocol: Sendable {

    /// Loads the agent manifest for a given `.claude/` directory.
    ///
    /// Scans the directory tree with `FileManager`, parses agent `.md` front matter,
    /// counts commands/skills/rules, and assembles an `AgentManifest` inline.
    ///
    /// - Parameter claudeDir: Path to the project's `.claude/` directory.
    /// - Returns: `AgentManifest` containing agents, commands, skills, and rules.
    /// - Throws: `ManifestError` if the directory is not found.
    func loadManifest(from claudeDir: URL) async throws -> AgentManifest
}
