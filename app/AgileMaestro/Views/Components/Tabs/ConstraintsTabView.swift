import SwiftUI

// MARK: - ConstraintsTabView

/// Story-only tab. Implementation constraints + AI context + out of scope.
///
/// Three clean cards, no accordion, nothing to click. Shows ContentUnavailableView
/// when all three fields are absent or empty.
struct ConstraintsTabView: View {
    let task: TaskItem

    private var constraints: [String] {
        task.metadata.story?.implementationConstraints ?? []
    }

    private var aiContext: String? {
        let ctx = task.metadata.story?.aiContext
        return (ctx?.isEmpty ?? true) ? nil : ctx
    }

    private var outOfScope: [String] {
        task.metadata.story?.outOfScope ?? []
    }

    private var hasContent: Bool {
        !constraints.isEmpty || aiContext != nil || !outOfScope.isEmpty
    }

    var body: some View {
        if !hasContent {
            ContentUnavailableView(
                "No Constraints",
                systemImage: "exclamationmark.triangle",
                description: Text("No implementation constraints or scope boundaries have been defined.")
            )
        } else {
            LazyVStack(alignment: .leading, spacing: 16) {
                // Implementation Constraints card
                if !constraints.isEmpty {
                    CardView(
                        title: "Implementation Constraints",
                        icon: "exclamationmark.triangle",
                        iconColor: .orange
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(constraints, id: \.self) { constraint in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.orange)
                                        .symbolRenderingMode(.hierarchical)
                                    Text(constraint)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }

                // AI Context card
                if let ctx = aiContext {
                    CardView(title: "AI Context", icon: "sparkles", iconColor: .purple) {
                        Text(ctx)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(3)
                    }
                }

                // Out of Scope card
                if !outOfScope.isEmpty {
                    CardView(title: "Out of Scope", icon: "xmark.circle", iconColor: .red) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(outOfScope, id: \.self) { item in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "xmark.circle")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.red)
                                        .symbolRenderingMode(.hierarchical)
                                    Text(item)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Preview Helpers (preview-only, not for production use)

private enum ConstraintsPreviewFactory {

    /// Creates a TaskItem with story metadata including all three constraint fields.
    static func makeStory() -> TaskItem {
        let json: [String: Any] = [
            "id": "preview-story-1",
            "subject": "Story: Preview Constraints Tab",
            "description": "Preview story for ConstraintsTabView development.",
            "status": "in_progress",
            "blocks": [],
            "blockedBy": [],
            "metadata": [
                "schema_version": "2.0",
                "type": "story",
                "approval": "approved",
                "blocked": false,
                "implementation_constraints": [
                    "Must use @Observable macro, not @StateObject",
                    "No Combine — use async/await throughout",
                    "All service calls must go through the actor-isolated service layer"
                ],
                "ai_context": "This story builds the constraint display layer for the detail panel. " +
                    "Implementors should focus on correctness of the empty-state detection logic.",
                "out_of_scope": [
                    "Inline editing of constraints",
                    "Constraint templates or library"
                ],
                "labels": [],
                "comments": []
            ] as [String: Any]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let item = try? JSONDecoder().decode(TaskItem.self, from: data) else {
            fatalError("ConstraintsTabView preview: failed to construct TaskItem fixture")
        }
        return item
    }

    /// Creates a minimal TaskItem with no constraints data (triggers empty state).
    static func makeEmpty() -> TaskItem {
        let json: [String: Any] = [
            "id": "preview-empty-2",
            "subject": "Story: Empty",
            "description": "",
            "status": "pending",
            "blocks": [],
            "blockedBy": [],
            "metadata": [
                "schema_version": "2.0",
                "type": "story",
                "approval": "pending",
                "blocked": false,
                "labels": [],
                "comments": []
            ] as [String: Any]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let item = try? JSONDecoder().decode(TaskItem.self, from: data) else {
            fatalError("ConstraintsTabView preview: failed to construct empty TaskItem fixture")
        }
        return item
    }
}

// MARK: - Preview

#Preview("ConstraintsTabView — Full") {
    ScrollView {
        ConstraintsTabView(task: ConstraintsPreviewFactory.makeStory())
            .padding(16)
    }
    .frame(width: 420, height: 600)
    .background(Color(.windowBackgroundColor))
}

#Preview("ConstraintsTabView — Empty") {
    ScrollView {
        ConstraintsTabView(task: ConstraintsPreviewFactory.makeEmpty())
            .padding(16)
    }
    .frame(width: 420, height: 300)
    .background(Color(.windowBackgroundColor))
}
