import SwiftUI

// MARK: - ChromelessStyle

/// Custom `ButtonStyle` for toolbar chips (ProductChipMenu, SessionChipMenu, folder button).
///
/// Renders no background at rest. A capsule fill fades in on hover (opacity 0.10)
/// and darkens on press (opacity 0.15). Conforms to the macOS Tahoe Liquid Glass
/// toolbar aesthetic — transparent at rest, subtle when interactive.
struct ChromelessStyle: ButtonStyle {

    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule()
                    .fill(
                        configuration.isPressed
                            ? Color.secondary.opacity(0.15)
                            : isHovered
                                ? Color.secondary.opacity(0.10)
                                : Color.clear
                    )
                    .animation(.easeInOut(duration: 0.12), value: isHovered)
                    .animation(.easeInOut(duration: 0.08), value: configuration.isPressed)
            }
            .contentShape(Capsule())
            .onHover { hovered in
                isHovered = hovered
            }
    }
}
