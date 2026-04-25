# Building an Epic: A Visual Walkthrough

This walkthrough follows a single epic — **AM-700: Detail Panel Metadata Completeness** — from backlog to completion. It shows how AgileMaestro visualizes every stage of the development lifecycle as Claude Code's AI team builds, reviews, and ships a feature.

AM-700 contains 6 stories and 21 tasks. The goal: make every metadata field from the task schema visible in the detail panel UI, with dedicated views for bug and techdebt types.

---

## 1. Backlog

Everything starts here. The epic, its stories, and all tasks are `pending` — planned but not yet approved for work.

The tree sidebar shows the full hierarchy: the epic at the top, stories nested underneath, and tasks under each story. Every item has a pending status indicator.

![Tree view showing the epic and its stories in the backlog](screenshots/01-backlog-tree-epic.png)

Clicking into a story reveals its metadata — points, sprint, labels, and the list of child tasks. All pending, waiting for approval.

![Story detail view showing pending status and child tasks](screenshots/02-backlog-tree-story.png)

The Description tab shows the full story spec — the user story, context, technical approach, and dependencies. This is what the developer agent reads when it picks up the work.

![Story description tab with user story and technical approach](screenshots/03-backlog-story-description.png)

Back at the epic level, the Planning tab lays out the execution plan — the sequence of stories, what each one delivers, and how they depend on each other. The AI team uses this to determine build order.

![Epic planning tab showing execution plan and story sequence](screenshots/04-backlog-epic-planning.png)

The Kanban board tells the same story from a different angle. Everything sits in the Backlog column. No work has started.

![Kanban board with all items in the Backlog column](screenshots/05-backlog-kanban.png)

---

## 2. Approved

The human reviews the epic plan and approves it. Every item moves from `pending` approval to `approved` — signaling to the AI team that work can begin.

On the Kanban board, everything shifts from the Backlog column to the Approved column. The epic and its stories are ready to be claimed.

![Kanban board with all items moved to the Approved column](screenshots/07-approved-kanban.png)

The tree view reflects the same state. The epic's workflow stepper shows the first stage (Dev) is next.

![Tree view showing approved epic ready for development](screenshots/06-approved-tree-epic.png)

---

## 3. In Development

The coordinator starts the build. Story AM-701 (Bug & TechDebt Model Parity) is the first story in the execution plan — no dependencies, foundational work that other stories build on.

The macOS Developer agent claims the first task, implements it, writes tests, and commits. Then the next task. The story moves to `in_progress` only after its first task is claimed. Tasks in other stories stay `pending` — they haven't started.

The Kanban board shows the spread: the epic and Story AM-701 are in the In Dev column. Two tasks are already Done. One task is actively being worked on. The remaining stories wait in the Approved column.

![Kanban board showing active development — tasks spread across In Dev and Done](screenshots/08-indev-kanban.png)

The tree view shows the same progression. The epic is `in_progress`, Story AM-701 is `in_progress` with a mix of completed and active tasks. Stories AM-702 through AM-706 are still pending.

![Tree view during active development](screenshots/09-indev-tree-epic.png)

---

## 4. Code Review

All four tasks in Story AM-701 are complete. The story automatically advances to Code Review, where the Staff Engineer agent reviews all code changes across the story as a unit.

The story detail shows `Code Review` in the workflow stepper. The review checks architecture, standards compliance, and security. CodeRabbit runs in parallel as a second reviewer.

![Story detail showing Code Review stage with all tasks completed](screenshots/10-codereview-tree-story.png)

Meanwhile, Story AM-702 has started development — its first tasks are being claimed and built. The Kanban board shows the pipeline: AM-701 in Code Review, AM-702 in Dev, tasks flowing through.

![Kanban board with Story AM-701 in Code Review, AM-702 in development](screenshots/11-codereview-kanban.png)

---

## 5. Security Review

Story AM-701 passed Code Review and QA. At the epic level, stories that pass QA advance to Security Review. Three security sub-agents run in parallel — static analysis, reasoning-based analysis, and platform-specific checks — reporting to a lead auditor who makes the pass/fail decision.

The Kanban board shows AM-701 in the Security column while development continues on other stories.

![Kanban board with Story AM-701 in Security Review](screenshots/12-security-kanban.png)

---

## 6. Human UAT

All six stories have passed through the full review cycle — Code Review, QA, Security, and Product Review. Every story is `completed`. Every task is `completed`.

The epic advances to Human UAT. This is the gate where the system stops and waits for a human to test the actual running application. No amount of automated testing replaces this step.

The workflow stepper on the epic detail shows Human UAT as the active stage — all prior stages are green.

![Epic detail showing Human UAT stage — all prior stages completed](screenshots/13-humanuat-tree-epic.png)

The Kanban board shows the epic sitting in the Human UAT column, with all stories and tasks in Done.

![Kanban board with epic in Human UAT, everything else Done](screenshots/14-humanuat-kanban.png)

---

## 7. Done

The human tests the app, confirms everything works, and approves. The epic moves to `completed`. The entire workflow stepper is green.

![Kanban board — everything in the Done column](screenshots/15-done-kanban.png)

The epic detail shows the final state: completed, all stories shipped, all review gates passed.

![Epic detail showing completed status — all stages green](screenshots/16-done-tree-epic.png)

---

## The Pipeline

What you've seen is one epic moving through the system. In practice, multiple epics run concurrently. Stories within an epic build in dependency waves — independent stories run in parallel. The Kanban board shows the full pipeline state at a glance: what's being built, what's in review, what's waiting for a human.

The cycle for every piece of work:

```
Backlog -> Approved -> In Dev -> Code Review -> QA -> Security -> Product Review -> Human UAT -> Done
                         ^                                                            |
                         +----------------------- rejection at any stage -------------+
```

Any rejection at any stage sends work back to development, and the full review cycle restarts from Code Review. The system enforces this — there are no shortcuts.

This is what structured AI development looks like. Not one agent doing everything. A coordinated team, following a process, with quality gates that actually gate.

---

*Built with the [Claude Code Apple App Toolkit](https://github.com/productengineered/claude-code-apple-app-toolkit).*
