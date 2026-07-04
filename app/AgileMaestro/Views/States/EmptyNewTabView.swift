import SwiftUI

// MARK: - EmptyNewTabView

/// Full-tab-content placeholder shown when a tab/window has no product
/// context yet (SM-EMPTY-800-T1, `ProductWindowIdentity.empty` sentinel case).
///
/// Reuses the `ContentUnavailableView` pattern from `EmptyStateView`, with a
/// "Choose a Product" action — the CTA `EmptyStateView` intentionally omits
/// (there, toolbar chips are the entry point; here, on a brand-new tab, there
/// is no existing product chip to point the user at yet). This is a NEW file,
/// a sibling to `EmptyStateView` — `EmptyStateView` itself is unmodified and
/// still used for the existing "no session selected within an already-loaded
/// product" case (out of scope for this epic).
///
/// Replaces the AM-803-1 placeholder (`EmptyProductTabPlaceholderView`) with
/// the full SCR-EMPTY experience: `planning/design/empty-new-tab-spec.md`.
struct EmptyNewTabView: View {
    let products: [Product]
    let staleProductIDs: Set<Product.ID>
    let onSelectProduct: (Product) -> Void
    let onNewProduct: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("No Product Open")
            } icon: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 48))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
        } description: {
            Text("Choose a product to load into this tab.")
                .font(.body)
                .foregroundStyle(.secondary)
        } actions: {
            // M-800-1: non-modal Menu — dismissible without selecting, per
            // design3 ("no forced modal"). Dismissing leaves this tab exactly
            // on SCR-EMPTY (SM-EMPTY-800-T5).
            Menu {
                ProductListMenuItems(
                    products: products,
                    selectedProductID: nil, // fresh tab — no current selection
                    staleProductIDs: staleProductIDs,
                    onSelect: onSelectProduct,
                    identifier: { AXID.EmptyTab.productRow($0.id.uuidString) }
                )

                if !products.isEmpty {
                    Divider()
                }

                Button {
                    onNewProduct()
                } label: {
                    Label("New Product...", systemImage: "plus")
                }
                .accessibilityIdentifier(AXID.EmptyTab.newProductMenuItem)
            } label: {
                Text("Choose a Product")
            }
            .menuStyle(.borderedButton)
            .controlSize(.large)
            .accessibilityLabel("Choose a product")
            .accessibilityHint("Opens a menu to select or create a product for this tab")
            .accessibilityIdentifier(AXID.EmptyTab.chooseProductButton)
        }
        .navigationTitle("New Tab")
    }
}

// MARK: - Preview

#Preview {
    EmptyNewTabView(
        products: [Product(name: "Sample Product")],
        staleProductIDs: [],
        onSelectProduct: { _ in },
        onNewProduct: {}
    )
    .frame(width: 800, height: 600)
}
