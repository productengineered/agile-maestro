import SwiftUI

// MARK: - KanbanFilterBarView

/// Horizontal filter controls bar for the Kanban board.
///
/// Layout: `[Type Picker] [Epic Menu] [Spacer] [Item Count]`.
/// Background material is set by the parent `KanbanBoardView` — this view has none.
/// Uses a native segmented `Picker` for type filtering and a native `Menu` dropdown
/// for epic filtering. Item count shows "[N] items" or "[N] of [M] items" when a
/// filter is active.
struct KanbanFilterBarView: View {
    @Binding var typeFilter: KanbanTypeFilter
    @Binding var epicFilter: String?
    let filteredCount: Int
    let totalCount: Int
    let availableEpicIDs: [String]

    // MARK: - Computed

    private var isFiltered: Bool {
        typeFilter != .all || epicFilter != nil
    }

    private var countText: String {
        if isFiltered {
            return "\(filteredCount) of \(totalCount) items"
        } else {
            return "\(totalCount) items"
        }
    }

    private var epicMenuLabel: String {
        epicFilter ?? "All Epics"
    }

    var body: some View {
        HStack(spacing: 12) {
            // MARK: Type Filter — native segmented Picker
            // Picker options: All, Epics, Stories, Tasks, Bugs, TD
            // Single-select, always one active. Immediate update on tap.
            Picker("Filter by type", selection: $typeFilter) {
                ForEach(KanbanTypeFilter.allCases, id: \.self) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize() // size to intrinsic content width; never stretch or clip
            .accessibilityLabel("Filter by type")
            .accessibilityHint("Select to show only items of that type")

            // MARK: Epic Filter — native Menu dropdown
            // "All Epics" clears the filter (epicFilter = nil).
            // Disabled when no epics available.
            Menu {
                Button("All Epics") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        epicFilter = nil
                    }
                }

                if !availableEpicIDs.isEmpty {
                    Divider()

                    ForEach(availableEpicIDs, id: \.self) { epicId in
                        Button(epicId) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                epicFilter = epicId
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(epicMenuLabel)
                        .font(.callout)
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize() // size to intrinsic content width; never compress/overlap neighbors
            .disabled(availableEpicIDs.isEmpty && epicFilter == nil)
            .accessibilityLabel("Filter by epic, currently \(epicMenuLabel)")
            .accessibilityHint("Select to show only items from a specific epic")

            Spacer()

            // MARK: Item Count
            // Non-interactive. Shows total or filtered count.
            Text(countText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .accessibilityLabel(countText)
                .accessibilityAddTraits(.isStaticText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Previews

#Preview("Filter Bar — All") {
    KanbanFilterBarView(
        typeFilter: .constant(.all),
        epicFilter: .constant(nil),
        filteredCount: 42,
        totalCount: 42,
        availableEpicIDs: ["AM-300", "AM-400", "AM-500"]
    )
    .background(.bar)
    .frame(width: 900)
    .preferredColorScheme(.dark)
}

#Preview("Filter Bar — Filtered") {
    KanbanFilterBarView(
        typeFilter: .constant(.task),
        epicFilter: .constant("AM-400"),
        filteredCount: 8,
        totalCount: 42,
        availableEpicIDs: ["AM-300", "AM-400", "AM-500"]
    )
    .background(.bar)
    .frame(width: 900)
    .preferredColorScheme(.light)
}

#Preview("Filter Bar — No Epics") {
    KanbanFilterBarView(
        typeFilter: .constant(.all),
        epicFilter: .constant(nil),
        filteredCount: 0,
        totalCount: 0,
        availableEpicIDs: []
    )
    .background(.bar)
    .frame(width: 900)
}
