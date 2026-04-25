import AppKit
import os
import SwiftUI

// MARK: - ViewModel

/// Local ViewModel for EditProductSheet.
///
/// Owns form state per SM-EDIT-PRODUCT-002 and provides helper methods for
/// NSOpenPanel invocation (IS-SHEET-002) and Save-button enable logic (IS-SHEET-003).
@Observable
@MainActor
final class EditProductSheetViewModel {

    // MARK: - State Machine (SM-EDIT-PRODUCT-002)

    enum SheetState: Equatable {
        /// Sheet open; fields pre-filled from product; Save disabled (no changes yet).
        case loaded
        /// User has made at least one change; Save enabled.
        case dirty
        /// `viewModel.updateProduct(...)` in flight.
        case saving
        /// Save or delete failed; inline error shown.
        case error(String)
        /// `viewModel.removeProduct(...)` in flight.
        case deleting
        /// Sheet dismissed after successful save.
        case dismissed
        /// Sheet dismissed after successful delete.
        case dismissedDeleted

        static func == (lhs: SheetState, rhs: SheetState) -> Bool {
            switch (lhs, rhs) {
            case (.loaded, .loaded), (.dirty, .dirty), (.saving, .saving),
                 (.deleting, .deleting),
                 (.dismissed, .dismissed), (.dismissedDeleted, .dismissedDeleted):
                return true
            case (.error(let lhsMsg), .error(let rhsMsg)):
                return lhsMsg == rhsMsg
            default:
                return false
            }
        }
    }

    // MARK: - Form State

    var sheetState: SheetState = .loaded

    /// Product name (pre-filled). Changes transition to `dirty`.
    var name: String {
        didSet { transitionToDirty() }
    }

    /// Abbreviated task directory path (pre-filled). Changes transition to `dirty`.
    var taskDirectoryPath: String {
        didSet { transitionToDirty() }
    }

    /// Abbreviated toolkit directory path (pre-filled, may be empty). Changes transition to `dirty`.
    var toolkitDirectoryPath: String {
        didSet { transitionToDirty() }
    }

    // MARK: - Derived State

    var isSaving: Bool {
        sheetState == .saving
    }

    var isDeleting: Bool {
        sheetState == .deleting
    }

    var errorMessage: String? {
        if case .error(let msg) = sheetState { return msg }
        return nil
    }

    /// IS-SHEET-003: Save enabled when name is non-empty and state allows saving.
    var isSaveEnabled: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch sheetState {
        case .dirty, .error:
            return true
        default:
            return false
        }
    }

    // MARK: - Private State

    private let originalProduct: Product
    private let sessionViewModel: SessionViewModel
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.agilemaestro",
        category: "EditProductSheetViewModel"
    )

    // MARK: - Init

    init(product: Product, sessionViewModel: SessionViewModel) {
        self.originalProduct = product
        self.sessionViewModel = sessionViewModel
        self.name = product.name
        self.taskDirectoryPath = Self.abbreviatePath(product.associatedSessionPath ?? "")
        self.toolkitDirectoryPath = Self.abbreviatePath(product.claudeDirectoryPath ?? "")
    }

    // MARK: - State Transitions

    private func transitionToDirty() {
        switch sheetState {
        case .loaded, .error:
            sheetState = .dirty
        default:
            break
        }
    }

    // MARK: - NSOpenPanel (IS-SHEET-002)

    /// Opens NSOpenPanel to select a task directory and updates `taskDirectoryPath`.
    func changeTaskDirectory() {
        guard let url = runOpenPanel() else { return }
        taskDirectoryPath = Self.abbreviatePath(url.path)
    }

    /// Opens NSOpenPanel to select a toolkit directory and updates `toolkitDirectoryPath`.
    func changeToolkitDirectory() {
        guard let url = runOpenPanel() else { return }
        toolkitDirectoryPath = Self.abbreviatePath(url.path)
    }

    /// Creates and runs a directory-only NSOpenPanel, returning the selected URL or nil.
    private func runOpenPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Select Directory"
        return panel.runModal() == .OK ? panel.url : nil
    }

    // MARK: - Path Abbreviation (IS-SHEET-002)

    /// Abbreviates an absolute path by replacing the home directory prefix with `~`.
    static func abbreviatePath(_ path: String) -> String {
        guard !path.isEmpty else { return "" }
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    /// Expands `~` prefix back to the home directory for storage.
    private func expandPath(_ path: String) -> String {
        if path.hasPrefix("~/") {
            return NSHomeDirectory() + path.dropFirst(1)
        }
        return path
    }

    // MARK: - Product Name (for alert title)

    /// The original product name, used in the delete confirmation alert title.
    var productName: String { originalProduct.name }

    // MARK: - Save Action

    /// Validates, builds updated Product, and calls SessionViewModel.updateProduct.
    func saveProduct() async {
        guard isSaveEnabled else { return }

        sheetState = .saving

        var updated = originalProduct
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.associatedSessionPath = taskDirectoryPath.isEmpty
            ? nil
            : expandPath(taskDirectoryPath)
        updated.claudeDirectoryPath = toolkitDirectoryPath.isEmpty
            ? nil
            : expandPath(toolkitDirectoryPath)

        do {
            try await sessionViewModel.updateProduct(updated)
            sheetState = .dismissed
            logger.info("Product updated: \(updated.name)")
        } catch {
            sheetState = .error(error.localizedDescription)
            logger.error("updateProduct failed: \(error)")
        }
    }

    // MARK: - Delete Action

    /// Calls SessionViewModel.removeProduct; transitions to dismissedDeleted on success.
    func deleteProduct() async {
        let product = originalProduct
        sheetState = .deleting

        do {
            try await sessionViewModel.removeProduct(product)
            sheetState = .dismissedDeleted
            logger.info("Product removed: \(product.name)")
        } catch {
            sheetState = .error(error.localizedDescription)
            logger.error("removeProduct failed: \(error)")
        }
    }
}

// MARK: - View

/// Modal sheet for editing an existing product.
///
/// Implements SM-EDIT-PRODUCT-002, IS-SHEET-002, IS-SHEET-003, IS-SHEET-004,
/// and MF-EDIT-PRODUCT-002 from the UX Flows specification.
struct EditProductSheet: View {

    @State private var viewModel: EditProductSheetViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirmation = false
    @FocusState private var nameFieldFocused: Bool

    init(product: Product, sessionViewModel: SessionViewModel) {
        _viewModel = State(
            initialValue: EditProductSheetViewModel(
                product: product,
                sessionViewModel: sessionViewModel
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // MARK: Header
            Text("Edit Product")
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)

            Divider()

            // MARK: Form Body
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Section 1: Product Name
                    FormSectionView(title: "Name") {
                        TextField("Product name", text: $viewModel.name)
                            .textFieldStyle(.roundedBorder)
                            .focused($nameFieldFocused)
                            .disabled(viewModel.isSaving || viewModel.isDeleting)
                            .accessibilityLabel("Product name")
                            .accessibilityHint("Edit the name for this product")
                    }

                    // Section 2: Task Directory
                    FormSectionView(title: "Task Directory") {
                        EditDirectoryRowView(
                            path: viewModel.taskDirectoryPath,
                            accessibilityPathLabel: "Task directory: \(viewModel.taskDirectoryPath)",
                            changeButtonLabel: "Change task directory",
                            isDisabled: viewModel.isSaving || viewModel.isDeleting,
                            onChange: {
                                viewModel.changeTaskDirectory()
                            }
                        )
                    }

                    // Section 3: Toolkit Directory
                    FormSectionView(title: "Toolkit Directory") {
                        EditDirectoryRowView(
                            path: viewModel.toolkitDirectoryPath,
                            accessibilityPathLabel: viewModel.toolkitDirectoryPath.isEmpty
                                ? "Toolkit directory: not set"
                                : "Toolkit directory: \(viewModel.toolkitDirectoryPath)",
                            changeButtonLabel: "Change toolkit directory",
                            isDisabled: viewModel.isSaving || viewModel.isDeleting,
                            onChange: {
                                viewModel.changeToolkitDirectory()
                            }
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }

            // MARK: Error Banner
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Divider()

            // MARK: Footer
            HStack(spacing: 8) {

                // Delete (destructive, left-aligned — action gravity by position per design spec)
                Button("Delete Product", role: .destructive) {
                    showingDeleteConfirmation = true
                }
                .disabled(viewModel.isSaving || viewModel.isDeleting)
                .accessibilityLabel("Delete product")
                .accessibilityHint("Removes this product from the list. Backup files are preserved.")

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .disabled(viewModel.isSaving || viewModel.isDeleting)
                .accessibilityLabel("Cancel")
                .keyboardShortcut(.escape, modifiers: [])

                // Save button: shows ProgressView when saving
                Button {
                    Task {
                        await viewModel.saveProduct()
                        if viewModel.sheetState == .dismissed {
                            dismiss()
                        }
                    }
                } label: {
                    if viewModel.isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Save")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.isSaveEnabled || viewModel.isSaving || viewModel.isDeleting)
                .accessibilityLabel("Save product changes")
                .accessibilityHint(
                    viewModel.isSaveEnabled
                    ? "Saves changes to this product"
                    : "Enter a product name to enable"
                )
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Edit Product")
        .onAppear {
            nameFieldFocused = true
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.errorMessage)

        // MARK: Delete Confirmation Alert (IS-SHEET-004)
        .alert("Delete \(viewModel.productName)?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                // Alert dismisses; sheet remains open.
                // SM-EDIT-PRODUCT-002: confirming_delete → loaded or dirty
            }
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.deleteProduct()
                    if viewModel.sheetState == .dismissedDeleted {
                        dismiss()
                    }
                }
            }
        } message: {
            Text("This removes the product from the list. Your backup files are not deleted.")
        }
    }
}

// MARK: - EditDirectoryRowView

/// Displays an abbreviated directory path with a "Change…" button for NSOpenPanel.
///
/// Named `EditDirectoryRowView` to distinguish from any future shared component,
/// keeping it scoped to EditProductSheet.
private struct EditDirectoryRowView: View {
    let path: String
    let accessibilityPathLabel: String
    let changeButtonLabel: String
    let isDisabled: Bool
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(path.isEmpty ? "Not set" : path)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(path.isEmpty ? .tertiary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(accessibilityPathLabel)

            Button("Change\u{2026}") {
                onChange()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isDisabled)
            .accessibilityLabel(changeButtonLabel)
        }
    }
}

// MARK: - Previews

#Preview("EditProductSheet — loaded") {
    let product = Product(
        name: "Agile Maestro",
        associatedSessionPath: NSHomeDirectory() + "/Code/agile-maestro/.claude/tasks/session-abc",
        claudeDirectoryPath: NSHomeDirectory() + "/Code/agile-maestro/.claude"
    )
    EditProductSheet(product: product, sessionViewModel: SessionViewModel())
        .preferredColorScheme(.light)
}

#Preview("EditProductSheet — dark") {
    let product = Product(
        name: "My Project",
        associatedSessionPath: NSHomeDirectory() + "/Code/myproject/.claude/tasks/session-xyz",
        claudeDirectoryPath: nil
    )
    EditProductSheet(product: product, sessionViewModel: SessionViewModel())
        .preferredColorScheme(.dark)
}
