# AM-300: Detail Panel, Tab Views & Shared Components

**18 commits** | Epic branch: `epic/AM-300-detail-panel`

---

## What Shipped

A full detail panel system that renders type-specific content for epics, stories, tasks, bugs, and tech debt. Selecting any item in the tree sidebar now opens a rich tabbed view with everything you'd expect from a project management tool.

### Components Built

- **TaskDetailView** container with StatsBarView showing key metrics
- **DetailHeaderView** with interactive breadcrumb trail (Epic > Story > Task) — clicking a parent navigates to that item
- **WorkflowStepperView** with 11 visual states, type-adapted stage counts (6 for epics, 4 for stories)
- **DetailTabsView** pill bar with left-aligned fixed pills maintaining intrinsic size
- **8 tab content views:**
  - Overview — type-specific summary with key metadata
  - Description — rendered via MarkdownSectionParser with unstructured fallback
  - Criteria — single-expand accordion for acceptance criteria
  - Planning — execution plan, estimates, dependencies
  - Constraints — implementation constraints and out-of-scope items
  - Checklist — ephemeral toggle state for granular steps
  - Verification — local checks and completion signal
  - Comments — 12 type-specific colors with UNRESOLVED badge for trackable rejections
- **10+ shared components:** CardView, CollapsibleCardView, CollapsibleSectionView, AgentAvatarView, ProgressBarView, FlowLayout, StatPillView, StatusPill, PriorityBadgeView, ImpactBadgeView, LabelBadgeView, TypeIconView

### Architecture

- DetailViewModel manages tab selection with type-specific tab availability
- MarkdownSectionParser utility extracts structured sections from markdown descriptions with graceful unstructured fallback
- All shared components designed for reuse by Kanban (Phase 4) and Team (Phase 5)
- Graceful null/missing metadata handling across all tabs

---

## `.claude/` Directory Updates

### New: `check-mcp-deps.sh` Pre-Flight Script

A mandatory pre-flight check that verifies MCP server availability (Xcode, Peekaboo, CodeRabbit) before agents are spawned. Both `/build-epic` and `/build-story` now run this before starting any work. If MCP servers are missing, the script reports what's degraded and asks the user whether to proceed with fallbacks or fix first. This prevents agents from silently skipping visual QA, screenshots, or build tools.

### Updated: Peekaboo Fallback Policy

Changed from "silently skip and don't fail" to explicit, per-agent warnings:
- **Visual QA agent:** Hard block — cannot function without Peekaboo
- **QA agent:** Warning in review comment header that only headless tests ran
- **Designer/Developer agents:** Warning in task comments that screenshots were skipped

Previously, agents would quietly skip visual checks and report success. Now unavailability is surfaced prominently so humans know what was and wasn't tested.

### Removed: `/synthesis-review` Command

The separate synthesis review step (310 lines) was folded into the Planning Agent itself. Decision persistence now lives in `planning/reviews/decisions.md`, written automatically during `/epic` runs. The workflow simplified from `/external-review` → `/synthesis-review` → `/epic` to just `/external-review` → `/epic`.

### Updated: Planning Agent

- Now has Write and Edit tools (was previously read-only)
- Writes all Q&A decisions to `planning/reviews/decisions.md` after epic creation
- Future `/epic` runs read prior decisions and skip already-answered questions
- Decision persistence format includes phase, question, decision, and rationale

### Updated: `/epic` Command

Significantly slimmed down — moved detailed schema documentation, field definitions, and expected output format into the Planning Agent where it belongs. The command file is now a lean coordinator script, not a 300-line reference document.

### Updated: `/build-epic` Command

- **Untracked test failure gate:** Epic can't close if tests fail without either a fix (if caused by this epic) or a filed Bug/TechDebt task (if pre-existing). Prevents sweeping failures under the rug.
- **Base branch support:** Reads `base_branch` from epic metadata instead of hardcoding `main`. Enables nested or non-main branch strategies.

---

## Learnings

### QA and UI Testing Conflicts with Desktop Use

Peekaboo, accessibility inspector, and UI automation tools take control of the mouse, keyboard, and screen focus. If you're using the Mac while QA or visual QA agents run, the tests and your activity interfere with each other — missed clicks, wrong window focus, flaky screenshots, false failures.

**Best practice: run development on a dedicated machine or VM.** The development Mac should be hands-off during agent work so MCPs like Peekaboo can operate uninterrupted. This is especially important during `/build-epic` runs where visual QA happens automatically after each story completes.

This isn't a limitation of the toolkit — it's a limitation of macOS UI automation itself. Any tool that drives the screen (Peekaboo, XCUITest, Instruments) has this constraint. Plan accordingly.

---

## Stories

| ID | Title | Tasks |
|----|-------|-------|
| AM-301 | Shared Components & Utilities | 4 tasks (CardView, badges, avatars, DetailViewModel) |
| AM-302 | Detail Panel Container, Header, Stepper & Tab Bar | 4 tasks (TaskDetailView, header, stepper, tabs) |
| AM-303 | Overview & Description Tab Views | 2 tasks (OverviewTabView, DescriptionTabView) |
| AM-304 | Criteria, Planning & Constraints Tab Views | 3 tasks (CriteriaTabView, PlanningTabView, ConstraintsTabView) |
| AM-305 | Checklist, Verification & Comments Tab Views | 3 tasks (ChecklistTabView, VerificationTabView, CommentsTabView) |
