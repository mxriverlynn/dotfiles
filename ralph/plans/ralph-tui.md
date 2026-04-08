# Plan: `ralph-tui` — Go/Glyph TUI for Ralph Loop

## Context

The `ralph-loop` bash script runs multiple sequential `claude` CLI calls, capturing all output into `$RESULT` and displaying it after-the-fact with `box-text`. This makes it impossible to see what's happening during long-running steps. We're building a Go program using [Glyph](https://useglyph.sh/) that replaces `ralph-loop` as the orchestrator, streaming claude output in real-time into a bordered, scrolling TUI panel with full workflow visibility.

---

## Layout

```
┌─ Ralph ──────────────────────────────────────────────────────────────────────┐
│                                                                              │
│  Iteration 1/3 — Issue #42: Add widget support                               │
│                                                                              │
│  [✓] Feature work    [✓] Test plan    [▸ Test writing]    [ ] Code review    │
│  [ ] Review fixes    [ ] Close issue  [ ] Update docs     [ ] Git push       │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  I'll start by examining the existing test files to understand the           │
│  patterns used in this project...                                            │
│                                                                              │
│  Reading src/widget.test.ts...                                               │
│  The test suite uses vitest with the following structure:                    │
│  - describe blocks for each public method                                    │
│  - beforeEach for shared setup                                               │
│                                                                              │
│  I'll create tests for the three new methods added in the feature            │
│  work step...                                                                │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│  ↑/k up  ↓/j down  n next step  q quit                                       │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Three sections, top to bottom:

**1. Status header (fixed height)**
- Current iteration and total: `Iteration 1/3`
- Issue being worked: `Issue #42: Add widget support`
- Step tracker with checkboxes across two rows showing all 8 steps per iteration
- Status indicators: `[✓]` done, `[▸ ...]` active (with spinner), `[ ]` pending

**2. Output log (fills remaining space, scrollable)**
- Streams claude stdout line-by-line as it arrives
- Auto-scrolls to bottom as new lines appear
- User can scroll up with `↑`/`k` — when scrolled up, auto-scroll pauses
- Scrolling back to the bottom re-enables auto-scroll
- Step transitions insert a visual separator: `── Test writing ─────────────`
- All steps' output accumulates in one continuous log (scroll up to see earlier steps)

**3. Keyboard shortcut bar (fixed, 1 line)**
- Shows available keys: `↑/k up  ↓/j down  n next step  q quit`
- Always visible at the bottom

### Error state

When a step fails (non-zero exit from `claude` or any subprocess), the TUI switches to an error mode:

```
├──────────────────────────────────────────────────────────────────────────────┤
│  ✗ Step "Test writing" failed (exit code 1)                                  │
│                                                                              │
│  ... last lines of output visible above in log ...                           │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│  c continue to next step  r retry step  q quit                               │
└──────────────────────────────────────────────────────────────────────────────┘
```

- The step checkbox shows `[✗]` 
- Shortcut bar changes to show error-specific keys
- `c` — skip this step, continue to the next one
- `r` — retry the failed step from scratch
- `q` — quit (with confirmation)

### Quit confirmation

Pressing `q` at any time shows a confirmation overlay or replaces the shortcut bar:

```
├──────────────────────────────────────────────────────────────────────────────┤
│  Quit ralph? (y/n)                                                           │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Glyph Component Mapping

```go
VBox(
    // Section 1: Status header
    VBox(
        Text(&iterationLine),           // "Iteration 1/3 — Issue #42: ..."
        HBox(stepCheckboxRow1...),      // first 4 steps
        HBox(stepCheckboxRow2...),      // next 4 steps
    ).Border(BorderRounded).Title("Ralph"),

    // Section 2: Scrollable output log
    // logReader is the read end of an io.Pipe(); subprocess output is written to the write end
    Log(logReader).Grow(1).MaxLines(5000).BindVimNav().OnUpdate(app.RequestRender),

    // Section 3: Keyboard shortcuts
    VBox(
        Text(&shortcutLine),            // "↑/k up  ↓/j down  n next step  q quit"
    ).Border(BorderRounded),
)
```

Key Glyph features:
- **`Log(io.Reader)`** — takes an `io.Reader`, NOT a `*[]string`. Glyph spawns its own internal goroutine to read lines via `bufio.Scanner` and manages its own `sync.Mutex` internally. This means the plan's subprocess streaming architecture must change: instead of appending to a shared slice, pipe subprocess output through an `io.Reader` (e.g., `io.Pipe`) that Glyph consumes directly.
- **`.Grow(1)`** — fills remaining vertical space
- **`.MaxLines(n)`** — ring buffer, default 10000
- **`.AutoScroll(bool)`** — auto-follows new content, pauses when user scrolls up
- **`.BindVimNav()`** — wires j/k (line), Ctrl-d/u (half-page), g/G (top/bottom) automatically
- **`.OnUpdate(func())`** — callback when new lines arrive; use with `app.RequestRender`
- **`Border(BorderRounded)`** — handles all box drawing (replaces `box-text`)
- **`Spinner`** — next to the active step name for visual activity indication
- **Pointer-based reactivity** — for `Text`, `Checkbox`, etc. (NOT for `Log` — it uses `io.Reader`)

---

## Internal Architecture

### Orchestration goroutine

A single goroutine runs the workflow (replicated from `ralph-loop` logic):

1. Display `ralph-art.txt` contents in the output log as a startup banner
2. Get GitHub username via `gh api user`
2. Loop N iterations:
   a. Get next issue via `gh` CLI
   b. Get current git SHA
   c. Run each step sequentially (spawn subprocess, stream output, wait for exit)
3. Run finalization steps (deferred work, lessons learned, final push)
4. Display completion summary: "Ralph completed after N iteration(s) and 3 finalizing tasks."

If `get_next_issue` returns an empty string (no issues labeled "ralph" assigned to the user), the orchestration goroutine should log a message to the TUI output, mark the iteration as skipped, and exit the loop early — mirroring `ralph-loop`'s behavior at line 43-46.

This goroutine communicates with the TUI by mutating shared state (which Glyph reads via pointers).

### Finalization phase

After all iterations complete, the orchestration goroutine runs three finalization steps (not part of the per-iteration step list):

1. **Deferred work** — `claude --permission-mode acceptEdits --model sonnet -p <deferred-work.md>` (no ISSUENUMBER/STARTINGSHA prepended)
2. **Lessons learned** — `claude --permission-mode acceptEdits --model sonnet -p <lessons-learned.md>` (no ISSUENUMBER/STARTINGSHA prepended)
3. **Final git push** — `git push`

During finalization, the status header switches to show `Finalizing 1/3`, `2/3`, `3/3` instead of an iteration number. The step tracker row is replaced with the three finalization step names.

These finalization steps are defined separately from `ralph-steps.json` — either as a second JSON array (`ralph-finalize-steps.json`) or as a hardcoded list, since they are fixed and few.

### Command template variables

Non-claude step commands may contain `{{ISSUE_ID}}` which is replaced at runtime with the current issue number before execution. This allows `close_gh_issue` to receive the issue number as an argument.

Script paths in commands (e.g., `scripts/close_gh_issue`) are resolved relative to `ralphDir` (the ralph directory, parent of `ralph-tui/`), not relative to the executable or the working directory. The orchestration code prepends `ralphDir` to script paths before execution.

Non-claude steps (git push, close_gh_issue) must also capture stderr — the bash script uses `2>&1` on these commands. For non-claude subprocess execution, use the same pipe-merging approach as claude steps so error output appears in the TUI log.

### Working directory

All subprocesses (`claude`, `git push`, scripts) must run with `cmd.Dir` set to the user's current working directory (the target repo being worked on), not the ralph directory. This matches how `ralph-loop` works — it's invoked from the target repo and all commands inherit that cwd. The TUI captures `os.Getwd()` at startup and passes it to all subprocess calls.

### Subprocess streaming

```go
// logReader and logWriter are created once at startup via io.Pipe().
// logReader is passed to Glyph's Log() component; logWriter is shared across all steps.
// Glyph's Log internally spawns its own goroutine with bufio.Scanner and its own sync.Mutex,
// so no external synchronization is needed — just write to logWriter.

ctx, cancel := context.WithCancel(context.Background())
cmd := exec.CommandContext(ctx, "claude", "--permission-mode", "acceptEdits", "--verbose", "--model", model, "-p", prompt)
cmd.Dir = workingDir  // must run in the target repo, not in ralph-tui/

// Capture both stdout and stderr via separate pipes, merged by two goroutines
// writing to the shared logWriter (and the file logger).
// Do NOT use io.MultiReader — it reads sequentially, hiding stderr until process exits.
stdoutPipe, _ := cmd.StdoutPipe()
stderrPipe, _ := cmd.StderrPipe()
cmd.Start()

var wg sync.WaitGroup
forwardPipe := func(pipe io.ReadCloser) {
    defer wg.Done()
    scanner := bufio.NewScanner(pipe)
    scanner.Buffer(make([]byte, 256*1024), 256*1024)
    for scanner.Scan() {
        line := scanner.Text()
        fmt.Fprintln(logWriter, line)   // Glyph's Log reads this via logReader
        fileLogger.Log(stepName, line)  // also write to the log file
    }
}

wg.Add(2)
go forwardPipe(stdoutPipe)
go forwardPipe(stderrPipe)

wg.Wait()    // both pipes must be fully read before Wait()
cmd.Wait()   // collect exit code (safe only after pipes are drained)
cancel()     // clean up context
```

The `cancel` function is stored by the orchestration goroutine so that keyboard handlers (`n` to skip, `q` to quit) can trigger subprocess termination (see "Subprocess termination" below).

**No shared slice or external mutex needed.** Glyph's `Log` component owns its own internal `[]string` buffer and `sync.Mutex`. The orchestration code simply writes lines to the `io.PipeWriter` end, and Glyph's internal `readLoop` goroutine consumes them safely.

> **Note:** The `--verbose` flag is intentionally added for the TUI (not present in `ralph-loop`) to provide richer streaming output during real-time display.

### Subprocess termination

When the user presses `n` (skip step) or confirms `q` (quit), the currently running subprocess must be terminated cleanly:

1. Call `cancel()` on the step's context — this sends SIGKILL via `exec.CommandContext`
2. Alternatively, for a gentler shutdown: call `cmd.Process.Signal(syscall.SIGTERM)`, wait up to 3 seconds, then `cmd.Process.Kill()` if still running
3. The scanner goroutines will exit naturally when the pipes close
4. `wg.Wait()` and `cmd.Wait()` will return, allowing the orchestration goroutine to proceed

**Partial state after termination:** A killed `claude` subprocess may have left uncommitted file changes or partial commits. The plan does NOT automatically roll back — the user pressed `n` intentionally and the next step (or a retry) will see the current state. If the user wants a clean slate, they can quit and manually reset.

### Retry cleanup

When the user presses `r` to retry a failed step:

- The step is re-run from its current state — no automatic `git reset` or rollback
- `STARTING_SHA` is NOT refreshed (it still represents the SHA at the start of the iteration, which is correct — prompts reference it for diffing)
- Output from the failed attempt remains in the log (scroll up to see it); a separator line marks the retry: `── Test writing (retry) ─────────────`
- For idempotent steps (`git push`, `close_gh_issue`), retry is always safe
- For claude steps, the retry runs claude again with the same prompt; claude will see the current file state including any partial changes from the failed attempt

### Signal handling

The TUI must handle SIGINT and SIGTERM gracefully:
- Cancel the current subprocess context (triggering subprocess termination)
- Wait for scanner goroutines to drain
- Flush and close the log file
- Restore terminal state (Glyph likely handles this, but verify)

### Step definitions loaded from JSON

Steps are loaded from a `ralph-steps.json` file located next to the compiled `ralph-tui` executable. The executable finds its own directory at startup using `os.Executable()` (with `filepath.EvalSymlinks` to handle symlinked binaries) and reads the JSON from there. The parent of this directory is `ralphDir` — the root ralph directory used for resolving `prompts/`, `scripts/`, and `logs/`.

```go
type Step struct {
    Name        string   `json:"name"`
    Model       string   `json:"model,omitempty"`       // "sonnet" or "opus"
    PromptFile  string   `json:"promptFile,omitempty"`   // path relative to prompts/
    IsClaude    bool     `json:"isClaude"`               // false for git push, close issue
    Command     []string `json:"command,omitempty"`      // for non-claude steps
    PrependVars bool     `json:"prependVars,omitempty"`  // true for iteration steps, false for finalization
}

func loadSteps() ([]Step, error) {
    exePath, _ := os.Executable()
    exePath, _ = filepath.EvalSymlinks(exePath)  // resolve symlinks
    exeDir := filepath.Dir(exePath)
    // Note: os.Executable() returns a temp path when using `go run`.
    // During development, use `go build && ./ralph-tui` or pass a -ralph-dir flag.
    data, err := os.ReadFile(filepath.Join(exeDir, "ralph-steps.json"))
    if err != nil {
        return nil, fmt.Errorf("could not read ralph-steps.json: %w", err)
    }
    var steps []Step
    if err := json.Unmarshal(data, &steps); err != nil {
        return nil, fmt.Errorf("could not parse ralph-steps.json: %w", err)
    }
    return steps, nil
}
```

**`ralph-steps.json`** (default, lives next to the executable):

```json
[
    {"name": "Feature work",  "model": "sonnet", "promptFile": "feature-work.md",       "isClaude": true, "prependVars": true},
    {"name": "Test planning", "model": "opus",   "promptFile": "test-planning.md",       "isClaude": true, "prependVars": true},
    {"name": "Test writing",  "model": "sonnet", "promptFile": "test-writing.md",        "isClaude": true, "prependVars": true},
    {"name": "Code review",   "model": "opus",   "promptFile": "code-review-changes.md", "isClaude": true, "prependVars": true},
    {"name": "Review fixes",  "model": "sonnet", "promptFile": "code-review-fixes.md",   "isClaude": true, "prependVars": true},
    {"name": "Close issue",   "isClaude": false,  "command": ["scripts/close_gh_issue", "{{ISSUE_ID}}"]},
    {"name": "Update docs",   "model": "sonnet", "promptFile": "update-docs.md",         "isClaude": true, "prependVars": true},
    {"name": "Git push",      "isClaude": false,  "command": ["git", "push"]}
]
```

### Prompt building

Same logic as the bash script — reads the prompt file. For iteration steps, prepends `ISSUENUMBER=` and `STARTINGSHA=`. For finalization steps, the prompt content is used as-is (no variables prepended).

> **Note on `\n`:** The bash script constructs prompts with literal two-character `\n` (not actual newlines) via `PROMPT="ISSUENUMBER=$ISSUE_ID\n"`. The Go version uses `fmt.Sprintf` with real newlines, which is arguably more correct. Claude CLI handles both, so this behavioral difference is harmless.

#### Step pipeline dependencies

Some steps produce intermediate files consumed by later steps — all in the working directory:
- **Test planning** creates `test-plan.md` → **Test writing** reads `@test-plan.md` and deletes it
- **Code review** creates `code-review.md` → **Review fixes** reads `@code-review.md` and deletes it
- Multiple steps append to `progress.txt` (never committed, cleared by lessons-learned finalization)
- **Feature work** appends to `deferred.txt` (never committed, consumed by deferred-work finalization)

These dependencies are encoded in the prompt files themselves, not in the TUI. The TUI does not need to manage these files directly — Claude CLI handles `@file` references.

```go
promptContent, _ := os.ReadFile(filepath.Join(ralphDir, "prompts", step.PromptFile))
var prompt string
if step.PrependVars {
    prompt = fmt.Sprintf("ISSUENUMBER=%s\nSTARTINGSHA=%s\n%s", issueID, startingSHA, promptContent)
} else {
    prompt = string(promptContent)
}
```

---

## Full Log File

Every line goes to both the TUI and a timestamped log file:

```
[2026-04-08 14:23:01] [Iteration 1/3] [Feature work] Starting...
[2026-04-08 14:23:02] [Feature work] I'll examine the issue requirements...
[2026-04-08 14:25:30] [Feature work] Completed (exit 0)
[2026-04-08 14:25:31] [Test planning] Starting...
```

Location: `ralph/logs/ralph-YYYY-MM-DD-HHMMSS.log` — one file per run. The `logs/` directory is resolved relative to `ralphDir` and created with `os.MkdirAll` at startup if it doesn't exist.

Written via a simple `io.Writer` that timestamps and prefixes each line with the current step name. The log writer is called from the same scanner goroutines that append to `outputLines`, so it must be safe for concurrent writes — either use a mutex-protected writer or a dedicated log goroutine consuming from a channel.

---

## File Structure

```
ralph/
  ralph-loop              # existing bash script (unchanged, serves as fallback)
  ralph-tui/              # new Go module
    main.go               # entry point, CLI arg parsing, app setup
    workflow.go            # orchestration logic (the loop, step execution)
    ui.go                  # Glyph view definitions, keyboard handlers
    steps.go              # step loading from JSON and prompt building
    logger.go             # log file writer
    ralph-steps.json      # default step definitions (lives next to compiled binary)
    go.mod
    go.sum
  prompts/                # read by both ralph-loop and ralph-tui
  scripts/                # still used by ralph-loop; ralph-tui calls gh/git directly
  logs/                   # new directory, written by ralph-tui
```

---

## Verification

1. `cd ralph/ralph-tui && go build` — compiles
2. Run with `./ralph-tui 1` against a real repo with a "ralph" labeled issue
3. Verify: output streams line-by-line in the log panel as claude runs
4. Verify: step checkboxes update as steps complete
5. Verify: `j`/`k`/arrows scroll the log, auto-scroll resumes at bottom
6. Verify: `n` skips current step, `q` prompts confirmation
7. Verify: log file appears in `ralph/logs/` with correct timestamps
8. Verify: error state appears on subprocess failure with `c`/`r`/`q` options
9. Verify: finalization phase runs after iterations (deferred work, lessons learned, final push)
10. Verify: if no issue is found, the iteration is skipped and the loop exits gracefully
11. Verify: `close_gh_issue` receives the issue number as an argument
12. Verify: `n` terminates the running subprocess before advancing
13. Verify: SIGINT/SIGTERM kills child processes and exits cleanly
14. Verify: stderr output from `git push` and `close_gh_issue` appears in the TUI

---

## Review Summary

**Iterations completed:** 3 (stopped at iteration 3 — below 80% probability of meaningful structural improvement)

**Assumptions challenged:** 18 total
- 7 Verified, 8 Refuted, 3 Uncertain
- Key refutations: missing finalization phase, broken stderr merging strategy, missing subprocess termination on skip, missing empty-issue handling, close_gh_issue missing argument

**Agent validation findings incorporated:**
- **Critical (2 fixed):** Replaced `io.MultiReader` with two-goroutine pipe scanning + WaitGroup; added subprocess termination via `context.WithCancel` for skip/quit
- **Medium (4 fixed):** Added Glyph concurrency verification note; added retry cleanup specification; committed to single stderr strategy for all steps; added signal handling section
- **Low (1 noted):** Template variable empty-string edge case covered by early-exit logic

**Consolidations made:** 0 (no internal overlap found)

**Ambiguities surfaced and resolved:** 1 — Glyph `Log` component takes `io.Reader` (not `*[]string`), manages its own internal `sync.Mutex` and background goroutine. Plan architecture updated from shared-slice+mutex to `io.Pipe` pattern, eliminating all concurrency concerns.

**Other additions from evidence-based investigation:**
- Documented step pipeline dependencies (test-plan.md, code-review.md, progress.txt, deferred.txt)
- Added startup banner (ralph-art.txt) and completion summary message
- Documented `\n` literal vs real newline behavioral difference (harmless)
- Added log writer concurrency note
- Added `go run` development caveat for `os.Executable()`
