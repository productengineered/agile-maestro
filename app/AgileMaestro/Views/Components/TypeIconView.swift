import SwiftUI

// MARK: - TypeIconView

/// Small SF Symbol icon representing a task type.
/// Decorative — always marked `.accessibilityHidden(true)` in parent row context.
///
/// Icon and color mapping per UI-SPEC 2.6:
/// - epic:     `mountain.2.fill` / `.indigo`
/// - story:    `book.fill`       / `.blue`
/// - task:     `checklist`       / `.green`
/// - bug:      `ladybug.fill`    / `.red`
/// - techdebt: `wrench.and.screwdriver.fill` / `.orange`
struct TypeIconView: View {
    let type: TaskType
    let size: CGFloat

    init(type: TaskType, size: CGFloat = 12) {
        self.type = type
        self.size = size
    }

    var body: some View {
        Image(systemName: type.treeIconName)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(typeColor)
            .symbolRenderingMode(typeRenderingMode)
            .frame(width: size + 2, height: size + 2)
    }

    // MARK: - Type Color (per UI-SPEC 2.6)

    private var typeColor: Color {
        switch type {
        case .epic:     return .indigo
        case .story:    return .blue
        case .task:     return .green
        case .bug:      return .red
        case .techdebt: return .orange
        }
    }

    // MARK: - Rendering Mode

    private var typeRenderingMode: SymbolRenderingMode {
        switch type {
        case .task:                                  return .hierarchical
        case .epic, .story, .bug, .techdebt:         return .monochrome
        }
    }
}

// MARK: - Preview

#Preview("TypeIconView — All Types") {
    VStack(alignment: .leading, spacing: 12) {
        ForEach(TaskType.allCases, id: \.self) { taskType in
            HStack(spacing: 8) {
                TypeIconView(type: taskType, size: 14)
                Text(taskType.displayName)
                    .font(.callout)
            }
        }
    }
    .padding()
}
