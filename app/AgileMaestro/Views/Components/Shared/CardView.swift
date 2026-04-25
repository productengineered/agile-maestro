import SwiftUI

// MARK: - CardView

/// Standard card container used across all tab views.
///
/// Background is `.ultraThinMaterial` — lighter than the `.regularMaterial`
/// used by the detail panel itself, providing visual layering and depth.
/// Accepts an optional title + icon header, then a generic `@ViewBuilder` content slot.
struct CardView<Content: View>: View {

    // MARK: - Properties

    let title: String?
    let icon: String?
    let iconColor: Color?
    let content: () -> Content

    // MARK: - Initializer

    init(
        title: String? = nil,
        icon: String? = nil,
        iconColor: Color? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.content = content
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title, !title.isEmpty {
                HStack(spacing: 8) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(iconColor ?? .secondary)
                            .symbolRenderingMode(.hierarchical)
                    }
                    Text(title)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
                .padding(.bottom, 12)
            }

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }
}

// MARK: - Preview

#Preview("With Title and Icon") {
    VStack(spacing: 12) {
        CardView(title: "Overview", icon: "doc.text", iconColor: .blue) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Status: In Progress")
                    .font(.body)
                Text("Priority: P1")
                    .font(.body)
            }
        }

        CardView(title: "No Icon") {
            Text("Content without an icon in the header.")
                .font(.body)
                .foregroundStyle(.secondary)
        }

        CardView {
            Text("Card with no title — content only.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
    .padding(20)
    .frame(width: 360)
    .background(Color(.windowBackgroundColor))
}
