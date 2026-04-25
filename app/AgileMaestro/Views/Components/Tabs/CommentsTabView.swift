import SwiftUI

// MARK: - CommentFilterType

/// Filter mode for the comment feed.
///
/// Extensible to .implementation, .review in future iterations.
enum CommentFilterType: String, CaseIterable {
    case all
    case rejection

    var label: String {
        switch self {
        case .all: return "All"
        case .rejection: return "Rejections"
        }
    }

    /// Comment `type` values shown when this filter is active.
    var matchedTypes: Set<String>? {
        switch self {
        case .all: return nil   // nil = show everything
        case .rejection: return ["rejection", "fix"]
        }
    }
}

// MARK: - CommentsTabView (All item types)

/// Chronological comment activity feed.
///
/// Displays a LazyVStack of CommentCardRow views, each showing:
/// - AgentAvatarView (24pt) for author identity
/// - Author name, relative timestamp, type badge (12 colors)
/// - Selectable comment content
/// - UNRESOLVED badge for rejection comments where resolved == false
///
/// Filter bar: "All" | "Rejections" pill toggle above the list.
/// When Rejections is active, only rejection + fix comments are shown.
///
/// Empty state: ContentUnavailableView with text.bubble icon. (ERR-DETAIL-002)
/// Filtered-empty state: ContentUnavailableView (ERR-DP700-006)
/// Staggered reveal animation on tab load: 0.04s per-card delay.
struct CommentsTabView: View {
    let task: TaskItem

    @State private var isVisible = false
    @State private var commentFilter: CommentFilterType = .all

    private var allComments: [Comment] { task.comments }

    private var filteredComments: [Comment] {
        guard let matchedTypes = commentFilter.matchedTypes else {
            return allComments
        }
        return allComments.filter { comment in
            guard let type = comment.type?.lowercased() else { return false }
            return matchedTypes.contains(type)
        }
    }

    private var rejectionCount: Int {
        allComments.filter { comment in
            guard let type = comment.type?.lowercased() else { return false }
            return ["rejection", "fix"].contains(type)
        }.count
    }

    var body: some View {
        if allComments.isEmpty {
            // ERR-DETAIL-002: No comments at all
            ContentUnavailableView(
                "No Comments",
                systemImage: "text.bubble",
                description: Text("This item has no comments yet.")
            )
        } else {
            VStack(alignment: .leading, spacing: 12) {
                // Header: "Comments" label + count badge
                commentsHeader

                // Filter chip row (SM-DP700-COMMENTS-005)
                CommentTypeFilterBar(
                    selectedFilter: $commentFilter,
                    rejectionCount: rejectionCount
                )

                // ERR-DP700-006: filtered results are empty
                if filteredComments.isEmpty {
                    ContentUnavailableView(
                        "No Rejections",
                        systemImage: "checkmark.circle",
                        description: Text("No rejection or fix comments found.")
                    )
                    .transition(.opacity)
                } else {
                    // Comment cards with staggered reveal animation
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(filteredComments.enumerated()), id: \.element.id) { index, comment in
                            CommentCardRow(comment: comment)
                                .opacity(isVisible ? 1 : 0)
                                .offset(y: isVisible ? 0 : -8)
                                .animation(
                                    .easeOut(duration: 0.25).delay(Double(index) * 0.04),
                                    value: isVisible
                                )
                        }
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: commentFilter)
            .onAppear {
                isVisible = true
            }
            .onDisappear {
                isVisible = false
            }
            .onChange(of: task.id) {
                // Reset filter to .all on task change (SM-DP700-COMMENTS-005)
                commentFilter = .all
            }
        }
    }

    // MARK: - Header

    private var commentsHeader: some View {
        HStack(spacing: 6) {
            Text("Comments")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            Text("\(allComments.count)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.10), in: Capsule())

            Spacer()
        }
        .padding(.bottom, 4)
    }
}

// MARK: - CommentTypeFilterBar

/// Horizontal row of filter pill chips for the comment feed.
///
/// Active chip: accent background, primary foreground.
/// Inactive chip: secondary.opacity(0.12) background, secondary foreground.
/// Rejections chip includes count badge: "Rejections (3)".
private struct CommentTypeFilterBar: View {
    @Binding var selectedFilter: CommentFilterType
    let rejectionCount: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(CommentFilterType.allCases, id: \.rawValue) { filter in
                filterChip(for: filter)
            }
            Spacer()
        }
    }

    private func filterChip(for filter: CommentFilterType) -> some View {
        let isSelected = selectedFilter == filter
        let chipLabel = chipTitle(for: filter)

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedFilter = filter
            }
        } label: {
            Text(chipLabel)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    isSelected
                        ? Color.accentColor
                        : Color.secondary.opacity(0.12),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(chipLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func chipTitle(for filter: CommentFilterType) -> String {
        switch filter {
        case .all:
            return filter.label
        case .rejection:
            return rejectionCount > 0
                ? "\(filter.label) (\(rejectionCount))"
                : filter.label
        }
    }
}

// MARK: - Comment Type Info

/// Maps a comment type string to a (display label, badge color) pair.
///
/// 12 explicit types per spec. ERR-DETAIL-006: unknown types fall back to gray
/// with the raw type string as the label.
private struct CommentTypeInfo {
    let label: String
    let color: Color

    // Dictionary lookup avoids a high-complexity switch statement.
    // swiftlint:disable colon comma
    private static let map: [String: CommentTypeInfo] = [
        "note":           CommentTypeInfo(label: "note",           color: .gray),
        "implementation": CommentTypeInfo(label: "implementation", color: .teal),
        "testing":        CommentTypeInfo(label: "testing",        color: .green),
        "review":         CommentTypeInfo(label: "review",         color: .purple),
        "rejection":      CommentTypeInfo(label: "rejection",      color: .red),
        "fix":            CommentTypeInfo(label: "fix",            color: .cyan),
        "handoff":        CommentTypeInfo(label: "handoff",        color: .indigo),
        "planning":       CommentTypeInfo(label: "planning",       color: .blue),
        "question":       CommentTypeInfo(label: "question",       color: .orange),
        "decision":       CommentTypeInfo(label: "decision",       color: .green),
        "blocker":        CommentTypeInfo(label: "blocker",        color: .red),
        "deployment":     CommentTypeInfo(label: "deployment",     color: .mint)
    ]
    // swiftlint:enable colon comma

    static func resolve(_ type: String?) -> CommentTypeInfo {
        let key = type?.lowercased() ?? "note"
        return map[key] ?? CommentTypeInfo(label: type ?? "note", color: .gray)
    }
}

// MARK: - CommentCardRow

/// Single comment card in the comments feed.
///
/// Layout: AgentAvatarView (left column) + VStack (right column).
/// Right column: author + timestamp + type badge header, content text,
/// optional UNRESOLVED badge for unresolved rejections.
///
/// Accessibility: combined element. (Section 8, UX flows)
private struct CommentCardRow: View {
    let comment: Comment

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Left column: agent avatar (24pt per task spec)
            AgentAvatarView(author: comment.author, size: 24)

            // Right column: header + content + optional unresolved badge
            VStack(alignment: .leading, spacing: 6) {
                headerRow
                contentText
                unresolvedBadge
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        // Section 8: combine row for VoiceOver
        .accessibilityElement(children: .combine)
        .accessibilityLabel(combinedAccessibilityLabel)
    }

    // MARK: - Sub-views

    private var headerRow: some View {
        HStack(spacing: 6) {
            Text(displayAuthor)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            Spacer()

            // Relative timestamp (live-updating via SwiftUI Text date style)
            if let timestamp = comment.timestamp {
                Text(timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Type badge capsule (12 color set per spec)
            commentTypeBadge
        }
    }

    @ViewBuilder
    private var contentText: some View {
        if let content = comment.content, !content.isEmpty {
            Text(verbatim: content)
                .font(.callout)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
    }

    @ViewBuilder
    private var unresolvedBadge: some View {
        // UNRESOLVED badge: rejection comments with resolved != true
        if comment.type?.lowercased() == "rejection" && comment.resolved != true {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
                    .symbolRenderingMode(.monochrome)
                Text("UNRESOLVED")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.orange)
                    .tracking(0.5)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.orange.opacity(0.12), in: Capsule())
            .accessibilityLabel("Unresolved rejection")
        }
    }

    private var commentTypeBadge: some View {
        let info = CommentTypeInfo.resolve(comment.type)
        return Text(info.label)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(info.color)
            .tracking(0.3)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(info.color.opacity(0.15), in: Capsule())
    }

    // MARK: - Computed Labels

    /// Strips "-agent" suffix and capitalizes for display.
    /// e.g. "macos-developer-agent" → "Macos Developer"
    private var displayAuthor: String {
        (comment.author ?? "Unknown")
            .replacingOccurrences(of: "-agent", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    private var combinedAccessibilityLabel: String {
        let type = comment.type ?? "note"
        let content = comment.content ?? ""
        let unresolvedSuffix = (comment.type?.lowercased() == "rejection" && comment.resolved != true)
            ? ", unresolved"
            : ""
        return "\(displayAuthor), \(timestampAccessibilityLabel), \(type)\(unresolvedSuffix), \(content)"
    }

    /// Relative timestamp string for accessibility label.
    private var timestampAccessibilityLabel: String {
        guard let ts = comment.timestamp else { return "unknown time" }
        return Self.relativeDateFormatter.localizedString(for: ts, relativeTo: Date())
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt
    }()
}

// MARK: - Preview

#Preview("CommentsTabView - With Comments") {
    ScrollView {
        CommentsTabView(task: CommentsPreviewFactory.makeTask(withComments: true))
            .padding(16)
    }
    .frame(width: 500, height: 700)
}

#Preview("CommentsTabView - Empty") {
    ScrollView {
        CommentsTabView(task: CommentsPreviewFactory.makeTask(withComments: false))
            .padding(16)
    }
    .frame(width: 500, height: 300)
}

// MARK: - Preview Factory

private enum CommentsPreviewFactory {
    static func makeTask(withComments: Bool) -> TaskItem {
        let commentsJSON = withComments ? sampleCommentsJSON : "[]"
        let json = taskJSON(commentsJSON: commentsJSON)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // swiftlint:disable:next force_try
        return try! decoder.decode(TaskItem.self, from: Data(json.utf8))
    }

    private static var sampleCommentsJSON: String {
        """
        [
          {
            "id": "C1",
            "timestamp": "2026-01-15T09:00:00Z",
            "author": "macos-developer-agent",
            "type": "note",
            "content": "STARTING: Implementing CommentsTabView.",
            "resolved": null
          },
          {
            "id": "C2",
            "timestamp": "2026-01-15T10:30:00Z",
            "author": "macos-developer-agent",
            "type": "implementation",
            "content": "Implemented LazyVStack with 12 type colors and UNRESOLVED badge.",
            "resolved": null
          },
          {
            "id": "C3",
            "timestamp": "2026-01-16T14:00:00Z",
            "author": "staff-engineer-agent",
            "type": "rejection",
            "content": "REJECTED: Missing accessibility labels on avatar views.",
            "resolved": false
          },
          {
            "id": "C4",
            "timestamp": "2026-01-16T16:00:00Z",
            "author": "qa-agent",
            "type": "testing",
            "content": "QA PASSED: All 12 type colors verified.",
            "resolved": null
          },
          {
            "id": "C5",
            "timestamp": "2026-01-17T09:00:00Z",
            "author": "pm-agent",
            "type": "review",
            "content": "PRODUCT REVIEW PASSED: Requirements met.",
            "resolved": null
          },
          {
            "id": "C6",
            "timestamp": "2026-01-17T10:00:00Z",
            "author": "macos-developer-agent",
            "type": "fix",
            "content": "FIXED: Added accessibilityLabel to all AgentAvatarView instances.",
            "resolved": null
          }
        ]
        """
    }

    private static func taskJSON(commentsJSON: String) -> String {
        """
        {
          "id": "preview-task-comments",
          "subject": "Preview Task for CommentsTabView",
          "description": "A preview task demonstrating CommentsTabView.",
          "status": "in_progress",
          "blocks": [],
          "blockedBy": [],
          "metadata": {
            "schema_version": "2.0",
            "type": "task",
            "priority": "P2",
            "approval": "approved",
            "blocked": false,
            "checklist": [],
            "local_checks": ["Build passes"],
            "completion_signal": "All checks verified",
            "comments": \(commentsJSON)
          }
        }
        """
    }
}
