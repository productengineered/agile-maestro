import SwiftUI

// MARK: - ProductListMenuItems

/// Shared per-product `Button` list for `Menu` content, used both by
/// `ProductChipMenu`'s toolbar picker and `EmptyNewTabView`'s M-800-1
/// "Choose a Product" popover (empty-new-tab-spec.md).
///
/// Extracted from `ProductChipMenu`'s original inline `ForEach` so both call
/// sites share one implementation — including the AM-600 stale-directory
/// indicator per product row. This extraction MUST NOT change
/// `ProductChipMenu`'s observable behavior (same menu items, same order,
/// same accessibility/help text).
///
/// Staleness is passed in as a `Set<Product.ID>` (matching
/// `SessionViewModel.staleProductIDs`) rather than a `Product.isStale`
/// property — `Product` has no such stored/computed property, and adding one
/// would duplicate the staleness detection that already lives on
/// `SessionViewModel.checkProductStaleness()`.
struct ProductListMenuItems: View {
    let products: [Product]
    let selectedProductID: Product.ID?
    let staleProductIDs: Set<Product.ID>
    let onSelect: (Product) -> Void

    /// Generates the accessibility identifier for a given product's row.
    /// Each call site supplies its own `AXID` namespace (the same list is
    /// rendered in two different screens: the toolbar chip and the empty-tab
    /// CTA), so this view stays decoupled from either screen's naming.
    let identifier: (Product) -> String

    var body: some View {
        ForEach(products) { product in
            let isSelected = product.id == selectedProductID
            let isStale = staleProductIDs.contains(product.id)
            Button {
                onSelect(product)
            } label: {
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
            .help(isStale ? "Session directory not found" : "")
            .accessibilityIdentifier(identifier(product))
        }
    }
}
