# ADR-043 — Plan: Command Execution Model

Date: 2026-03-21
Status: Accepted
Domain: engx CLI — internal execution layer
Nexus version: v1.8.0
Depends on: ADR-040 (outcome-centric UX), ADR-037 (signal system), ADR-015 (SSE/tracing)

---

## Context

Every engx command that does real work — `run`, `platform start`,
`build`, `check` — executes the same implicit pattern:

1. Validate inputs
2. Call one or more services
3. Poll for state change
4. Print outcome

This pattern currently lives as sequential imperative code scattered
across `cmd_run.go`, `cmd_platform.go`, and `cmd_forge.go`. Each
implementation is independent. None of them share structure.

This creates three concrete problems:

**Problem 1 — No plan visibility.**
There is no way to see what a command will do before it does it.
`engx run atlas --dry-run` does not exist. A developer cannot inspect
the intended execution path without reading source code.

**Problem 2 — No step-level traceability.**
`cmd_run.go` executes validate → start → monitor as one function.
The trace ID produced by the start call is not connected to the
monitoring loop. There is no structured span per step. A developer
looking at `engx trace <id>` sees the Forge execution but cannot see
which CLI step triggered it, how long validation took, or which
monitoring poll observed the state change.

**Problem 3 — No consistent failure model.**
Each command implements its own failure path. `cmd_run.go` checks
`failCount`. `cmd_platform.go` loops over `platformServiceIDs`.
`cmd_forge.go` calls `printForgeResult`. The same class of failure
(service not reaching running state) is described differently in each.
`UserError` exists but is not used consistently — some paths still
call raw `fmt.Errorf`.

The proposal (v2.1.0 principle) states:

> A command is a declarative intent that expands into a structured
> execution graph. Every node is contract-driven, traceable, and
> independently observable.

This ADR defines the internal model that makes that true.

---

## Decision

Introduce `internal/plan` — a package inside Nexus that defines the
execution model for all engx commands.

A `Plan` is a named, ordered sequence of `Step` objects constructed
entirely before execution begins. The executor runs the plan step by
step, printing progress to the user and emitting a structured span per
step. The user sees labels and outcomes. The developer sees spans.

### Plan and Step types

```go
// Plan is a named, ordered sequence of steps.
// Constructed before execution — never modified during execution.
type Plan struct {
    ID      string  // trace root ID — propagated to all steps
    Name    string  // human label, e.g. "run:atlas"
    Steps   []*Step
}

// Step is one unit of work in a plan.
type Step struct {
    Label     string       // user-visible label, e.g. "Validating"
    Kind      StepKind     // validate | execute | wait | observe
    Retry     RetryPolicy  // how to handle transient failure
    Run       StepFunc     // the operation — called by the executor
}

// StepFunc is the operation a step performs.
// ctx carries the plan trace ID via context.
// Returns a StepResult describing what happened.
type StepFunc func(ctx context.Context) StepResult

// StepResult is the outcome of one step.
type StepResult struct {
    OK       bool
    Skip     bool   // step skipped — not a failure (e.g. already running)
    Message  string // user-visible outcome message, appended after the label
    Detail   string // developer-visible detail, emitted in the span
    Err      *UserError
}

// StepKind classifies what a step does.
// Used for display (icon, indent) and retry policy defaults.
type StepKind int

const (
    KindValidate StepKind = iota // pre-flight check — fail-open or fail-hard
    KindExecute                  // service call with expected side effect
    KindWait                     // poll loop until condition met or timeout
    KindObserve                  // read-only check, no side effects
)

// RetryPolicy declares how a step handles transient failure.
type RetryPolicy struct {
    MaxAttempts int           // 0 = no retry
    Backoff     time.Duration // wait between attempts
    RetryOn     func(StepResult) bool // nil = retry on !OK && !UserError
}
```

### Executor

```go
// Run executes a plan, printing progress and emitting spans.
// Returns nil if all steps succeed or skip.
// Returns the first UserError that caused a hard stop.
func Run(ctx context.Context, p *Plan, w io.Writer) error
```

Execution rules:
- Steps execute sequentially
- A `KindValidate` step with `OK=false` stops the plan immediately
- A `KindExecute` or `KindWait` step with `OK=false` stops the plan
- A `KindObserve` step with `OK=false` logs a warning and continues
- `Skip=true` on any step prints the skip message and continues
- Each step emits a structured span on completion (see trace model)

### User output contract

Every step prints on one line:

```
  Validating    ✓
  Starting      ✓
  Waiting       ···✓
  Health check  ✓

  Status:   RUNNING
  Services: 3/3 running  (2.1s)
```

On failure, the failed step's `UserError` is printed in full:

```
  Validating    ✓
  Starting      ✗

  What:      project "atlas" is not registered
  Where:     nexus registry
  Why:       project has not been registered with the platform
  Next step: engx register ~/workspace/projects/engx/services/atlas
```

The user sees at most one failure block. The developer sees all spans.

### Trace model — one span per step

Each step emits a Nexus event on completion:

```
type:      "PLAN_STEP"
component: "engx"
outcome:   "success" | "failure" | "skipped"
payload:   {
  "plan_id":    "<uuid>",
  "plan_name":  "run:atlas",
  "step_index": 2,
  "step_label": "Waiting",
  "step_kind":  "wait",
  "duration_ms": 1840,
  "detail":     "3/3 services reached running state"
}
trace_id:  <plan root trace ID>
```

The plan root trace ID is set once when the plan is constructed and
propagated as `X-Trace-ID` on every service call made within a step.
This connects the CLI execution to Forge history, Nexus events, and
Observer traces — all under one root ID.

### --dry-run flag

Every command that uses a Plan gains `--dry-run` for free:

```
engx run atlas --dry-run

  Plan: run:atlas
  ─────────────────────────────────────
  1  validate   Validate project policy
  2  execute    Start project services
  3  wait       Wait for running state   (timeout: 60s)
  4  observe    Confirm service health
  ─────────────────────────────────────
  No changes made.
```

`--dry-run` calls `Plan.Print(w)` and returns without calling `Run`.
No service calls, no state changes, no spans emitted.

### Command migration

Commands migrate to the plan model one at a time. Migration is
additive — no existing behaviour changes, only structure is added.

**v1.8.0 — first migration: `engx run`**

`runProject()` in `cmd_run.go` is replaced by a `BuildRunPlan()`
function that returns a `*plan.Plan` with four steps:

| Index | Label | Kind | Operation |
|-------|-------|------|-----------|
| 0 | Validate | KindValidate | `callValidate` — fail-open if unavailable |
| 1 | Start | KindExecute | `sendCommand(CmdProjectStart)` |
| 2 | Wait | KindWait | poll `projectServiceStates` until running or timeout |
| 3 | Health | KindObserve | `getJSON /health` on each service |

**Future migrations (not in v1.8.0):**

| Command | Plan name |
|---------|-----------|
| `engx platform start` | `platform:start` |
| `engx build` | `build:<project>` |
| `engx check` | `check:<project>` |

---

## Implementation — files to create or modify

### New: `internal/plan/plan.go`

Defines `Plan`, `Step`, `StepKind`, `StepResult`, `RetryPolicy`,
`StepFunc`. No imports from `cmd/` packages. No cobra dependency.
Pure execution model — testable in isolation.

### New: `internal/plan/executor.go`

Implements `Run(ctx, plan, writer)`. Handles step iteration, retry
logic, span emission via Nexus event writer, and output formatting.
Max 40 lines per function — split into `runStep`, `emitSpan`,
`printStepLine`, `printOutcomeBlock`.

### New: `internal/plan/plan_test.go`

Table-driven tests:
- plan with all steps succeeding
- plan with validate step blocking
- plan with execute step failing
- plan with wait step timing out
- plan with observe step failing (continues)
- dry-run prints correct output
- retry policy retries on transient failure

### Modified: `cmd/engx/cmd_run.go`

`runProject()` replaced by:

```go
func runProject(socketPath, httpAddr, id string, timeoutSecs int, dryRun bool) error {
    p := plan.Build("run:"+id, buildRunSteps(socketPath, httpAddr, id, timeoutSecs))
    if dryRun {
        plan.Print(p, os.Stdout)
        return nil
    }
    return plan.Run(context.Background(), p, os.Stdout)
}
```

`callValidate` moves into a `plan.StepFunc` closure. No logic changes
— same service calls, same retry behaviour, same output. The structure
is formalized, not rewritten.

### Modified: `cmd/engx/cmd_run.go` — `runCmd`

Add `--dry-run` / `-n` flag:

```go
cmd.Flags().BoolVarP(&dryRun, "dry-run", "n", false,
    "print the execution plan without running it")
```

---

## Accord additions (coordinate before Nexus code)

New types in `api/upstream.go` — plan span DTO for Observer/Sentinel
consumption:

```go
// PlanSpanDTO is one step span emitted by the engx CLI plan executor.
// Carried in EventDTO.Payload as JSON. Component is always "engx".
type PlanSpanDTO struct {
    PlanID     string `json:"plan_id"`
    PlanName   string `json:"plan_name"`
    StepIndex  int    `json:"step_index"`
    StepLabel  string `json:"step_label"`
    StepKind   string `json:"step_kind"`
    DurationMS int64  `json:"duration_ms"`
    Outcome    string `json:"outcome"`   // "success" | "failure" | "skipped"
    Detail     string `json:"detail,omitempty"`
}
```

---

## Consequences

**Positive**
- Every command execution is inspectable before it runs (`--dry-run`)
- Every step produces a structured span — full CLI traceability
- Failure model is unified — one `UserError` type, one output block,
  all commands
- New commands are built by composing steps — no new output code needed
- The plan is the documentation — `--dry-run` output is always accurate

**Negative**
- Migration of existing commands is incremental — `platform start`,
  `build`, `check` remain unstructured until their migrations land
- Span emission requires the Nexus event writer — the CLI must have a
  valid httpAddr to emit spans. If the daemon is unreachable, spans
  are silently dropped (fail-open — never block the user operation)

**Invariants**
- `internal/plan` has zero dependency on `cmd/` packages
- `internal/plan` has zero dependency on cobra
- Plan construction never makes service calls — construction is pure
- `--dry-run` never emits spans or changes any state
- A plan's step list is immutable after construction

---

## Alternatives Considered

**Shared helper functions (no Plan type)** — rejected. Already exists
implicitly (`printOutcome`, `getProjectServices`, `callValidate`).
The problem is not missing helpers — it is missing structure. Helpers
without a model produce more helpers, not coherence.

**Workflow engine in Forge** — rejected for this scope. Forge owns
execution of developer intents (build, test, deploy). The CLI plan
model owns the translation of user commands into service calls. These
are different layers. Forge workflows operate on project artifacts;
CLI plans operate on platform state.

**Event sourcing for plan replay** — deferred. Full plan replay
(re-execute a past plan exactly) requires persisting the plan
definition alongside the spans. This is correct long-term but adds
storage complexity. v1.8.0 emits spans for observability. Replay
is a future ADR.
