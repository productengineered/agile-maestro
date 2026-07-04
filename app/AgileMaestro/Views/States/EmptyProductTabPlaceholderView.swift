import SwiftUI

// MARK: - EmptyProductTabPlaceholderView

/// Minimal placeholder shown for a "New Tab" window/scene that has no product
/// selected yet (`ProductWindowIdentity.empty` sentinel case).
///
/// Intentionally minimal — the full SCR-EMPTY experience (product picker CTA,
/// recent products list, etc.) lands in task AM-803-2 ("Add open-in-new-tab flow
/// + empty new-tab CTA"). This view only exists so the value-based `WindowGroup`
/// scene has something to render for an empty tab in the meantime.
struct EmptyProductTabPlaceholderView: View {

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("New Tab")
            } icon: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 48))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
        } description: {
            Text("Choose a product to get started.")
        }
        .navigationTitle("New Tab")
    }
}

// MARK: - Preview

#Preview {
    EmptyProductTabPlaceholderView()
        .frame(width: 800, height: 600)
}
