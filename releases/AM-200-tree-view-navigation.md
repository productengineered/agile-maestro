# AM-200: Tree View & Navigation

**23 commits** (squash-merged) | Epic branch: `epic/AM-200-tree-view-navigation`

---

## What Shipped

The app shell and primary navigation layer. After AM-100 laid the data foundation, AM-200 made it visible — a Liquid Glass toolbar, a hierarchical tree sidebar, session discovery, and all the state views needed for a functional browsing experience.

### Components Built

- **MainWindowView** — App shell with NavigationSplitView, Liquid Glass toolbar, three-pane layout
- **TaskTreeView** — Hierarchical sidebar with expand/collapse, arrow key navigation (right=expand, left=collapse), persistent expansion state per session
- **TreeRowView** — Individual tree rows with type icons, status dots, indent levels, and disclosure indicators
- **Toolbar components:**
  - ProductChipMenu — product selection dropdown
  - SessionChipMenu — session selection with auto-select of most recent
  - ViewModeSegment — tree/kanban/team mode picker
  - RefreshButton — manual refresh with time-ago display
- **State views:** EmptyStateView, EmptyTasksView, ErrorStateView, LoadingStateView, TaskDetailPlaceholder, KanbanBoardPlaceholderView, TeamPlaceholderView

### ViewModels

- **TreeViewModel** — Tree hierarchy construction, expand/collapse state, node selection, filtering
- **SessionViewModel** — Session discovery from `~/.claude/tasks/`, auto-select, file watching coordination

### Architecture

- Both ViewModels use `@Observable` macro (macOS 26+)
- Protocol-based service injection for full testability
- Orphan detection: bugs and tech debt without parent stories get their own sidebar sections
- Expansion state persists per session — switching sessions restores the tree state you left

### Tests

- 36 new unit tests (88 total after AM-100's 52)
- SessionViewModelTests: session discovery, selection, error handling
- TreeViewModelTests: hierarchy construction, expand/collapse, filtering, orphan handling

---

## Design Specs Created

Four design specifications were created during this epic and used by the developer agents:

- `planning/design/app-shell-spec.md` — MainWindowView layout, NavigationSplitView configuration
- `planning/design/toolbar-spec.md` — Liquid Glass toolbar components, chip menus, spacing
- `planning/design/tree-sidebar-spec.md` — Tree row layout, indent levels, disclosure indicators, selection states
- `planning/design/empty-states-spec.md` — All placeholder and empty state views

---

## Learnings

### Human UAT Catches What AI Review Misses

6 issues were found during human UAT that passed through the full code review → QA → product review cycle:

1. **Sandbox entitlements blocking file dialogs** — The app couldn't access `~/.claude/tasks/` without the right entitlements. No automated test caught this because the test environment has different permissions than a sandboxed app.
2. **ViewModel not wired to View** — A ViewModel was created and tested in isolation but never connected to the actual View that needed it. Tests passed because they tested the ViewModel directly.
3. **UX polish on hit targets** — Tree row tap targets were too small for comfortable use. Technically functional, aesthetically wrong.
4. **Toolbar layout spacing** — Spacing between toolbar components didn't match the design spec. Functional but visually off.
5. **Session auto-select timing** — Race condition where the tree would briefly show empty state before the most recent session was auto-selected.
6. **Expand/collapse animation** — Disclosure triangle animation was janky on first expand due to lazy loading timing.

These are exactly the kinds of issues that require running the actual app and using it as a human would. The AI team builds it. The human makes sure it actually works.

---

## Stories

| ID | Title | Summary |
|----|-------|---------|
| AM-201 | App Shell & Toolbar | MainWindowView, Liquid Glass toolbar, product/session chips |
| AM-202 | Tree Sidebar | TaskTreeView, TreeRowView, expand/collapse, arrow keys |
| AM-203 | Session Discovery | SessionViewModel, auto-select, file watching |
| AM-204 | State Views | Empty, error, loading, and placeholder states |
| AM-205 | UAT Fixes | 6 issues found during human testing |
