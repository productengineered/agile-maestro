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
    @Environment(\.openWindow) private var openWindow

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
        ProductListMenuItems(
            products: viewModel.products,
            selectedProductID: viewModel.selectedProduct?.id,
            staleProductIDs: viewModel.staleProductIDs,
            onSelect: viewModel.selectProduct,
            identifier: { AXID.ProductChipMenu.productRow($0.id.uuidString) }
        )

        if !viewModel.products.isEmpty {
            // IS-TAB-OPEN-800-1: open a product in a new tab instead of
            // switching the current one. Native openWindow(value:) dedup
            // (research-window-tabbing.md Claim 1) means choosing a product
            // already open elsewhere focuses that tab rather than creating a
            // duplicate — no extra dedup logic needed here.
            Menu("Open in New Tab") {
                ForEach(viewModel.products) { product in
                    Button {
                        openWindow(value: ProductWindowIdentity.product(product.id))
                    } label: {
                        Text(product.name)
                    }
                    .accessibilityIdentifier(AXID.ProductChipMenu.openInNewTabRow(product.id.uuidString))
                }
            }
            .accessibilityIdentifier(AXID.ProductChipMenu.openInNewTabMenu)

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
