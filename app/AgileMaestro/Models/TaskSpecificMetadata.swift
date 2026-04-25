import Foundation

// MARK: - BugEnvironment

/// Environment context captured when a bug was discovered.
struct BugEnvironment: Codable {
    /// macOS version the bug was observed on (e.g. "15.4").
    let macosVersion: String?
    /// App version the bug was observed in (e.g. "1.2.3").
    let appVersion: String?

    enum CodingKeys: String, CodingKey {
        case macosVersion = "macos_version"
        case appVersion = "app_version"
    }
}

// MARK: - TaskSpecificMetadata

/// All fields specific to a task, bug, or techdebt item.
///
/// Decoded from the flat top-level metadata JSON object when `type == "task"`, `"bug"`, or `"techdebt"`.
/// All fields are optional to support resilient decoding of partial or evolving JSON.
struct TaskSpecificMetadata: Codable {

    // MARK: - Stored Properties (task / techdebt)

    /// v2.0 schema identifier (e.g. "2.0").
    let schemaVersion: String?
    /// Parent story task ID.
    let parent: String?
    let taskId: String?
    let storyId: String?
    let priority: String?
    /// Resilient: decoded from Int or String.
    let hoursEstimated: Int?
    /// Resilient: decoded from Int or String.
    let hoursActual: Int?
    let assignee: String?
    let claimedBy: String?
    let claimedAt: Date?
    let createdAt: Date?
    let lastUpdatedAt: Date?
    let createdBy: String?
    let files: [String]?
    /// v2.0: Granular implementation steps (renamed from subtasks).
    let checklist: [String]?
    /// v2.0: Task-specific verification checks (renamed from acceptance_criteria). Maps from "local_checks".
    let localChecks: [String]?
    /// v2.0: Defines when this task is considered done.
    let completionSignal: String?
    /// v2.0: How to verify this task (renamed from verify).
    let validationHint: String?
    /// v2.0: Hints for AI agents executing this task.
    let aiExecutionHints: [String]?

    // MARK: - Stored Properties (techdebt-specific)

    /// Debt classification: e.g. "code-quality", "architecture", "testing", "documentation".
    let debtType: String?
    /// Debt subcategory: e.g. "naming", "duplication", "complexity", "missing-tests".
    let debtCategory: String?
    /// File paths impacted by this technical debt item.
    let filesAffected: [String]?
    /// Risk of regression if the debt is addressed: "low", "medium", or "high".
    let regressionRisk: String?
    /// Consequences of deferring this debt item.
    let impactIfDeferred: String?
    /// Business rationale for resolving this debt item.
    let businessJustification: String?

    // MARK: - Stored Properties (bug-specific)

    /// Triage severity: "critical", "major", "moderate", or "minor".
    let severity: String?
    /// Ordered steps required to reproduce the bug.
    let stepsToReproduce: [String]?
    /// What the system should do in the given scenario.
    let expectedBehavior: String?
    /// What the system actually did.
    let actualBehavior: String?
    /// Root-cause-analysis lifecycle: "pending", "investigated", "needs-more-info", "reviewed", or "approved".
    let rcaStatus: String?
    /// ID of the task during which this bug was discovered.
    let discoveredFrom: String?
    /// Name of the agent that discovered this bug.
    let discoveredBy: String?
    /// File paths known to be affected by this bug.
    let affectedFiles: [String]?
    /// Whether this bug is a regression (previously working behaviour broke).
    let regression: Bool?
    /// Environment context captured when the bug was discovered.
    let environment: BugEnvironment?

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case parent
        case taskId = "task_id"
        case storyId = "story_id"
        case priority
        case hoursEstimated = "hours_estimated"
        case hoursActual = "hours_actual"
        case assignee
        case claimedBy = "claimed_by"
        case claimedAt = "claimed_at"
        case createdAt = "created_at"
        case lastUpdatedAt = "last_updated_at"
        case createdBy = "created_by"
        case files
        case checklist
        case localChecks = "local_checks"
        case completionSignal = "completion_signal"
        case validationHint = "validation_hint"
        case aiExecutionHints = "ai_execution_hints"
        // Techdebt-specific
        case debtType = "debt_type"
        case debtCategory = "debt_category"
        case filesAffected = "files_affected"
        case regressionRisk = "regression_risk"
        case impactIfDeferred = "impact_if_deferred"
        case businessJustification = "business_justification"
        // Bug-specific
        case severity
        case stepsToReproduce = "steps_to_reproduce"
        case expectedBehavior = "expected_behavior"
        case actualBehavior = "actual_behavior"
        case rcaStatus = "rca_status"
        case discoveredFrom = "discovered_from"
        case discoveredBy = "discovered_by"
        case affectedFiles = "affected_files"
        case regression
        case environment
    }

    // MARK: - Custom Decoding

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        schemaVersion = try? container.decode(String.self, forKey: .schemaVersion)
        parent = try? container.decode(String.self, forKey: .parent)
        taskId = try? container.decode(String.self, forKey: .taskId)
        storyId = try? container.decode(String.self, forKey: .storyId)
        priority = decodeFlexibleString(from: container, forKey: .priority)
        hoursEstimated = decodeFlexibleInt(from: container, forKey: .hoursEstimated)
        hoursActual = decodeFlexibleInt(from: container, forKey: .hoursActual)
        assignee = try? container.decode(String.self, forKey: .assignee)
        claimedBy = try? container.decode(String.self, forKey: .claimedBy)
        claimedAt = decodeDateResiliently(from: container, forKey: .claimedAt)
        createdAt = decodeDateResiliently(from: container, forKey: .createdAt)
        lastUpdatedAt = decodeDateResiliently(from: container, forKey: .lastUpdatedAt)
        createdBy = try? container.decode(String.self, forKey: .createdBy)
        files = try? container.decode([String].self, forKey: .files)
        checklist = try? container.decode([String].self, forKey: .checklist)
        localChecks = try? container.decode([String].self, forKey: .localChecks)
        completionSignal = try? container.decode(String.self, forKey: .completionSignal)
        validationHint = try? container.decode(String.self, forKey: .validationHint)
        aiExecutionHints = try? container.decode([String].self, forKey: .aiExecutionHints)
        // Techdebt-specific
        debtType = try? container.decode(String.self, forKey: .debtType)
        debtCategory = try? container.decode(String.self, forKey: .debtCategory)
        filesAffected = try? container.decode([String].self, forKey: .filesAffected)
        regressionRisk = try? container.decode(String.self, forKey: .regressionRisk)
        impactIfDeferred = try? container.decode(String.self, forKey: .impactIfDeferred)
        businessJustification = try? container.decode(String.self, forKey: .businessJustification)
        // Bug-specific
        severity = try? container.decode(String.self, forKey: .severity)
        stepsToReproduce = try? container.decode([String].self, forKey: .stepsToReproduce)
        expectedBehavior = try? container.decode(String.self, forKey: .expectedBehavior)
        actualBehavior = try? container.decode(String.self, forKey: .actualBehavior)
        rcaStatus = try? container.decode(String.self, forKey: .rcaStatus)
        discoveredFrom = try? container.decode(String.self, forKey: .discoveredFrom)
        discoveredBy = try? container.decode(String.self, forKey: .discoveredBy)
        affectedFiles = try? container.decode([String].self, forKey: .affectedFiles)
        regression = decodeFlexibleBool(from: container, forKey: .regression)
        environment = try? container.decode(BugEnvironment.self, forKey: .environment)
    }

    // MARK: - Static Empty

    /// An empty TaskSpecificMetadata used as a fallback when decoding fails.
    static let empty = TaskSpecificMetadata()

    private init() {
        schemaVersion = nil
        parent = nil
        taskId = nil
        storyId = nil
        priority = nil
        hoursEstimated = nil
        hoursActual = nil
        assignee = nil
        claimedBy = nil
        claimedAt = nil
        createdAt = nil
        lastUpdatedAt = nil
        createdBy = nil
        files = nil
        checklist = nil
        localChecks = nil
        completionSignal = nil
        validationHint = nil
        aiExecutionHints = nil
        // Techdebt-specific
        debtType = nil
        debtCategory = nil
        filesAffected = nil
        regressionRisk = nil
        impactIfDeferred = nil
        businessJustification = nil
        // Bug-specific
        severity = nil
        stepsToReproduce = nil
        expectedBehavior = nil
        actualBehavior = nil
        rcaStatus = nil
        discoveredFrom = nil
        discoveredBy = nil
        affectedFiles = nil
        regression = nil
        environment = nil
    }
}
