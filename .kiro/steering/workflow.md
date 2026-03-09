---
inclusion: auto
description: Workflow orchestration rules for planning, execution, verification, and task management
---

# Workflow Orchestration

## Planning

- Enter plan mode for any non-trivial task (3+ steps or architectural decisions).
- If something goes sideways, stop and re-plan immediately. Don't keep pushing.
- Use plan mode for verification steps, not just building.
- Write detailed specs upfront to reduce ambiguity.

## Subagent Strategy

- Use subagents liberally to keep the main context window clean.
- Offload research, exploration, and parallel analysis to subagents.
- For complex problems, throw more compute at it via subagents.
- One task per subagent for focused execution.

## Self-Improvement Loop

- After any correction from the user, update `tasks/lessons.md` with the pattern.
- Write rules that prevent the same mistake from recurring.
- Iterate on these lessons until the mistake rate drops.
- Review lessons at session start for the relevant project.

## Verification Before Done

- Never mark a task complete without proving it works.
- Diff behavior between main and your changes when relevant.
- Ask yourself: "Would a staff engineer approve this?"
- Run tests, check logs, demonstrate correctness.

## Elegance (Balanced)

- For non-trivial changes, pause and ask "is there a more elegant way?"
- If a fix feels hacky: "Knowing everything I know now, implement the elegant solution."
- Skip this for simple, obvious fixes. Don't over-engineer.
- Challenge your own work before presenting it.

## Autonomous Bug Fixing

- When given a bug report, just fix it. Don't ask for hand-holding.
- Point at logs, errors, failing tests, then resolve them.
- Zero context switching required from the user.
- Fix failing CI tests without being told how.

## Task Management

1. Write a plan to `tasks/todo.md` with checkable items.
2. Check in before starting implementation.
3. Mark items complete as you go.
4. Provide a high-level summary at each step.
5. Add a review section to `tasks/todo.md` when done.
6. Update `tasks/lessons.md` after corrections.

## Core Principles

- Simplicity first. Make every change as simple as possible. Minimal code impact.
- No laziness. Find root causes. No temporary fixes. Senior developer standards.
- Minimal impact. Changes should only touch what's necessary. Avoid introducing bugs.
