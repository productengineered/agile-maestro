# AM-100: Project Scaffold & Data Layer

**14 commits** (squash-merged) | Epic branch: `epic/AM-100-project-scaffold`

---

## What Shipped

The foundation. Xcode project, full model layer, service layer, and 52 unit tests. Nothing visible to the user yet — this epic is entirely infrastructure. Every subsequent epic builds on the parsing, session discovery, and data models created here.

### Xcode Project

- AgileMaestro.xcodeproj targeting macOS 26.0 (Tahoe)
- App entitlements for file access
- SwiftLint configuration (`.swiftlint.yml`)
- Core Data stack (`AgileMaestro.xcdatamodeld`) ready for persistence features
- UI test target scaffolded

### Model Layer (30 types)

Full representation of the Claude Code task JSON schema v2.0:

- **Core types:** TaskItem, TaskSession, TreeNode, Product, ViewMode
- **Task metadata:** TaskMetadataContainer, TaskSpecificMetadata, EpicMetadata, StoryMetadata
- **Enums:** TaskStatus, TaskType (epic, story, task, bug, techdebt)
- **Nested structures:** AcceptanceCriteriaItem, Comment, DefinitionOfDone, Dependencies, Estimate, ExecutionPlan, References, RiskItem, StoryReference, TaskReference, SuccessMetrics, SuggestedInput, TimelineDay, ReviewInfo, GitInfo, DesignAsset
- **Supporting:** AnyCodableValue (type-erased JSON), KanbanCard, TeamManifest

All models use resilient decoding — malformed or partially complete task JSON files parse gracefully instead of crashing. This was a deliberate design choice: Claude Code task files are written by AI agents and frequently have missing fields, unexpected types, or schema version mismatches.

### Service Layer (6 services, all protocol-based)

- **TaskParserService** — Reads and decodes task JSON files from disk
- **TaskSessionService** — Discovers available sessions from `~/.claude/tasks/`
- **ProductService** — Product CRUD with UserDefaults persistence
- **BackupService** — Task state backup and restore
- **ManifestService** — Team manifest parsing
- **FileWatcherService** — FSEvents-based file watching for live task updates

Every service has a corresponding protocol (`TaskParserServiceProtocol`, etc.) enabling full dependency injection and testability.

### Utilities

- **ResilientDecoding** — Custom JSON decoding that handles missing keys, wrong types, and partial data without throwing
- **MarkdownSectionParser** — Extracts structured sections from markdown text
- **ClaudeDirectoryResolver** — Resolves `~/.claude/` path across environments
- **CGFloat+DesignSystem** — Design system spacing constants on a 4pt grid
- **Logger+Categories** — os.Logger categories for structured logging

### Tests

52 unit tests covering:
- TaskItemDecodingTests (31 tests) — exhaustive JSON decoding including malformed data, missing fields, type mismatches
- TaskParserServiceTests — file reading, directory scanning, error handling
- TaskSessionServiceTests — session discovery, sorting, edge cases
- ProductServiceTests — CRUD operations, persistence
- BackupServiceTests — backup creation, restore, file management
- FileWatcherServiceTests — event detection, debouncing, cleanup
- MarkdownSectionParserTests — section extraction, edge cases

---

## Architecture Decisions

### Resilient Decoding Over Strict Validation

Task JSON files are written by AI agents. They frequently have:
- Missing optional fields (agent forgot to include them)
- Wrong types (string where number expected)
- Extra fields from newer schema versions
- Partially written files (agent interrupted mid-write)

Rather than failing on any malformation, the parser uses resilient decoding: every field has a sensible default, type mismatches are handled gracefully, and partial files produce partial (but usable) TaskItem objects. This means the app never crashes on bad data — it just shows what it can.

### Protocol-Based Services

Every service conforms to a protocol. This adds boilerplate but enables:
- Unit testing with mock services (no file system or network needed)
- Dependency injection via initializer
- Swappable implementations (e.g., in-memory vs. disk-based)

This pattern carries through every subsequent epic.

---

## Stories

| ID | Title | Summary |
|----|-------|---------|
| AM-101 | Xcode Project Setup | Project creation, targets, entitlements, SwiftLint |
| AM-102 | Model Layer | All 30 model types with resilient decoding |
| AM-103 | Service Layer | 6 services with protocols and DI |
| AM-104 | Unit Tests | 52 tests across all services and models |
