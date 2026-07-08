# AgileMaestro

A native macOS SwiftUI application that visualizes Claude Code task files as a full agile project management board. It reads the JSON task files from `~/.claude/tasks/` and renders them as a browsable hierarchy — epics, stories, tasks — the same way you'd track work in Jira or Linear.

Built entirely by an AI development team powered by the [Claude Code Apple App Toolkit](https://github.com/productengineered/claude-code-apple-app-toolkit) (not yet public).

---

## How It Was Built

This app was built using a structured `.claude/` directory that turns Claude Code into a full development team. Not metaphorically. A product manager, a designer, developers, a staff engineer doing code review, a QA tester, a security audit team, a build engineer, and a documentation writer. All config files. All doing their jobs. All shipping this production macOS app.

The toolkit — 17 specialized agents, 45+ slash commands, 30+ skills, 15 rule files, 18 scripts, and 5 hooks — now lives in its own repo:

**[claude-code-apple-app-toolkit](https://github.com/productengineered/claude-code-apple-app-toolkit)**

This repo is the app. The toolkit repo is the team that built it.

---

## The App

AgileMaestro is a native macOS 26 (Tahoe) SwiftUI application. It reads Claude Code task JSON files from `~/.claude/tasks/` and renders them as a browsable hierarchy. It's being built by the toolkit, and it visualizes the toolkit's output. Recursive in the best way.

### Current State

- Liquid Glass toolbar with product/session selection
- Hierarchical tree sidebar (epics > stories > tasks) with expand/collapse
- Kanban board with 9 workflow columns, filter bar, and card-to-tree navigation
- Team view with agent roster (grouped cards, search, expand/collapse), workflow train map (3 pipeline visualizations), and directory health dashboard (animated counters)
- Detail panel with 8 tab views, breadcrumb navigation, workflow stepper, and metadata cards
- Claude Tasks and Orphaned Tasks sidebar sections with detail views
- Product CRUD (create, edit, delete) with persistent selection
- Native Swift ManifestService parsing `.claude/` directories (no Python dependency)
- Session discovery with auto-select of most recent session
- Empty, error, and loading states throughout
- Arrow key navigation (right=expand, left=collapse)
- 298 unit tests passing

### Architecture

- **MVVM** with `@Observable` macro (macOS 26+)
- **async/await** throughout (no Combine)
- **Core Data** stack (ready for persistence features)
- **Protocol-based services** with dependency injection for full testability
- **Xcode 26.3 MCP bridge** for build/test/preview when Xcode is running

---

## The Workflow

Every piece of work follows the same cycle. No shortcuts, no skipping steps.

```
Discovery > Epic > Stories & Tasks > Design > Build > Code Review > QA > Product Review > Ship
                                                 ^                                    |
                                                 +-------- rejection at any stage ----+
```

The toolkit defines 17 specialized agents. Each one has a specific role, a specific model assignment (Opus for deep reasoning, Sonnet for everything else), and detailed instructions for how to do its job.

| Agent | Role | What They Do |
|-------|------|-------------|
| **PM** | Product Manager | Discovery Q&A, epic creation, final product review gate |
| **Planning** | Architect | Creates epics from planning docs with 25+ metadata fields |
| **Designer** | UI/UX | Produces SwiftUI skeleton code with exact design system values |
| **Staff Engineer** | Tech Lead | Code review, architecture decisions, story breakdown |
| **macOS Developer** | Builder | Claims tasks, implements, writes tests, commits |
| **Data Architect** | DB Specialist | Core Data models, migrations, data integrity |
| **QA** | Test Engineer | Tests against acceptance criteria with edge case coverage |
| **Security Audit** | Lead Auditor | Coordinates 3 sub-agents for static, reasoning, and platform analysis |
| **Build Engineer** | DevOps | Git operations, builds, archives, PR creation |
| **Documentation** | Tech Writer | Module specs, ADRs, changelogs |
| **RCA** | Bug Investigator | Root cause analysis — reads and traces, never implements |

Plus 5 security sub-agents, a UI audit agent, and a visual QA agent.

For the full agent instructions, rules, and workflow details, see the [toolkit repo](https://github.com/productengineered/claude-code-apple-app-toolkit).

---

## Build Log

A living record. Updated as each epic ships.

### Completed

**AM-100: Project Scaffold & Data Layer** — ([release notes](releases/AM-100-scaffold-data-layer.md))
- Xcode project targeting macOS 26
- Full model layer with resilient JSON decoding (handles malformed task files gracefully)
- Service layer: task parsing, session discovery, file watching, product management
- 52 unit tests

**AM-200: Tree View & Navigation** — ([release notes](releases/AM-200-tree-view-navigation.md))
- App shell with Liquid Glass toolbar
- TreeViewModel + SessionViewModel with full service wiring
- Hierarchical tree sidebar with expand/collapse and persistent state per session
- Toolbar components: product/session chips, view mode picker, refresh with time-ago
- Empty, error, loading, and placeholder state views
- 36 additional unit tests (88 total)

**AM-300: Detail Panel, Tab Views & Shared Components** — ([release notes](releases/AM-300-detail-panel.md))
- TaskDetailView container with StatsBarView and interactive breadcrumb navigation
- WorkflowStepperView with 11 visual states, type-adapted stage counts
- 8 specialized tab views: Overview, Description, Criteria, Planning, Constraints, Checklist, Verification, Comments
- 10+ shared reusable components (CardView, CollapsibleCardView, badges, avatars, FlowLayout)
- MarkdownSectionParser for structured description rendering

**AM-400: Kanban Board, Columns, Cards & Filter Bar** — ([release notes](releases/AM-400.md))
- Horizontal scrolling kanban board with 9 workflow columns (Backlog through Done)
- KanbanViewModel with column assignment engine, cascade inheritance, and two-pass transformation
- Cards with type icon, priority badge, status accent bar, and review stage badges
- Filter bar with type segmented picker and epic dropdown filter
- Card-to-tree navigation via `revealTask(_:)`
- 73 additional unit tests (161 total)

**AM-500: Team View — Agent Roster, Workflow Train Map & Directory Health** — ([release notes](releases/AM-500.md))
- Team view with NavigationSplitView, Liquid Glass sidebar, and 3 detail sections
- Agent roster with grouped cards by role (Core Team, Specialists, Security), live search, expand/collapse
- Workflow train map with 3 pipeline visualizations (Epic 8-stage, Story 5-stage, Task 3-stage)
- Directory health dashboard with Timer-driven animated counters and reduce-motion support
- Native Swift ManifestService replacing Python dependency
- 137 additional unit tests (298 total)

**AM-600: Product Management** — CRUD operations, session wiring, UAT bug fixes

**AM-700: Detail Panel Metadata Completeness** — ([release notes](releases/AM-700.md))
- Bug and TechDebt model parity with dedicated overview content views
- Stats bar and tab enhancements (comment count badges, sprint/complexity/risk pills)
- Cross-cutting overview enhancements (blocks card, epic goal callout, header metadata)
- Integration tests for end-to-end JSON decoding

**AM-800: Claude Tasks & Orphaned Tasks Sidebar Sections**
- Three-category parser (TaskItem, ClaudeTask, OrphanedTask)
- Collapsible sidebar sections with persistent expand/collapse state
- Detail views for Claude tasks and orphaned tasks with router wiring
- Topological sort for dependency ordering

---

## Run It

### Prerequisites

- macOS 26.0+ (Tahoe)
- Xcode 26.3+

### Build

```bash
git clone https://github.com/productengineered/agile-maestro.git
cd agile-maestro/app
open AgileMaestro.xcodeproj
# Build and run (Cmd+R)
```

### Use the Toolkit

The toolkit that built this app is available separately:

**[claude-code-apple-app-toolkit](https://github.com/productengineered/claude-code-apple-app-toolkit)**

It's tuned for macOS SwiftUI apps — the agents reference SwiftUI patterns, the rules enforce Swift conventions, the design system targets macOS 26 Tahoe, and the build scripts wrap `xcodebuild`. The workflow patterns (`/build-epic`, `/build-story`, `/code-review`, the full review cycle) are platform-agnostic and work with any project that uses Claude Code Tasks.

---

## Standing on Shoulders

**[Axiom](https://github.com/CharlesWiltgen/Axiom)** by Charles Wiltgen — A Claude Code plugin with battle-tested skills for xOS development. Liquid Glass implementation, accessibility auditing, SwiftUI performance profiling, Swift 6 concurrency patterns, and Apple documentation access via MCP. Axiom is iOS/iPadOS-focused; AgileMaestro targets macOS. But Axiom was the starting reference for what a design skill should contain and how to structure domain-specific knowledge for agent consumption.

If you're building for iOS or iPadOS, start with Axiom. If you're building for macOS, start with the [toolkit](https://github.com/productengineered/claude-code-apple-app-toolkit).

---

## License

MIT

---

*Built with [Claude Code](https://claude.ai/claude-code) by Anthropic.*
