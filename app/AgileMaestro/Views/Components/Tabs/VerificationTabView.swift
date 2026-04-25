import SwiftUI

// MARK: - VerificationTabView (Task only)

/// Read-only verification reference cards.
///
/// Surfaces `local_checks`, `completion_signal`, `validation_hint`, and
/// `ai_execution_hints` from task metadata as structured, selectable cards.
/// All sections are conditionally shown — hidden if the data is nil or empty.
/// Empty state shown when all four sections are absent.
struct VerificationTabView: View {

    // MARK: - Properties

    let task: TaskItem

    // MARK: - Private Computed Properties

    private var localChecks: [String] {
        task.metadata.task?.localChecks ?? []
    }

    private var completionSignal: String? {
        let signal = task.metadata.task?.completionSignal
        return (signal?.isEmpty == false) ? signal : nil
    }

    private var validationHint: String? {
        let hint = task.metadata.task?.validationHint
        return (hint?.isEmpty == false) ? hint : nil
    }

    private var aiExecutionHints: [String] {
        task.metadata.task?.aiExecutionHints ?? []
    }

    private var hasAnyData: Bool {
        !localChecks.isEmpty ||
        completionSignal != nil ||
        validationHint != nil ||
        !aiExecutionHints.isEmpty
    }

    // MARK: - Body

    var body: some View {
        if hasAnyData {
            LazyVStack(alignment: .leading, spacing: 16) {
                // Local Checks card
                if !localChecks.isEmpty {
                    localChecksCard
                }

                // Completion Signal card
                if let signal = completionSignal {
                    completionSignalCard(signal)
                }

                // Validation Hint card
                if let hint = validationHint {
                    validationHintCard(hint)
                }

                // AI Execution Hints card
                if !aiExecutionHints.isEmpty {
                    aiExecutionHintsCard
                }
            }
        } else {
            ContentUnavailableView(
                "No Verification Data",
                systemImage: "shield.checkered",
                description: Text("No verification criteria have been defined for this task.")
            )
        }
    }

    // MARK: - Local Checks Card

    private var localChecksCard: some View {
        CardView(
            title: "Local Checks",
            icon: "shield.checkered",
            iconColor: .green
        ) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(localChecks.enumerated()), id: \.offset) { index, check in
                    HStack(alignment: .top, spacing: 8) {
                        // Numbered check badge
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.12))
                                .frame(width: 20, height: 20)
                            Text("\(index + 1)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.green)
                        }

                        // Check text
                        Text(check)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    // MARK: - Completion Signal Card

    private func completionSignalCard(_ signal: String) -> some View {
        CardView(
            title: "Completion Signal",
            icon: "flag.checkered",
            iconColor: .accentColor
        ) {
            Text(signal)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Validation Hint Card

    private func validationHintCard(_ hint: String) -> some View {
        CardView(
            title: "Validation Hint",
            icon: "lightbulb",
            iconColor: .yellow
        ) {
            Text(hint)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - AI Execution Hints Card

    private var aiExecutionHintsCard: some View {
        CardView(
            title: "AI Execution Hints",
            icon: "sparkles",
            iconColor: .purple
        ) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(aiExecutionHints.enumerated()), id: \.offset) { _, hint in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.purple)
                            .symbolRenderingMode(.monochrome)
                            .padding(.top, 2)

                        Text(hint)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("With All Sections") {
    let item = PreviewTaskFactory.makeTask(
        localChecks: [
            "Build succeeds with zero errors",
            "SwiftLint passes with no violations",
            "All unit tests pass"
        ],
        completionSignal: "VerificationTabView compiles and displays all four cards conditionally.",
        validationHint: "Check that each card only appears when its data is non-empty.",
        aiExecutionHints: [
            "Read the design spec before implementing — skeleton code is provided.",
            "Use CardView from Shared/CardView.swift for each section.",
            "Wire .verification case in TaskDetailView.tabContent(for:)."
        ]
    )
    ScrollView {
        VerificationTabView(task: item)
            .padding(16)
    }
    .frame(width: 380, height: 600)
    .background(Color(.windowBackgroundColor))
}

#Preview("Empty State") {
    let item = PreviewTaskFactory.makeTask(
        localChecks: [],
        completionSignal: nil,
        validationHint: nil,
        aiExecutionHints: []
    )
    VerificationTabView(task: item)
        .padding(16)
        .frame(width: 380, height: 300)
        .background(Color(.windowBackgroundColor))
}

// MARK: - Preview Factory

private enum PreviewTaskFactory {
    static func makeTask(
        localChecks: [String],
        completionSignal: String?,
        validationHint: String?,
        aiExecutionHints: [String]
    ) -> TaskItem {
        let json = buildJSON(
            localChecks: localChecks,
            completionSignal: completionSignal,
            validationHint: validationHint,
            aiExecutionHints: aiExecutionHints
        )
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(TaskItem.self, from: json)
    }

    private static func buildJSON(
        localChecks: [String],
        completionSignal: String?,
        validationHint: String?,
        aiExecutionHints: [String]
    ) -> Data {
        var metadata: [String: Any] = [
            "schema_version": "2.0",
            "type": "task",
            "priority": "P2",
            "approval": "approved",
            "blocked": false,
            "local_checks": localChecks,
            "ai_execution_hints": aiExecutionHints,
            "comments": [Any]()
        ]
        if let signal = completionSignal {
            metadata["completion_signal"] = signal
        }
        if let hint = validationHint {
            metadata["validation_hint"] = hint
        }

        let json: [String: Any] = [
            "id": "preview-99",
            "subject": "Task: Implement VerificationTabView",
            "description": "Preview task for VerificationTabView",
            "status": "pending",
            "blocks": [Any](),
            "blockedBy": [Any](),
            "metadata": metadata
        ]
        // swiftlint:disable:next force_try
        return try! JSONSerialization.data(withJSONObject: json)
    }
}
