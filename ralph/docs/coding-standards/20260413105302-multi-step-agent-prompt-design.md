# Multi-Step Agent Prompt Design

- **Status:** accepted
- **Date Created:** 2026-04-13 10:53
- **Last Updated:** 2026-04-13 10:53
- **Authors:**
  - River Bailey (mxriverlynn, river.bailey@testdouble.com)
- **Reviewers:**
- **Applies To:**
  - `ralph/prompts/` — all agent step prompt files

## Introduction

Guidelines for writing ralph prompt files that chain together into multi-step agent workflows. These patterns prevent agents from doing unnecessary work, ensure structured handoffs between steps, and reduce the chance of conflation between analysis and execution.

### Purpose

Multi-step agent workflows fail in predictable ways: agents over-combine analysis and implementation, continue processing when there is nothing to do, and leave intermediate files in the repo. These standards prevent those failure modes.

### Scope

All prompt files under `ralph/prompts/`. Applies equally to iteration steps (`ralph-steps.json` entries) and finalization steps.

## Background

Three recurring problems emerged during development of the ralph workflow:

1. When a single prompt asked an agent to both _analyze_ code and _fix_ the findings, it would rush the analysis or conflate the two tasks — especially under tight output pressure.
2. Agents would continue running expensive steps (writing tests, applying fixes) even when the upstream analysis produced nothing to act on.
3. Intermediate artifacts (test plans, code review notes) were occasionally committed to the repo, polluting history.

Splitting analysis from execution, adding explicit skip conditions, and using guarded file handoffs resolved all three.

## Coding Standard

### Separate Analysis from Execution

When a step both analyzes code _and_ acts on those findings, split it into two consecutive steps:
- The **analysis step** uses the heavier/smarter model (Opus). It reads the code and writes structured findings to a handoff file.
- The **execution step** uses the faster model (Sonnet). It reads the handoff file and implements.

This separation keeps each step focused, allows model selection by task type, and makes individual steps easier to retry without re-running expensive analysis.

**Correct usage:**

```markdown
<!-- test-planning.md (Opus step) -->
@progress.txt
1. Run /test-planning against commits starting with {{STARTING_SHA}}, without the edge case testing agent, and write the test plan to test-plan.md
2. Append your progress to progress.txt
3. Append all deferred work to deferred.txt
Never commit test-plan.md
Never commit progress.txt
Never commit deferred.txt
```

```markdown
<!-- test-writing.md (Sonnet step) -->
@test-plan.md
If the test-plan.md file is empty, non-existent, or otherwise says there is nothing to be done, skip to step 3.
1. Write all tests specified in test-plan.md
2. Run all tests, type checks, linting and formatting tools. Fix any issues.
3. Delete test-plan.md
4. Commit changes in a single commit.
```

**What to avoid:**

```markdown
<!-- combined step — don't do this -->
@progress.txt
1. Run /test-planning against commits starting with {{STARTING_SHA}}, and write all tests that were identified
2. Run all tests and type checks, and fix any issues.
3. Commit changes in a single commit.
```

**Project references:**
- `ralph/prompts/test-planning.md` — analysis step for tests (Opus)
- `ralph/prompts/test-writing.md` — execution step for tests (Sonnet)
- `ralph/prompts/code-review-changes.md` — analysis step for code review (Opus)
- `ralph/prompts/code-review-fixes.md` — execution step for code review (Sonnet)

---

### Include a Skip Condition for No-Op Steps

Any execution step that reads from an upstream handoff file must begin with an explicit skip condition. This allows the agent to exit cleanly when the upstream analysis found nothing to act on.

The condition should appear at the top of the prompt, immediately after the file reference, before any numbered steps.

**Correct usage:**

```markdown
@code-review.md
If the code-review.md file is empty, non-existent, or otherwise says nothing needs to be done, skip all to step 3.
1. Implement all identified items in code-review.md
2. Run all tests, type checks, linting and formatting tools. Fix any issues.
3. Delete code-review.md
4. Commit all changes in a single commit.
```

**What to avoid:**

```markdown
@code-review.md
1. Implement all identified items in code-review.md
2. Run all tests, type checks, linting and formatting tools. Fix any issues.
3. Delete code-review.md
```

**Project references:**
- `ralph/prompts/code-review-fixes.md` — skip condition before item 1
- `ralph/prompts/test-writing.md` — skip condition before item 1

---

### Use Intermediate Files as Handoffs, Guarded with "Never commit"

Pass structured data between steps by writing to a named intermediate file. The writing step creates it; the reading step deletes it after consuming it. Every prompt that touches an intermediate file must include a `Never commit <file>` directive.

The delete step must be included even in the skip path — if an execution step skips its work, it still deletes the handoff file so it does not accumulate.

**Correct usage:**

```markdown
<!-- Writing step: creates the file -->
1. Run /code-review for the changes made since commit sha {{STARTING_SHA}}, and write the full review content to code-review.md
Never commit code-review.md

<!-- Reading/consuming step: deletes after use -->
@code-review.md
If the code-review.md file is empty, non-existent, or otherwise says nothing needs to be done, skip all to step 3.
1. Implement all identified items in code-review.md
2. Run all tests, type checks, linting and formatting tools. Fix any issues.
3. Delete code-review.md
Never commit code-review.md
```

**What to avoid:**

```markdown
<!-- No "Never commit" guard — file may land in git history -->
1. Write the full review content to code-review.md
2. Implement all identified items in code-review.md
```

**Project references:**
- `ralph/prompts/code-review-changes.md` — writes `code-review.md`; includes `Never commit code-review.md`
- `ralph/prompts/code-review-fixes.md` — reads and deletes `code-review.md`
- `ralph/prompts/test-planning.md` — writes `test-plan.md`
- `ralph/prompts/test-writing.md` — reads and deletes `test-plan.md`

## Additional Resources

### Project Documentation

- [`ralph/ralph-steps.json`](../ralph-steps.json) — step definitions including model assignments per step
- [`ralph/plans/ralph-tui.md`](../plans/ralph-tui.md) — architecture decisions for the ralph orchestration system
