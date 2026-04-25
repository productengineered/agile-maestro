import Foundation

/// All fields specific to an epic task.
///
/// Decoded from the flat top-level metadata JSON object when `type == "epic"`.
/// All fields are optional to support resilient decoding of partial or evolving JSON.
struct EpicMetadata: Codable {

    // MARK: - Stored Properties

    let schemaVersion: String?
    /// Display identifier (e.g. "AM-100"). Maps from the "id" JSON key.
    let displayId: String?
    let lastUpdatedAt: Date?
    let claimedBy: String?
    let epicId: String?
    let phase: String?
    let project: String?
    let goal: String?
    let testCriteria: String?
    /// Resilient: decoded from Int or String.
    let storyCount: Int?
    let complexity: String?
    let riskLevel: String?
    /// Resilient: decoded from Int or String.
    let sprint: Int?
    let branch: String?
    let plannedBy: String?
    let estimate: Estimate?
    let references: References?
    let dependencies: Dependencies?
    let successMetrics: SuccessMetrics?
    let acceptanceCriteria: [AcceptanceCriteriaItem]?
    let executionPlan: ExecutionPlan?
    let definitionOfDone: DefinitionOfDone?
    let externalDeps: [String]?
    let blocksEpics: [String]?
    let suggestedInputs: [SuggestedInput]?
    let risks: [RiskItem]?
    let outOfScope: [String]?
    let stories: [StoryReference]?

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case displayId = "id"
        case lastUpdatedAt = "last_updated_at"
        case claimedBy = "claimed_by"
        case epicId = "epic_id"
        case phase
        case project
        case goal
        case testCriteria = "test_criteria"
        case storyCount = "story_count"
        case complexity
        case riskLevel = "risk_level"
        case sprint
        case branch
        case plannedBy = "planned_by"
        case estimate
        case references
        case dependencies
        case successMetrics = "success_metrics"
        case acceptanceCriteria = "acceptance_criteria"
        case executionPlan = "execution_plan"
        case definitionOfDone = "definition_of_done"
        case externalDeps = "external_deps"
        case blocksEpics = "blocks_epics"
        case suggestedInputs = "suggested_inputs"
        case risks
        case outOfScope = "out_of_scope"
        case stories
    }

    // MARK: - Custom Decoding

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        schemaVersion = try? container.decode(String.self, forKey: .schemaVersion)
        displayId = try? container.decode(String.self, forKey: .displayId)
        lastUpdatedAt = decodeDateResiliently(from: container, forKey: .lastUpdatedAt)
        claimedBy = try? container.decode(String.self, forKey: .claimedBy)
        epicId = try? container.decode(String.self, forKey: .epicId)
        phase = try? container.decode(String.self, forKey: .phase)
        project = try? container.decode(String.self, forKey: .project)
        goal = try? container.decode(String.self, forKey: .goal)
        testCriteria = try? container.decode(String.self, forKey: .testCriteria)
        storyCount = decodeFlexibleInt(from: container, forKey: .storyCount)
        complexity = try? container.decode(String.self, forKey: .complexity)
        riskLevel = try? container.decode(String.self, forKey: .riskLevel)
        sprint = decodeFlexibleInt(from: container, forKey: .sprint)
        branch = try? container.decode(String.self, forKey: .branch)
        plannedBy = try? container.decode(String.self, forKey: .plannedBy)
        estimate = try? container.decode(Estimate.self, forKey: .estimate)
        references = try? container.decode(References.self, forKey: .references)
        dependencies = try? container.decode(Dependencies.self, forKey: .dependencies)
        successMetrics = try? container.decode(SuccessMetrics.self, forKey: .successMetrics)
        acceptanceCriteria = decodeResiliently(
            AcceptanceCriteriaItem.self, from: container, forKey: .acceptanceCriteria)
        executionPlan = try? container.decode(ExecutionPlan.self, forKey: .executionPlan)
        definitionOfDone = try? container.decode(DefinitionOfDone.self, forKey: .definitionOfDone)
        externalDeps = try? container.decode([String].self, forKey: .externalDeps)
        blocksEpics = try? container.decode([String].self, forKey: .blocksEpics)
        suggestedInputs = decodeResiliently(SuggestedInput.self, from: container, forKey: .suggestedInputs)
        risks = decodeResiliently(RiskItem.self, from: container, forKey: .risks)
        outOfScope = try? container.decode([String].self, forKey: .outOfScope)
        stories = decodeResiliently(StoryReference.self, from: container, forKey: .stories)
    }

    // MARK: - Static Empty

    /// An empty EpicMetadata used as a fallback when decoding fails.
    static let empty = EpicMetadata()

    private init() {
        schemaVersion = nil
        displayId = nil
        lastUpdatedAt = nil
        claimedBy = nil
        epicId = nil
        phase = nil
        project = nil
        goal = nil
        testCriteria = nil
        storyCount = nil
        complexity = nil
        riskLevel = nil
        sprint = nil
        branch = nil
        plannedBy = nil
        estimate = nil
        references = nil
        dependencies = nil
        successMetrics = nil
        acceptanceCriteria = nil
        executionPlan = nil
        definitionOfDone = nil
        externalDeps = nil
        blocksEpics = nil
        suggestedInputs = nil
        risks = nil
        outOfScope = nil
        stories = nil
    }

    // MARK: - Computed Properties

    /// The estimate value in the primary unit.
    var estimateValue: Int? {
        estimate?.value
    }

    /// The primary unit of the estimate (e.g. "points").
    var estimateUnit: String? {
        estimate?.primaryUnit
    }

    /// All success metrics combined (primary + secondary).
    var allSuccessMetrics: [String] {
        successMetrics?.allMetrics ?? []
    }

    /// Completion gates from the definition of done.
    var completionGates: [String] {
        definitionOfDone?.completionGates ?? []
    }

    /// Generation hints from the definition of done.
    var generationHints: [String] {
        definitionOfDone?.generationHints ?? []
    }

    /// Epics that this epic blocks. Prefers `dependencies.blocksEpics`, falls back to `blocksEpics`.
    var allBlocksEpics: [String] {
        dependencies?.blocksEpics ?? blocksEpics ?? []
    }

    /// All external dependencies as formatted strings ("name version").
    var allExternalDeps: [String] {
        if let externalList = dependencies?.external, !externalList.isEmpty {
            return externalList.compactMap { dep in
                guard let name = dep.name else { return nil }
                if let version = dep.version {
                    return "\(name) \(version)"
                }
                return name
            }
        }
        return externalDeps ?? []
    }

    /// The execution phases from the execution plan.
    var executionPhases: [ExecutionPhase]? {
        executionPlan?.phases
    }

    /// Whether this epic uses schema version 2.0.
    var isV2Schema: Bool {
        schemaVersion == "2.0"
    }
}
