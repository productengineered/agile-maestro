import SwiftUI

// MARK: - FlowLayout

/// Wrapping horizontal layout for badge rows that don't fit on a single line.
///
/// Implements the `Layout` protocol (macOS 13+) to arrange children left-to-right,
/// wrapping to the next row when a child would exceed the container width.
/// Used in kanban cards (labels), agent roster (skills), and `OverviewTabView` label rows.
struct FlowLayout: Layout {
    var spacing: CGFloat

    init(spacing: CGFloat = 4) {
        self.spacing = spacing
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var realizedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                totalHeight += rowHeight + spacing
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            currentX += size.width + spacing
            realizedWidth = max(realizedWidth, currentX - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight

        let reportedWidth = proposal.width ?? realizedWidth
        return CGSize(width: reportedWidth, height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(size)
            )
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Preview

#Preview {
    let tags = [
        "infrastructure", "phase-1", "core-data", "ui", "viewmodel",
        "networking", "testing", "accessibility", "kanban", "detail-panel"
    ]

    FlowLayout(spacing: 6) {
        ForEach(tags, id: \.self) { tag in
            Text(tag)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12), in: Capsule())
        }
    }
    .padding(24)
    .frame(width: 320)
}
