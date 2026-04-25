# AM-310: Bug Fixes & Session Discovery

**7 commits** | Branch: `AM-310-bug-fixes-session-discovery`

---

## What Shipped

A collection of bug fixes and enhancements discovered after AM-300 shipped. Fixes session discovery so the app works without manual product configuration, resolves stale UI state issues, removes stat duplication, and adds orphan task visibility plus a child tasks table to the Story overview.

### Bug Fixes

- **Session auto-discovery (task-105):** App was stuck on empty state when `products.json` didn't exist — the expected state for Phases 1-5. `SessionViewModel.loadProducts()` now falls through to `TaskSessionService.getRecentSessions()` directly, auto-selecting the most recent session. This was a gap between the Phase 2 spec (sessions work without products) and the implementation (which gated everything behind product registration).

- **Stale detail panel (task-104):** When navigating to an empty directory, the sidebar correctly showed "No Tasks" but the detail panel kept displaying the previously selected item. `TreeViewModel.buildTree()` now clears `selectedNodeID` and `selectedTask` when the selected task isn't present in the new task set.

- **StatsBarView duplication (task-102):** Stats appeared in both the detail header (StatsBarView) and the Overview tab content. Removed StatsBarView from TaskDetailView — stats now only appear in the Overview tab where they belong.

- **Orphan tasks not visible in sidebar:** `TaskTreeView` showed "No Tasks" empty state when `rootNodes` was empty, but `rootNodes` only contains epics. Orphan bugs, tech debt, and tasks (items without a parent epic/story) were hidden behind the empty-state gate. Fixed the condition to check all node arrays, and added a new `orphanTaskNodes` bucket for parentless items of type `.task`.

### CodeRabbit Review Fixes

- **Stale state on session fallback:** `SessionViewModel` now clears `selectedProduct` and `selectedSession` before falling back to direct session discovery, preventing stale UI when `loadProducts()` re-runs.

- **Duplicated session loading logic:** Extracted `loadAndHandleSessions(logContext:errorFallback:fetch:)` helper in `SessionViewModel`, eliminating duplicated fetch→enrich→assign→select→error pattern between `loadSessionsWithoutProduct()` and `loadSessions(for:)`.

- **Orphan tasks silently dropped:** `TreeViewModel.buildOrphanNodes` was excluding tasks whose `parentId` matched an epic ID. Now uses `storyIDSet` only as valid parents for `.task` type, so tasks with epic parents are correctly classified as orphans.

- **Duplicated status-rank sorter:** Extracted `TaskStatus.sortRank` computed property in `OverviewTabView`, replacing two identical inline sorting closures in `sortedStories` and `sortedTasks`.

- **Release notes MD022 violations:** Added blank lines around Markdown headings to fix linting warnings.

### Enhancements

- **Child tasks table on Story overview (task-103):** The Epic overview had a Stories table, but Stories had no equivalent for their child tasks. Added a Tasks card to `StoryOverviewContent` with status, title, type icon, and priority columns. Mirrors the epic-to-story pattern. Extracted `TaskTableRow` component matching the existing `StoryTableRow` pattern.

---

## Files Changed

### ViewModels

- **SessionViewModel.swift** — Added `loadSessionsWithoutProduct()` fallback path in `loadProducts()`; extracted `loadAndHandleSessions` shared helper; stale state clearing on fallback paths
- **TreeViewModel.swift** — Added `orphanTaskNodes` array, `isTaskSectionExpanded`, `toggleTaskSection()`; stale selection clearing in `buildTree()`; node lookup and expand persistence updated for orphan tasks
- **DetailViewModel.swift** — Added `childTasks(of:)` helper for Story overview

### Views

- **TaskTreeView.swift** — Empty-state condition checks all node arrays; added orphan Tasks collapsible section
- **OverviewTabView.swift** — Added tasks table card to `StoryOverviewContent`; extracted `TaskStatus.sortRank` property
- **TaskTableRow.swift** *(new)* — Row component for the Story tasks table
- **TaskDetailView.swift** — Removed StatsBarView from detail header

### Tests

- **TreeViewModelTests.swift** — 3 regression tests for stale selection clearing
- **SessionViewModelTests.swift** — 3 regression tests for session auto-discovery without products

### Specs

- **detail-container-spec.md** — Removed StatsBarView from layout spec

### Workflow & Tooling

- **`base_branch` support for epics** — Epic metadata, git-workflow rules, build-engineer agent, `/complete-epic`, and `/build-epic` now support a `base_branch` field (default: `main`). Enables epics that branch from and merge back into another epic branch instead of main. Updated templates and metadata schema to require the field.

- **CodeRabbit review decoupled from staff engineer** — Code review (`/code-review`) no longer has the staff engineer run CodeRabbit directly. The coordinator now spawns a parallel `coderabbit:code-reviewer` agent alongside the staff engineer, then merges results. Reduces review time and avoids duplicate runs. Updated `staff-engineer-agent.md` and `code-review.md`.

- **`check-mcp-deps.sh` rewritten** — Added `build-epic` stage that checks all CLI tools (gitleaks, swiftlint, jq) and all MCP servers (Xcode, Peekaboo, Aikido, Trivy). Hard fails on exit 1. Replaced fragile `.mcp.json` / settings.json grep checks with a unified `claude mcp list` helper.

- **`/complete-epic` — no untracked failures gate** — Epic completion now requires every test failure to either be fixed or have a filed Bug/TechDebt task. Pre-existing failures that aren't caused by the epic get tracked but don't block closure.

- **`save-review.sh` — branch-scoped output** — Review outputs now save to `tools/third-party-reviews/<branch>/` subdirectories instead of flat filenames, grouping reviews by epic.

- **Discovery agent** — Added `AskUserQuestion` to the tool list so it can conduct interactive Q&A during `/discover`.

---

## Bugs & Tasks

| ID | Type | Title |
|----|------|-------|
| task-102 | Bug | StatsBarView in header bar duplicates Overview tab stats |
| task-103 | TechDebt | Add child tasks table to Story overview tab |
| task-104 | Bug | Detail panel shows stale task when sidebar is empty |
| task-105 | Bug | App stuck in idle state when no products.json exists |
