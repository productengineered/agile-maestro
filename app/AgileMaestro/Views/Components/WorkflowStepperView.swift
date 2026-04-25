import SwiftUI

// MARK: - WorkflowStep Model

struct WorkflowStep: Identifiable {
    let id: String
    let label: String
    let state: WorkflowStepState
}

enum WorkflowStepState: Equatable {
    case completed    // Green fill + checkmark
    case current      // Accent fill + pulsing (awaiting) OR orange fill (rejected)
    case upcoming     // Outlined gray circle
}

// MARK: - WorkflowStepperView

/// Read-only workflow progress display. Shown below DetailHeaderView for epic and story types.
/// No interactive elements — purely visual (IS-STEPPER-001).
/// Computes step states from task.reviewStage and task.reviewResult (SM-STEPPER-001).
struct WorkflowStepperView: View {
    let task: TaskItem

    @State private var pulseOpacity: Double = 1.0

    private var steps: [WorkflowStep] {
        computeSteps(for: task)
    }

    /// Pulse only when current stage is awaiting review (not rejected, not passed).
    private var shouldPulse: Bool {
        task.reviewResult == "awaiting" && task.reviewStage != nil
    }

    var body: some View {
        // Guard: only show stepper for epic and story types
        if task.type == .epic || task.type == .story {
            VStack(alignment: .leading, spacing: 6) {
                // Stage row: circles connected by lines
                HStack(spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        HStack(spacing: 0) {
                            // Stage circle
                            stageCircle(step: step)

                            // Connector line (all but last)
                            if index < steps.count - 1 {
                                connectorLine(
                                    completed: step.state == .completed,
                                    nextCompleted: steps[index + 1].state == .completed
                                )
                            }
                        }
                    }
                }

                // Labels row: aligned below circles
                HStack(spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        HStack(spacing: 0) {
                            // Label centered under circle (20pt wide, matching circle)
                            Text(step.label)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(
                                step.state == .upcoming ? Color.secondary.opacity(0.5) : Color.secondary
                            )
                                .frame(width: 28)  // Match outer frame of circle (28pt)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.7)

                            // Spacer to match connector
                            if index < steps.count - 1 {
                                Spacer()
                            }
                        }
                    }
                }
            }
            // SM-STEPPER-001: Start pulsing when current stage is awaiting
            .onAppear {
                if shouldPulse {
                    startPulse()
                }
            }
            .onChange(of: shouldPulse) { _, newValue in
                if newValue {
                    startPulse()
                } else {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        pulseOpacity = 1.0
                    }
                }
            }
            // IS-STEPPER-001: Combined accessibility element
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
        }
    }

    // MARK: - Stage Circle

    @ViewBuilder
    private func stageCircle(step: WorkflowStep) -> some View {
        ZStack {
            switch step.state {
            case .completed:
                // Green filled circle with checkmark
                Circle()
                    .fill(Color.green)
                    .frame(width: 20, height: 20)

                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.monochrome)

            case .current:
                let isRejected = task.reviewResult == "rejected"
                let circleColor: Color = isRejected ? .orange : .accentColor

                // Outer pulse ring (awaiting only — not rejected)
                if !isRejected {
                    Circle()
                        .fill(circleColor.opacity(0.20))
                        .frame(width: 28, height: 28)
                        .opacity(pulseOpacity)
                }

                // Main circle
                Circle()
                    .fill(circleColor)
                    .frame(width: 20, height: 20)

                // Center dot
                Circle()
                    .fill(.white)
                    .frame(width: 7, height: 7)

            case .upcoming:
                // Outlined gray circle
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.30), lineWidth: 1.5)
                    .frame(width: 20, height: 20)

                Circle()
                    .fill(Color.secondary.opacity(0.08))
                    .frame(width: 20, height: 20)
            }
        }
        .frame(width: 28, height: 28)  // Outer frame accounts for pulse ring
    }

    // MARK: - Connector Line

    private func connectorLine(completed: Bool, nextCompleted: Bool) -> some View {
        Rectangle()
            .fill(
                completed && nextCompleted
                    ? Color.green.opacity(0.5)
                    : Color.secondary.opacity(0.20)
            )
            .frame(height: 1.5)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 2)
            .padding(.top, 4)  // Visual center with 20pt circle inside 28pt outer frame
    }

    // MARK: - Pulse Animation

    private func startPulse() {
        withAnimation(
            .easeInOut(duration: 1.0)
            .repeatForever(autoreverses: true)
        ) {
            pulseOpacity = 0.4
        }
    }

    // MARK: - Step Computation (SM-STEPPER-001)

    /// Pure function: computes the visual state for each stage from task workflow metadata.
    /// Covers all 11 SM-STEPPER-001 states.
    /// Internal access for unit testing.
    func computeSteps(for task: TaskItem) -> [WorkflowStep] {
        let stageKeys: [String]
        let stageLabels: [String]

        switch task.type {
        case .epic:
            stageKeys   = ["dev", "code-review", "qa", "security", "product-review", "human-uat", "done"]
            stageLabels = ["Dev", "Code\nReview", "QA", "Security", "Product\nReview", "Human\nUAT", "Done"]
        case .story:
            stageKeys   = ["dev", "code-review", "qa", "product-review", "done"]
            stageLabels = ["Dev", "Code\nReview", "QA", "Product\nReview", "Done"]
        default:
            return []  // Tasks, bugs, techdebt do not show a stepper
        }

        let reviewStage  = task.reviewStage    // e.g. "code-review"
        let reviewResult = task.reviewResult   // e.g. "awaiting", "rejected", "passed"
        let taskStatus   = task.status         // .pending, .inProgress, .completed

        // State 10: status == completed → all stages completed
        if taskStatus == .completed {
            return zip(stageKeys, stageLabels).map { key, label in
                WorkflowStep(id: key, label: label, state: .completed)
            }
        }

        // Determine current stage index
        // When reviewStage == nil AND status is pending/inProgress → Dev is current (index 0)
        // ERR-DETAIL-007: unknown stage → currentIndex = nil → all upcoming
        let currentIndex: Int?
        if let stage = reviewStage {
            currentIndex = stageKeys.firstIndex(of: stage)  // nil if unknown stage
        } else {
            // No review stage = Dev is current (pending or in_progress)
            currentIndex = 0
        }

        return zip(stageKeys, stageLabels).enumerated().map { enumIndex, pair in
            let (key, label) = pair
            let state: WorkflowStepState

            if let ci = currentIndex {
                if enumIndex < ci {
                    state = .completed
                } else if enumIndex == ci {
                    // SM-STEPPER-001: product-review with result "passed" → show as completed
                    if reviewResult == "passed" && key == "product-review" {
                        state = .completed
                    } else {
                        state = .current
                    }
                } else {
                    state = .upcoming
                }
            } else {
                // ERR-DETAIL-007: unknown review stage → all upcoming
                state = .upcoming
            }

            return WorkflowStep(id: key, label: label, state: state)
        }
    }

    // MARK: - Accessibility Label (IS-STEPPER-001)

    private var accessibilityLabel: String {
        let flatten: (String) -> String = { $0.replacingOccurrences(of: "\n", with: " ") }
        let completedSteps = steps.filter { $0.state == .completed }.map { flatten($0.label) }
        let currentStep    = steps.first(where: { $0.state == .current }).map { flatten($0.label) }
        let upcomingSteps  = steps.filter { $0.state == .upcoming }.map { flatten($0.label) }

        var parts: [String] = ["Workflow progress:"]
        if !completedSteps.isEmpty {
            parts.append("Completed: \(completedSteps.joined(separator: ", "))")
        }
        if let current = currentStep {
            let rejectedNote = task.reviewResult == "rejected" ? " (rejected)" : ""
            parts.append("Current stage: \(current)\(rejectedNote)")
        }
        if !upcomingSteps.isEmpty {
            parts.append("Upcoming: \(upcomingSteps.joined(separator: ", "))")
        }
        return parts.joined(separator: ". ")
    }
}

// MARK: - Preview

#Preview("Story - Code Review Awaiting") {
    let task = PreviewTaskItemFactory.makeStory(reviewStage: "code-review", reviewResult: "awaiting")
    return WorkflowStepperView(task: task)
        .padding()
        .frame(width: 400)
}

#Preview("Story - Code Review Rejected") {
    let task = PreviewTaskItemFactory.makeStory(reviewStage: "code-review", reviewResult: "rejected")
    return WorkflowStepperView(task: task)
        .padding()
        .frame(width: 400)
}

#Preview("Epic - QA Awaiting") {
    let task = PreviewTaskItemFactory.makeEpic(reviewStage: "qa", reviewResult: "awaiting")
    return WorkflowStepperView(task: task)
        .padding()
        .frame(width: 500)
}

#Preview("Story - Completed") {
    let task = PreviewTaskItemFactory.makeStory(status: .completed)
    return WorkflowStepperView(task: task)
        .padding()
        .frame(width: 400)
}

// MARK: - Preview Factory (internal, not for production use)

private enum PreviewTaskItemFactory {

    static func makeStory(
        reviewStage: String? = nil,
        reviewResult: String? = nil,
        status: TaskStatus = .inProgress
    ) -> TaskItem {
        makeItem(type: "story", reviewStage: reviewStage, reviewResult: reviewResult, status: status)
    }

    static func makeEpic(
        reviewStage: String? = nil,
        reviewResult: String? = nil,
        status: TaskStatus = .inProgress
    ) -> TaskItem {
        makeItem(type: "epic", reviewStage: reviewStage, reviewResult: reviewResult, status: status)
    }

    private static func makeItem(
        type: String,
        reviewStage: String?,
        reviewResult: String?,
        status: TaskStatus
    ) -> TaskItem {
        let statusStr: String
        switch status {
        case .pending:    statusStr = "pending"
        case .inProgress: statusStr = "in_progress"
        case .completed:  statusStr = "completed"
        }

        var json: [String: Any] = [
            "id": UUID().uuidString,
            "subject": "Preview \(type.capitalized)",
            "description": "",
            "status": statusStr,
            "blocks": [],
            "blockedBy": [],
            "metadata": [
                "schema_version": "2.0",
                "type": type,
                "approval": "approved",
                "blocked": false,
                "labels": [],
                "comments": []
            ] as [String: Any]
        ]

        // Inject review fields if provided
        if var metadata = json["metadata"] as? [String: Any] {
            if let stage = reviewStage {
                metadata["review_stage"] = stage
            }
            if let result = reviewResult {
                metadata["review_result"] = result
            }
            json["metadata"] = metadata
        }

        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let item = try? JSONDecoder().decode(TaskItem.self, from: data) else {
            fatalError("WorkflowStepperView preview: failed to construct TaskItem fixture")
        }
        return item
    }
}
