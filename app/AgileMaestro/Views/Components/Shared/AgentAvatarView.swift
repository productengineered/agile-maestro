import SwiftUI

// MARK: - AgentAvatarView

/// Circular initials avatar for each of the 16 recognized agent types.
///
/// Derives a 2-letter abbreviation and a semantic color from the `author` string
/// via keyword matching (e.g., `"macos-developer-agent"` → `"DV"`, orange).
/// Unknown authors fall back to the first two characters and `accentColor`.
///
/// Size variants: 28pt for comment cards, 20pt for pipeline nodes.
struct AgentAvatarView: View {
    let author: String?  // Full author string, e.g. "macos-developer-agent"
    let size: CGFloat
    let isDecorative: Bool

    init(author: String?, size: CGFloat = 28, isDecorative: Bool = false) {
        self.author = author
        self.size = size
        self.isDecorative = isDecorative
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(avatarColor.opacity(0.20))
                .frame(width: size, height: size)

            Text(initials)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(avatarColor)
        }
        .accessibilityLabel("\(displayName) avatar")
        .accessibilityHidden(isDecorative)
    }

    // MARK: - Computed Properties

    private var initials: String {
        let key = authorKey
        return Self.agentColorMap[key]?.0 ?? String(key.prefix(2)).uppercased()
    }

    private var avatarColor: Color {
        let key = authorKey
        return Self.agentColorMap[key]?.1 ?? .accentColor
    }

    private var displayName: String {
        author?.replacingOccurrences(of: "-agent", with: "")
                .replacingOccurrences(of: "-", with: " ")
                .capitalized ?? "Unknown"
    }

    private var authorKey: String {
        // Normalize: strip "-agent" suffix, find keyword via contains matching.
        // Order matters — more specific keys must appear before broader ones.
        let raw = (author ?? "").lowercased()
        for key in Self.orderedKeys where raw.contains(key) {
            return key
        }
        return String(raw.prefix(2))
    }

    // Ordered for specificity — "macos-developer" before "developer", etc.
    private static let orderedKeys: [String] = [
        "macos-developer",
        "staff-engineer",
        "data-architect",
        "build-engineer",
        "documentation",
        "coordinator",
        "discovery",
        "security",
        "planning",
        "designer",
        "devops",
        "human",
        "test",
        "rca",
        "user",
        "qa",
        "pm"
    ]

    // MARK: - Agent Color Map (16 entries per FULL-INVENTORY Section 7.4)
    // (initials, color)
    private static let agentColorMap: [String: (String, Color)] = [
        "planning": ("PL", .indigo),
        "designer": ("DS", .pink),
        "macos-developer": ("DV", .orange),
        "staff-engineer": ("SE", .blue),
        "data-architect": ("DA", .teal),
        "qa": ("QA", .green),
        "pm": ("PM", .purple),
        "security": ("SC", .red),
        "build-engineer": ("BE", .gray),
        "documentation": ("DC", .mint),
        "rca": ("RC", .brown),
        "discovery": ("DI", .cyan),
        "coordinator": ("CO", .indigo),
        "user": ("HU", Color(.systemGray)),
        "human": ("HU", Color(.systemGray)),
        "devops": ("DO", .gray),
        "test": ("TS", .green)
    ]
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        HStack(spacing: 12) {
            AgentAvatarView(author: "macos-developer-agent", size: 28)
            AgentAvatarView(author: "staff-engineer-agent", size: 28)
            AgentAvatarView(author: "qa-agent", size: 28)
            AgentAvatarView(author: "pm-agent", size: 28)
            AgentAvatarView(author: "planning-agent", size: 28)
        }
        HStack(spacing: 12) {
            AgentAvatarView(author: "security-audit-agent", size: 20)
            AgentAvatarView(author: "build-engineer-agent", size: 20)
            AgentAvatarView(author: "data-architect-agent", size: 20)
            AgentAvatarView(author: "designer-agent", size: 20)
            AgentAvatarView(author: "unknown-agent", size: 20)
        }
    }
    .padding(24)
}
