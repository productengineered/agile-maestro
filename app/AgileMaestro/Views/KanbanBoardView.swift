import SwiftUI

// MARK: - KanbanBoardView

/// Full Kanban board — filter bar above a horizontally scrolling column layout.
///
/// Rendered when `selectedViewMode == .kanban` in `MainWindowView`. Fills the entire
/// content area (no sidebar, no detail panel). Data is read from
/// `@Environment(KanbanViewModel.self)`.
///
/// Layout: filter bar (`.bar` material) at top, divider, then `ScrollView(.horizontal)`
/// containing an `HStack` of `KanbanColumnView` instances. The security, agent-UAT, and
/// human-UAT columns are only shown when at least one epic is present in the session.
struct KanbanBoardView: View {
    @Environment(KanbanViewModel.self) private var kanbanViewModel

    // Callback: card tap → navigate to task in tree detail.
    // Provided by MainWindowView which controls selectedViewMode and selectedTask.
    // Default no-op allows use without wiring (AM-404 adds the real callback).
    var onSelectTask: (TaskItem) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Filter Bar
            // .bar material: matches system toolbar aesthetic.
            // Sits above scroll content as a persistent header strip.
            KanbanFilterBarView(
                typeFilter: Bindable(kanbanViewModel).typeFilter,
                epicFilter: Bindable(kanbanViewModel).epicFilter,
                filteredCount: kanbanViewModel.filteredCount,
                totalCount: kanbanViewModel.allCards.count,
                availableEpicIDs: kanbanViewModel.availableEpicIDs
            )
            .background(.bar)

            Divider()

            // MARK: Board Content
            // Board is always rendered (no loading state — data transform is synchronous).
            // Empty state: columns render with "No items" individually.
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(visibleColumns) { column in
                        KanbanColumnView(
                            column: column,
                            cards: kanbanViewModel.cards(for: column.id),
                            onSelect: onSelectTask
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            // Soft edge fade at horizontal edges to indicate overflow content
            .scrollEdgeEffectStyle(.soft, for: .leading)
            .scrollEdgeEffectStyle(.soft, for: .trailing)
            .accessibilityLabel("Kanban board")
            .accessibilityHint("Scroll horizontally to see all columns")
            // NSAccessibility.Role.scrollArea is assigned automatically by SwiftUI's ScrollView
            // on macOS. There is no .accessibilityRole() modifier in SwiftUI — the spec table
            // lists the AppKit role for documentation purposes only.
        }
        .frame(minWidth: 800, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Visible Columns
    // Security, Agent UAT, and Human UAT columns only appear when epic cards exist.
    // Otherwise default 7 columns: backlog, approved, in_dev, code_review, qa,
    // product_review, done. Gating logic lives in KanbanColumnDef.visibleColumns(hasEpicCards:)
    // so it is unit-testable without instantiating this View.
    private var visibleColumns: [KanbanColumnDef] {
        let hasEpicCards = kanbanViewModel.allCards.contains { $0.type == .epic }
        return KanbanColumnDef.visibleColumns(hasEpicCards: hasEpicCards)
    }
}

// MARK: - Previews

#Preview("Kanban Board — Empty") {
    let vm = KanbanViewModel()
    KanbanBoardView(onSelectTask: { _ in })
        .environment(vm)
        .frame(width: 1100, height: 700)
        .preferredColorScheme(.dark)
}

#Preview("Kanban Board — Light") {
    let vm = KanbanViewModel()
    KanbanBoardView(onSelectTask: { _ in })
        .environment(vm)
        .frame(width: 1100, height: 700)
        .preferredColorScheme(.light)
}
