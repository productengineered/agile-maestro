import Foundation

/// Git branch and PR information for a story or epic.
///
/// Note: Defined for backward compatibility with v1.0 task data.
/// Removed from StoryMetadata in v2.0 schema.
struct GitInfo: Codable {
    let branch: String?
    let worktree: String?
    let prUrl: String?
    let baseBranch: String?

    enum CodingKeys: String, CodingKey {
        case branch
        case worktree
        case prUrl = "pr_url"
        case baseBranch = "base_branch"
    }
}
