import SwiftUI

// MARK: - CollapsibleCardView

/// Card with expand/collapse toggle.
///
/// Used for Description tab sections and Criteria accordion items.
/// The header row is always visible and tappable. The chevron rotates 90°
/// when expanded. Expand state is controlled via an external `@Binding` so
/// the parent view can manage single-expand behavior (one card open at a time).
///
/// - Note: `CollapsibleCardView` manages chevron animation internally.
///   The *parent* is responsible for resetting `isExpanded` on other siblings
///   when a new card is opened (single-expand pattern).
struct CollapsibleCardView<Content: View>: View {

    // MARK: - Properties

    let title: String
    let icon: String
    let iconColor: Color
    @Binding var isExpanded: Bool
    let content: () -> Content

    // MARK: - Initializer

    init(
        title: String,
        icon: String,
        iconColor: Color,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self._isExpanded = isExpanded
        self.content = content
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row — always visible, tappable to toggle expand state
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(iconColor)
                        .symbolRenderingMode(.hierarchical)

                    Text(title)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title), \(isExpanded ? "expanded" : "collapsed")")
            .accessibilityHint(isExpanded ? "Tap to collapse" : "Tap to expand")

            // Expanded content — fades in with opacity + scale transition
            if isExpanded {
                Divider()
                    .padding(.top, 12)
                    .padding(.bottom, 12)

                content()
                    .transition(.opacity.combined(with: .scale(scale: 0, anchor: .top)))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }
}

// MARK: - Preview

#Preview("Single-Expand Pattern") {
    struct PreviewWrapper: View {
        @State private var expandedIndex: Int? = 0

        var body: some View {
            VStack(spacing: 12) {
                ForEach(0..<3) { index in
                    CollapsibleCardView(
                        title: sectionTitle(for: index),
                        icon: sectionIcon(for: index),
                        iconColor: sectionColor(for: index),
                        isExpanded: Binding(
                            get: { expandedIndex == index },
                            set: { isNowExpanded in
                                expandedIndex = isNowExpanded ? index : nil
                            }
                        )
                    ) {
                        Text("Content for section \(index + 1). Detail information appears here when expanded.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(20)
            .frame(width: 360)
            .background(Color(.windowBackgroundColor))
        }

        private func sectionTitle(for index: Int) -> String {
            ["Description", "Acceptance Criteria", "Planning Notes"][index]
        }

        private func sectionIcon(for index: Int) -> String {
            ["doc.text", "checkmark.circle", "calendar"][index]
        }

        private func sectionColor(for index: Int) -> Color {
            [Color.blue, Color.green, Color.orange][index]
        }
    }

    return PreviewWrapper()
}
