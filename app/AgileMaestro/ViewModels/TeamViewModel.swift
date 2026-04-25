import Foundation
import Observation
import OSLog

// MARK: - TeamViewModel

/// ViewModel for the Team view.
///
/// Drives `TeamView` via `viewState`. Implements SM-TEAM-001:
/// - `.idle`  — no toolkit path, or manifest file missing
/// - `.loading` — manifest is being parsed
/// - `.loaded(AgentManifest)` — manifest decoded, detail panes available
/// - `.error(String)` — manifest parse failed
///
/// Sub-conditions within `.idle` are exposed via `hasToolkitPath` and
/// `isManifestMissing` for the view to select the correct empty state.
@Observable
@MainActor
final class TeamViewModel {

    // MARK: - ViewState (SM-TEAM-001)

    /// Loading lifecycle enum matching SM-TEAM-001.
    enum ViewState: Equatable {
        /// No toolkit configured, or manifest file missing. View reads sub-conditions
        /// (`hasToolkitPath`, `isManifestMissing`) to select the correct empty state.
        case idle

        /// Manifest is being loaded or regenerated.
        case loading

        /// Manifest decoded successfully. Associated value is the full manifest.
        case loaded(AgentManifest)

        /// Manifest parse failed. Associated value is the user-facing error message.
        case error(String)

        // MARK: Equatable

        static func == (lhs: ViewState, rhs: ViewState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle),
                 (.loading, .loading):
                return true
            case (.loaded(let lhsManifest), .loaded(let rhsManifest)):
                return lhsManifest == rhsManifest
            case (.error(let lhsMsg), .error(let rhsMsg)):
                return lhsMsg == rhsMsg
            default:
                return false
            }
        }
    }

    // MARK: - State

    /// Current view state driving the Team view.
    private(set) var viewState: ViewState = .idle

    /// True when a toolkit directory path is configured on the active product.
    private(set) var hasToolkitPath: Bool = false

    /// True when `hasToolkitPath` is true but no manifest file exists at that path.
    ///
    /// Used by `TeamView` to distinguish "no toolkit" vs "no manifest" within `.idle`.
    private(set) var isManifestMissing: Bool = false

    /// True while an "Update Team Info" script is executing.
    private(set) var isUpdating: Bool = false

    /// Controls whether the Edit Product sheet is shown.
    var showEditProduct: Bool = false

    /// The currently selected section in the Team sidebar.
    ///
    /// Kept on the ViewModel so the selection persists across `.loaded` state transitions
    /// (e.g., manifest reloads do not reset the user's active section).
    var selectedSection: TeamSection = .roster

    /// Search query for filtering agents in GroupedRosterView.
    var searchQuery: String = ""

    // MARK: - Computed Properties

    /// Agents from the loaded manifest, or an empty array.
    var agents: [AgentInfo] {
        guard case .loaded(let manifest) = viewState else { return [] }
        return manifest.agents
    }

    /// Workflow pipelines from the loaded manifest, or an empty array.
    var pipelines: [WorkflowPipeline] {
        guard case .loaded(let manifest) = viewState else { return [] }
        return manifest.workflowPipelines
    }

    /// Directory health from the loaded manifest, or nil.
    var health: DirectoryHealth? {
        guard case .loaded(let manifest) = viewState else { return nil }
        return manifest.directoryHealth
    }

    /// Timestamp when the manifest was last generated, or nil.
    var generatedAt: String? {
        guard case .loaded(let manifest) = viewState else { return nil }
        return manifest.generatedAt
    }

    /// Agents filtered by `searchQuery` (case-insensitive substring match on name, description, or skills).
    ///
    /// Returns all agents when `searchQuery` is empty.
    var filteredAgents: [AgentInfo] {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return agents }
        let lower = query.lowercased()
        return agents.filter { agent in
            agent.name.lowercased().contains(lower)
                || agent.description.lowercased().contains(lower)
                || agent.skills.contains { $0.lowercased().contains(lower) }
        }
    }

    // MARK: - Private

    private let manifestService: ManifestServiceProtocol
    private let logger = Logger.manifest

    /// The product whose manifest is currently loaded (used to detect product changes).
    private var currentProductID: UUID?

    // MARK: - Init

    init(manifestService: ManifestServiceProtocol = ManifestService.shared) {
        self.manifestService = manifestService
    }

    // MARK: - SM-TEAM-001 Entry Point

    /// Loads the manifest for the given product, implementing SM-TEAM-001 guards.
    ///
    /// - If the product changes: resets all state to `.idle` and re-evaluates.
    /// - Guard (no toolkit path): stays `.idle`, sets `hasToolkitPath = false`.
    /// - Guard (manifest file missing): stays `.idle`, sets `isManifestMissing = true`.
    /// - Guard (manifest file present): transitions to `.loading`, then `.loaded` or `.error`.
    func loadManifest(for product: Product) async {
        // SM-TEAM-001: "any | product changes → .idle, clear all state"
        if product.id != currentProductID {
            logger.debug("Product changed — resetting TeamViewModel state")
            resetState(for: product)
        }

        guard let claudeDir = product.claudeDirectoryURL else {
            // Guard: no toolkit path configured
            logger.debug("No claudeDirectoryPath configured — staying .idle (no toolkit)")
            hasToolkitPath = false
            isManifestMissing = false
            viewState = .idle
            return
        }

        hasToolkitPath = true

        // Guard: manifest file must exist before we start loading
        if let manifestURL = product.manifestURL {
            let exists = FileManager.default.fileExists(atPath: manifestURL.path(percentEncoded: false))
            if !exists {
                logger.debug("Manifest file not found — staying .idle (no team info)")
                isManifestMissing = true
                viewState = .idle
                return
            }
        }

        isManifestMissing = false
        await performLoad(from: claudeDir)
    }

    // MARK: - SM-TEAM-001: Update (native re-scan)

    /// Triggers "Update Team Info": re-runs the native ManifestService scan and reloads.
    ///
    /// SM-TEAM-001 transition: `.loaded` or `.idle` → `.loading` → `.loaded` or `.error`.
    ///
    /// - Parameter product: The product whose toolkit directory will be scanned.
    func updateManifest(for product: Product) async {
        guard let claudeDir = product.claudeDirectoryURL else {
            logger.warning("updateManifest called but no claudeDirectoryPath — no-op")
            return
        }

        isUpdating = true
        viewState = .loading
        logger.info("Re-scanning manifest from: \(claudeDir.path(percentEncoded: false))")

        await performLoad(from: claudeDir)

        isUpdating = false
    }

    /// Convenience no-arg overload for call sites that don't have a product reference.
    ///
    /// No-op if no product is currently tracked. Preserved from the prior stub
    /// to avoid breaking existing TeamView and DirectoryHealthView call sites.
    func updateManifest() async {
        // No-op: call sites that need full functionality should call updateManifest(for:)
        // This stub is preserved for views that will be updated in task-150.
    }

    // MARK: - Private Helpers

    /// Resets all ViewModel state when the active product changes.
    private func resetState(for product: Product) {
        currentProductID = product.id
        viewState = .idle
        hasToolkitPath = false
        isManifestMissing = false
        isUpdating = false
        searchQuery = ""
    }

    /// Transitions to `.loading`, calls `ManifestService`, then sets `.loaded` or `.error`.
    private func performLoad(from claudeDir: URL) async {
        viewState = .loading
        logger.debug("Loading manifest from: \(claudeDir.path(percentEncoded: false))")

        do {
            let manifest = try await manifestService.loadManifest(from: claudeDir)
            viewState = .loaded(manifest)
            logger.info(
                """
                Manifest loaded: \(manifest.agents.count) agent(s), \
                \(manifest.workflowPipelines.count) pipeline(s)
                """
            )
        } catch {
            let message = error.localizedDescription
            viewState = .error(message)
            logger.error("Manifest load failed: \(message)")
        }
    }

}

// MARK: - Preview Helpers

extension TeamViewModel {

    /// Preview factory: idle state (no toolkit configured).
    static func previewIdle() -> TeamViewModel {
        TeamViewModel()
        // hasToolkitPath defaults to false → "No Toolkit Configured" empty state
    }

    /// Preview factory: loading state.
    static func previewLoading() -> TeamViewModel {
        let vm = TeamViewModel()
        vm.viewState = .loading
        return vm
    }

    /// Preview factory: loaded state with a sample manifest.
    static func previewLoaded() -> TeamViewModel {
        let vm = TeamViewModel()
        vm.viewState = .loaded(AgentManifest.preview)
        return vm
    }

    /// Preview factory: error state.
    static func previewError() -> TeamViewModel {
        let vm = TeamViewModel()
        vm.viewState = .error("Unexpected character 'x' at line 42, column 8")
        return vm
    }
}
