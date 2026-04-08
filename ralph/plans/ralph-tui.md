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
    Log(&outputLines).Grow(1).MaxLines(5000),

    // Section 3: Keyboard shortcuts
    VBox(
        Text(&shortcutLine),            // "↑/k up  ↓/j down  n next step  q quit"
    ).Border(BorderRounded),
)
```

Key Glyph features:
- **`Log`** with `.Grow(1)` — fills remaining vertical space, auto-scrolls, supports scroll-back
- **Pointer-based reactivity** — goroutine updates `outputLines`, `iterationLine`, step states; Glyph re-reads each frame
- **`Border(BorderRounded)`** — handles all box drawing (replaces `box-text`)
- **`Spinner`** — next to the active step name for visual activity indication
- **`.Handle("k", ...)`** / **`.Handle("j", ...)`** — Glyph's keyboard-first design maps directly to vim keys

---

## Internal Architecture

### Orchestration goroutine

A single goroutine runs the workflow (replicated from `ralph-loop` logic):

1. Get GitHub username via `gh api user`
2. Loop N iterations:
   a. Get next issue via `gh` CLI
   b. Get current git SHA
   c. Run each step sequentially (spawn subprocess, stream output, wait for exit)
3. Run finalization steps (deferred work, lessons learned, final push)

This goroutine communicates with the TUI by mutating shared state (which Glyph reads via pointers).

### Subprocess streaming

```go
cmd := exec.Command("claude", "--permission-mode", "acceptEdits", "--verbose", "--model", model, "-p", prompt)
stdout, _ := cmd.StdoutPipe()
cmd.Start()

scanner := bufio.NewScanner(stdout)
for scanner.Scan() {
    line := scanner.Text()
    mu.Lock()
    outputLines = append(outputLines, line)
    mu.Unlock()
}
cmd.Wait()
```

A mutex protects `outputLines` since the orchestration goroutine writes and Glyph's render loop reads.

### Step definitions loaded from JSON

Steps are loaded from a `ralph-steps.json` file located next to the compiled `ralph-tui` executable. The executable finds its own directory at startup using `os.Executable()` and reads the JSON from there.

```go
type Step struct {
    Name       string   `json:"name"`
    Model      string   `json:"model,omitempty"`      // "sonnet" or "opus"
    PromptFile string   `json:"promptFile,omitempty"`  // path relative to prompts/
    IsClaude   bool     `json:"isClaude"`              // false for git push, close issue
    Command    []string `json:"command,omitempty"`      // for non-claude steps
}

func loadSteps() ([]Step, error) {
    exePath, _ := os.Executable()
    exeDir := filepath.Dir(exePath)
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
    {"name": "Feature work",  "model": "sonnet", "promptFile": "feature-work.md",       "isClaude": true},
    {"name": "Test planning", "model": "opus",   "promptFile": "test-planning.md",       "isClaude": true},
    {"name": "Test writing",  "model": "sonnet", "promptFile": "test-writing.md",        "isClaude": true},
    {"name": "Code review",   "model": "opus",   "promptFile": "code-review-changes.md", "isClaude": true},
    {"name": "Review fixes",  "model": "sonnet", "promptFile": "code-review-fixes.md",   "isClaude": true},
    {"name": "Close issue",   "isClaude": false,  "command": ["scripts/close_gh_issue"]},
    {"name": "Update docs",   "model": "sonnet", "promptFile": "update-docs.md",         "isClaude": true},
    {"name": "Git push",      "isClaude": false,  "command": ["git", "push"]}
]
```

### Prompt building

Same logic as the bash script — reads the prompt file, prepends `ISSUENUMBER=` and `STARTINGSHA=`:

```go
promptContent, _ := os.ReadFile(filepath.Join(ralphDir, "prompts", step.PromptFile))
prompt := fmt.Sprintf("ISSUENUMBER=%s\nSTARTINGSHA=%s\n%s", issueID, startingSHA, promptContent)
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

Location: `ralph/logs/ralph-YYYY-MM-DD-HHMMSS.log` — one file per run.

Written via a simple `io.Writer` that timestamps and prefixes each line with the current step name.

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
