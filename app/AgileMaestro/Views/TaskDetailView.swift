import SwiftUI

// MARK: - TaskDetailView

/// Primary container for the task detail panel.
///
/// Routes to one of four states:
/// - **ClaudeTask selected**: Shows `ClaudeTaskDetailView`.
/// - **OrphanedTask selected**: Shows `OrphanedTaskDetailView`.
/// - **TaskItem selected**: Vertical stack with DetailHeaderView,
///   WorkflowStepperView (epic/story only), StatsBarView (all types),
///   DetailTabsView, and tab content per SM-DETAIL-001.
/// - **Idle** (no selection): Shows `TaskDetailPlaceholder`.
///
/// Observes `TreeViewModel.selectedClaudeTask` and `TreeViewModel.selectedOrphanedTask`
/// for the new section types. For standard task items, keeps `DetailViewModel.selectedTask`
/// in sync via `setTask()`. All task transitions animate with `.opacity.easeInOut(0.2)`.
///
/// Background: `.regularMaterial` (inherits from the NavigationSplitView detail pane).
struct TaskDetailView: View {

    // MARK: - Environment

    @Environment(DetailViewModel.self) private var detailViewModel
    @Environment(TreeViewModel.self) private var treeViewModel
    @Environment(SessionViewModel.self) private var sessionViewModel

    // MARK: - Body

    var body: some View {
        Group {
            if let claudeTask = treeViewModel.selectedClaudeTask {
                ClaudeTaskDetailView(task: claudeTask)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: claudeTask.id)
            } else if let orphanedTask = treeViewModel.selectedOrphanedTask {
                OrphanedTaskDetailView(task: orphanedTask)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: orphanedTask.filename)
            } else if let task = detailViewModel.selectedTask {
                taskDetailContent(for: task)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: task.id)
            } else {
                TaskDetailPlaceholder()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Sync initial selection when the view first appears.
        .onAppear {
            detailViewModel.setTask(treeViewModel.selectedTask, tasks: sessionViewModel.tasks)
        }
        // Sync TreeViewModel.selectedTask → DetailViewModel whenever it changes.
        // When a ClaudeTask or OrphanedTask is selected, selectedTask is nil — clear the panel.
        .onChange(of: treeViewModel.selectedTask) { _, newTask in
            detailViewModel.setTask(newTask, tasks: sessionViewModel.tasks)
        }
    }

    // MARK: - Task Detail Content

    @ViewBuilder
    private func taskDetailContent(for task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Scrollable detail content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Header: breadcrumb trail + title + status + priority (task-88)
                    DetailHeaderView(task: task)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 12)

                    // Workflow stepper: epic and story only (task-89)
                    if task.type == .epic || task.type == .story {
                        WorkflowStepperView(task: task)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }

                    // Stats bar: only rendered when there are visible stats
                    if StatsBarView.hasVisibleStats(task: task) {
                        StatsBarView(task: task)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }

                    // Tab pill bar: horizontal scroll, left-aligned (task-90)
                    DetailTabsView(task: task)
                        .padding(.bottom, 12)

                    Divider()
                        .padding(.bottom, 16)

                    // Active tab content
                    tabContent(for: task)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                }
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
        }
    }

    // MARK: - Tab Content Router

    @ViewBuilder
    private func tabContent(for task: TaskItem) -> some View {
        let activeTab = detailViewModel.activeTab
        Group {
            switch activeTab {
            case .overview:
                OverviewTabView(task: task)
            case .description:
                DescriptionTabView(task: task)
            case .criteria:
                CriteriaTabView(task: task)
            case .planning:
                PlanningTabView(task: task)
            case .constraints:
                ConstraintsTabView(task: task)
            case .checklist:
                ChecklistTabView(task: task)
            case .verification:
                VerificationTabView(task: task)
            case .comments:
                CommentsTabView(task: task)
            }
        }
        // Force identity reset on tab change — resets @State in tab views
        .id(activeTab)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: activeTab)
    }
}

// MARK: - Preview

#Preview {
    TaskDetailView()
        .environment(SessionViewModel())
        .environment(TreeViewModel())
        .environment(DetailViewModel())
        .frame(width: 700, height: 700)
}
