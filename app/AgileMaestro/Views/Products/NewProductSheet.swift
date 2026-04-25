import AppKit
import SwiftUI

// MARK: - ViewModel

/// Local ViewModel for NewProductSheet.
///
/// Owns form state per SM-NEW-PRODUCT-001 and provides helper methods for
/// NSOpenPanel invocation (IS-SHEET-002) and Create-button enable logic (IS-SHEET-003).
@Observable
@MainActor
final class NewProductSheetViewModel {

    // MARK: - State Machine (SM-NEW-PRODUCT-001)

    enum SheetState {
        /// Sheet just opened; name empty, session radio pre-selected.
        case idle
        /// User has entered name and/or changed a directory source.
        case editing
        /// `viewModel.createProduct(...)` in flight.
        case saving
        /// Save failed; inline error shown below footer.
        case error(String)
        /// Sheet dismissed (success or Cancel).
        case dismissed
    }

    // MARK: - Directory Source (IS-SHEET-001)

    enum DirectorySource {
        case session
        case browse
    }

    // MARK: - Published Form State

    var sheetState: SheetState = .idle
    var name: String = "" {
        didSet { transitionToEditing() }
    }
    var directorySource: DirectorySource = .session {
        didSet { transitionToEditing() }
    }
    var selectedSession: TaskSession? {
        didSet { transitionToEditing() }
    }
    var taskDirectoryPath: String = "" {
        didSet { transitionToEditing() }
    }
    var toolkitDirectoryPath: String = "" {
        didSet { transitionToEditing() }
    }

    // MARK: - Supporting Data

    var availableSessions: [TaskSession] = []

    // MARK: - Derived State

    var isSaving: Bool {
        if case .saving = sheetState { return true }
        return false
    }

    var errorMessage: String? {
        if case .error(let msg) = sheetState { return msg }
        return nil
    }

    /// IS-SHEET-003: Create enabled when name is non-empty AND directory source is valid.
    var isCreateEnabled: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch directorySource {
        case .session:
            return selectedSession != nil
        case .browse:
            return !taskDirectoryPath.isEmpty
        }
    }

    // MARK: - Private Dependencies

    private let sessionViewModel: SessionViewModel
    private let sessionService: TaskSessionServiceProtocol

    // MARK: - Init

    init(sessionViewModel: SessionViewModel,
         sessionService: TaskSessionServiceProtocol = TaskSessionService.shared) {
        self.sessionViewModel = sessionViewModel
        self.sessionService = sessionService
    }

    // MARK: - State Transitions

    private func transitionToEditing() {
        switch sheetState {
        case .idle, .error:
            sheetState = .editing
        default:
            break
        }
    }

    // MARK: - Load Sessions

    /// Discovers sessions directly from `~/.claude/tasks/` via the session service,
    /// independent of `SessionViewModel.sessions` which may be empty when no product
    /// is currently loaded (e.g. after deleting the last product).
    func loadSessions() async {
        do {
            availableSessions = try await sessionService.getRecentSessions(maxSessions: 10)
        } catch {
            // Fall back silently — the picker will show empty rather than crash.
            availableSessions = []
        }
    }

    // MARK: - NSOpenPanel (IS-SHEET-002)

    /// Opens NSOpenPanel to select a task directory and updates `taskDirectoryPath`.
    func browseForTaskDirectory() {
        guard let url = runOpenPanel() else { return }
        taskDirectoryPath = abbreviatePath(url.path)
        transitionToEditing()
    }

    /// Opens NSOpenPanel to select a toolkit directory and updates `toolkitDirectoryPath`.
    func browseForToolkitDirectory() {
        guard let url = runOpenPanel() else { return }
        toolkitDirectoryPath = abbreviatePath(url.path)
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

    /// Abbreviates an absolute path by replacing the home directory prefix with `~`.
    private func abbreviatePath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    // MARK: - Create Action

    /// Validates form, calls SessionViewModel.createProduct, and transitions state.
    func createProduct() async {
        guard isCreateEnabled else { return }

        sheetState = .saving

        let resolvedPath: String
        switch directorySource {
        case .session:
            guard let session = selectedSession else {
                sheetState = .error("No session selected.")
                return
            }
            resolvedPath = session.path.path
        case .browse:
            resolvedPath = expandPath(taskDirectoryPath)
        }

        let toolkitPath: String? = toolkitDirectoryPath.isEmpty
            ? nil
            : expandPath(toolkitDirectoryPath)

        do {
            try await sessionViewModel.createProduct(
                name: name.trimmingCharacters(in: .whitespaces),
                taskDirectoryPath: resolvedPath,
                toolkitDirectoryPath: toolkitPath
            )
            sheetState = .dismissed
        } catch {
            sheetState = .error(error.localizedDescription)
        }
    }

    /// Expands `~` prefix back to the home directory for storage.
    private func expandPath(_ path: String) -> String {
        if path.hasPrefix("~/") {
            return NSHomeDirectory() + path.dropFirst(1)
        }
        return path
    }
}

// MARK: - View

/// Modal sheet for creating a new product.
///
/// Implements SM-NEW-PRODUCT-001, IS-SHEET-001, IS-SHEET-002, IS-SHEET-003,
/// and MF-NEW-PRODUCT-001 from the UX Flows specification.
struct NewProductSheet: View {

    @State private var viewModel: NewProductSheetViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFieldFocused: Bool

    init(sessionViewModel: SessionViewModel) {
        _viewModel = State(
            initialValue: NewProductSheetViewModel(sessionViewModel: sessionViewModel)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // MARK: Header
            Text("New Product")
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
                            .disabled(viewModel.isSaving)
                            .accessibilityLabel("Product name")
                            .accessibilityHint("Enter a name for this product")
                    }

                    // Section 2: Task Directory
                    FormSectionView(title: "Task Directory") {
                        VStack(alignment: .leading, spacing: 12) {
                            sessionRadioBlock
                            browseRadioBlock
                        }
                    }

                    // Section 3: Toolkit Directory (optional)
                    FormSectionView(title: "Toolkit Directory") {
                        HStack(spacing: 8) {
                            Text(viewModel.toolkitDirectoryPath.isEmpty
                                 ? "Optional"
                                 : viewModel.toolkitDirectoryPath)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(viewModel.toolkitDirectoryPath.isEmpty
                                                 ? .tertiary : .secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityLabel(
                                    viewModel.toolkitDirectoryPath.isEmpty
                                    ? "Toolkit directory: not set"
                                    : "Toolkit directory: \(viewModel.toolkitDirectoryPath)"
                                )

                            Button("Browse\u{2026}") {
                                viewModel.browseForToolkitDirectory()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(viewModel.isSaving)
                            .accessibilityLabel("Browse for toolkit directory")
                        }
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
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .disabled(viewModel.isSaving)
                .accessibilityLabel("Cancel")
                .keyboardShortcut(.escape, modifiers: [])

                Button {
                    Task {
                        await viewModel.createProduct()
                        if case .dismissed = viewModel.sheetState {
                            dismiss()
                        }
                    }
                } label: {
                    if viewModel.isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Create")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.isCreateEnabled || viewModel.isSaving)
                .accessibilityLabel("Create product")
                .accessibilityHint(viewModel.isCreateEnabled
                                   ? "Creates the product and loads the session"
                                   : "Enter a product name and select a directory to enable")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("New Product")
        .task {
            await viewModel.loadSessions()
            nameFieldFocused = true
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.errorMessage)
    }

    // MARK: - Session Radio Block (IS-SHEET-001)

    private var sessionRadioBlock: some View {
        VStack(alignment: .leading, spacing: 8) {

            // Radio button: Select from sessions
            HStack(spacing: 8) {
                Image(systemName: viewModel.directorySource == .session
                      ? "largecircle.fill.circle"
                      : "circle")
                    .foregroundStyle(
                        viewModel.directorySource == .session
                        ? AnyShapeStyle(.tint)
                        : AnyShapeStyle(.secondary)
                    )
                    .symbolRenderingMode(.hierarchical)
                    .animation(.easeInOut(duration: 0.2), value: viewModel.directorySource)
                    .accessibilityHidden(true)

                Text("Select from sessions")
                    .font(.body)
                    .foregroundStyle(
                        viewModel.directorySource == .session ? Color.primary : Color.secondary
                    )
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.directorySource = .session
                }
            }
            .accessibilityLabel("Select from sessions")
            .accessibilityAddTraits(
                viewModel.directorySource == .session ? .isSelected : AccessibilityTraits()
            )

            // Session picker (nested, dimmed when inactive)
            Picker("Session", selection: $viewModel.selectedSession) {
                Text("Choose a session\u{2026}").tag(Optional<TaskSession>.none)
                ForEach(viewModel.availableSessions) { session in
                    Text(session.displayName).tag(Optional(session))
                }
            }
            .pickerStyle(.menu)
            .padding(.leading, 24)
            .opacity(viewModel.directorySource == .session ? 1.0 : 0.4)
            .disabled(viewModel.directorySource != .session || viewModel.isSaving)
            .animation(.easeInOut(duration: 0.2), value: viewModel.directorySource)
            .accessibilityLabel("Session")
            .accessibilityHint("Select an existing session as the task directory source")
        }
    }

    // MARK: - Browse Radio Block (IS-SHEET-001)

    private var browseRadioBlock: some View {
        VStack(alignment: .leading, spacing: 8) {

            // Radio button: Browse for directory
            HStack(spacing: 8) {
                Image(systemName: viewModel.directorySource == .browse
                      ? "largecircle.fill.circle"
                      : "circle")
                    .foregroundStyle(
                        viewModel.directorySource == .browse
                        ? AnyShapeStyle(.tint)
                        : AnyShapeStyle(.secondary)
                    )
                    .symbolRenderingMode(.hierarchical)
                    .animation(.easeInOut(duration: 0.2), value: viewModel.directorySource)
                    .accessibilityHidden(true)

                Text("Browse for directory")
                    .font(.body)
                    .foregroundStyle(
                        viewModel.directorySource == .browse ? Color.primary : Color.secondary
                    )
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.directorySource = .browse
                }
            }
            .accessibilityLabel("Browse for directory")
            .accessibilityAddTraits(
                viewModel.directorySource == .browse ? .isSelected : AccessibilityTraits()
            )

            // Path display + Browse button (nested, dimmed when inactive)
            HStack(spacing: 8) {
                Text(viewModel.taskDirectoryPath.isEmpty
                     ? "No directory selected"
                     : viewModel.taskDirectoryPath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(viewModel.taskDirectoryPath.isEmpty ? .tertiary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(
                        viewModel.taskDirectoryPath.isEmpty
                        ? "Task directory: none selected"
                        : "Task directory: \(viewModel.taskDirectoryPath)"
                    )

                Button("Browse\u{2026}") {
                    viewModel.browseForTaskDirectory()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.directorySource != .browse || viewModel.isSaving)
                .accessibilityLabel("Browse for task directory")
            }
            .padding(.leading, 24)
            .opacity(viewModel.directorySource == .browse ? 1.0 : 0.4)
            .animation(.easeInOut(duration: 0.2), value: viewModel.directorySource)
        }
    }
}

// MARK: - FormSectionView

/// Reusable labeled form section with title header and content slot.
struct FormSectionView<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            content()
        }
    }
}

// MARK: - Previews

#Preview("NewProductSheet — idle") {
    NewProductSheet(sessionViewModel: SessionViewModel())
        .preferredColorScheme(.light)
}

#Preview("NewProductSheet — dark") {
    NewProductSheet(sessionViewModel: SessionViewModel())
        .preferredColorScheme(.dark)
}
