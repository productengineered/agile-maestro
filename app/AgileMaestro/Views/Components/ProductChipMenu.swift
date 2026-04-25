import SwiftUI

// MARK: - ProductChipMenu

/// Toolbar chip showing the currently selected product.
///
/// Opens a dropdown `Menu` for product selection and management actions.
/// Placed in the `.navigation` (leading) toolbar group.
///
/// Management actions (New Product, Edit, Remove) use bindings from
/// `MainWindowView` that control sheet/alert presentation. The actions
/// themselves are phase-6 work; for now they surface the presentation state.
struct ProductChipMenu: View {

    @Environment(SessionViewModel.self) private var viewModel

    @Binding var showingNewProductSheet: Bool
    @Binding var showingEditProductSheet: Bool
    @Binding var showingDeleteAlert: Bool

    var body: some View {
        Menu {
            productListSection
            managementSection
        } label: {
            chipLabel
        }
        .menuStyle(.button)
        .buttonStyle(ChromelessStyle())
        .accessibilityLabel(
            viewModel.selectedProduct.map { "Product: \($0.name)" }
                ?? "No product selected"
        )
        .accessibilityHint("Opens product menu")
    }

    // MARK: - Private Subviews

    @ViewBuilder
    private var productListSection: some View {
        ForEach(viewModel.products) { product in
            Button {
                viewModel.selectProduct(product)
            } label: {
                let isSelected = viewModel.selectedProduct?.id == product.id
                let isStale = viewModel.staleProductIDs.contains(product.id)
                HStack {
                    if isSelected {
                        Label(product.name, systemImage: "checkmark")
                    } else {
                        Text(product.name)
                    }
                    if isStale {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle.fill")
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 12))
                            .accessibilityLabel("Directory not found")
                    }
                }
            }
            .help(viewModel.staleProductIDs.contains(product.id) ? "Session directory not found" : "")
        }

        if !viewModel.products.isEmpty {
            Divider()
        }
    }

    @ViewBuilder
    private var managementSection: some View {
        Button {
            showingNewProductSheet = true
        } label: {
            Label("New Product...", systemImage: "plus")
        }

        if let product = viewModel.selectedProduct {
            Button {
                showingEditProductSheet = true
            } label: {
                Label("Edit \(product.name)...", systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) {
                showingDeleteAlert = true
            } label: {
                Label("Remove Product", systemImage: "trash")
            }
        }
    }

    private var chipLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "tray.fill")
                .symbolRenderingMode(.hierarchical)
            Text(viewModel.selectedProduct?.name ?? "No Product")
                .foregroundStyle(viewModel.selectedProduct == nil ? .secondary : .primary)
                .lineLimit(1)
        }
    }
}
