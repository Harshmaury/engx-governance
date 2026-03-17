# ADR-021 — Forge Execution Context Snapshot

**Status:** Accepted
**Date:** 2026-03-18
**Author:** Harsh Maury
**Scope:** Forge execution service — execution_history store
**Depends on:** ADR-010 (Forge Phase 4), ADR-009 (Atlas Phase 3)

---

## Context

ADR-010 introduced `execution_history` — every Forge command execution
is logged to SQLite with intent, target, trace ID, status, output, and
timing. This provides a full audit trail of what ran and what the outcome
was.

However, the execution record contains no information about the Atlas
context that was used to authorize the execution. The current flow in
`internal/api/handler/commands.go` is:

```
1. checker.Check(ctx, target)     ← Atlas queried, result captured in pr
2. engine.Execute(ctx, cmd)       ← Atlas may rescan here (3s poll cycle)
3. store.LogExecution(record)     ← record contains no preflight context
```

Atlas runs a workspace rescan every 3 seconds when it receives Nexus
filesystem events. Between steps 1 and 3, Atlas may have changed the
project's status from `verified` to `unverified` (or vice versa) if a
`nexus.yaml` was added or removed. The execution record reflects neither
what Atlas told Forge during preflight nor what Atlas state looked like
at the time of logging.

This produces two concrete problems:

**Problem 1 — Forensic gap.** When reviewing `GET /history/:trace_id`
to understand why a command was permitted or denied, there is no record
of the Atlas graph state at decision time. The developer must guess what
Atlas reported.

**Problem 2 — Race condition.** The `preflight.Result` returned by
`checker.Check()` — specifically `Result.Project` containing the Atlas
`ProjectDetail` — is not attached to the execution log. If Atlas rescans
mid-execution, the stored record silently misrepresents the authorization
context. This is the RC-001 race identified during the platform
concurrency audit (2026-03-18).

---

## Decision

### 1. PreflightSnapshot — immutable capture at check time

Introduce `PreflightSnapshot` — a value type that captures the complete
Atlas response at the moment `checker.Check()` returns.

```go
// PreflightSnapshot is an immutable record of the Atlas context
// at the moment of preflight authorization (ADR-021).
// Captured once in checker.Check() and passed by value through the
// execution pipeline — never re-queried between check and log.
type PreflightSnapshot struct {
    AtlasQueried  bool      // false = Atlas unreachable, check skipped (fail-open)
    ProjectFound  bool      // false = project not in verified graph
    ProjectID     string    // target project ID as returned by Atlas
    ProjectStatus string    // "verified" | "unverified" | "" if not found
    Capabilities  []string  // declared capabilities from nexus.yaml
    DependsOn     []string  // declared dependencies from nexus.yaml
    SnapshotAt    time.Time // time.Now().UTC() at the moment of the check
}
```

### 2. checker.Check() returns PreflightSnapshot

`preflight.Result` is extended to carry a `PreflightSnapshot`:

```go
type Result struct {
    Permitted bool
    Reason    string
    Snapshot  PreflightSnapshot  // ← always populated, even on deny
}
```

`checker.Check()` populates `Snapshot` from the Atlas response before
returning. The snapshot is complete regardless of whether the result is
permitted or denied.

### 3. ExecutionRecord carries the snapshot

`store.ExecutionRecord` gains a `PreflightSnapshot` field:

```go
type ExecutionRecord struct {
    // ... existing fields unchanged ...
    PreflightSnapshot store.PreflightSnapshot  // ← new field (ADR-021)
}
```

`commands.go` passes `pr.Snapshot` into both `recordExecution()` and
`recordDenied()` immediately after `checker.Check()` returns — before
`engine.Execute()` is called. This eliminates the race window.

### 4. Forge db migration v4

The snapshot is serialised as JSON and stored in a new nullable column:

```sql
ALTER TABLE execution_history
    ADD COLUMN preflight_snapshot_json TEXT NOT NULL DEFAULT '';
```

A new migration v4 entry is added to the `allMigrations` slice in
`internal/store/db.go`. The column defaults to empty string so all
existing rows are valid.

### 5. LogExecution marshals the snapshot

`store.LogExecution()` marshals `ExecutionRecord.PreflightSnapshot` to
JSON before the INSERT. `scanHistory()` unmarshals it on read. If
marshalling fails, the empty string default is used — execution logging
is never blocked by snapshot serialisation.

### 6. GET /history and GET /history/:trace_id return the snapshot

The `PreflightSnapshot` is included in the JSON response of both history
endpoints. Consumers (Guardian, Sentinel, future tooling) can read
exactly what Atlas reported at authorization time without re-querying.

---

## What does NOT change

- `checker.Check()` still fails open if Atlas is unreachable. The
  snapshot in that case has `AtlasQueried: false` — this is explicit and
  queryable.
- The preflight permit/deny logic is unchanged.
- `GET /history` and `GET /history/:trace_id` endpoint URLs are unchanged.
- The `execution_history` table schema is backward-compatible — all
  existing rows have `preflight_snapshot_json = ''`.
- No changes to Atlas, Nexus, or any observer service.

---

## Implementation scope — Forge

### Modified files

```
internal/preflight/checker.go
    — PreflightSnapshot type added
    — Result.Snapshot field added
    — Check() populates Snapshot from Atlas response before returning

internal/store/storer.go
    — PreflightSnapshot type added (mirrored here for store layer)
    — ExecutionRecord gains PreflightSnapshot field

internal/store/db.go
    — Migration v4: ADD COLUMN preflight_snapshot_json TEXT NOT NULL DEFAULT ''
    — LogExecution: json.Marshal(r.PreflightSnapshot) into new column
    — scanHistory: json.Unmarshal into PreflightSnapshot on read

internal/api/handler/commands.go
    — Submit(): pr.Snapshot captured immediately after checker.Check()
    — recordExecution() and recordDenied() accept PreflightSnapshot parameter
    — Snapshot passed by value — never re-queried after Check() returns
```

### No new files

All changes are additive modifications to existing files.

---

## Consequences

**Positive:**
- RC-001 race eliminated — the Atlas state used for authorization is
  frozen at check time and never observed in a mutated form.
- Full forensic record — `GET /history/:trace_id` now answers:
  "what did Atlas tell Forge, exactly, at the moment this executed?"
- Guardian and Sentinel can correlate execution decisions with the
  Atlas graph state at decision time, not just the current graph state.
- The snapshot is self-contained — no need to re-query Atlas to
  reconstruct past authorization decisions.

**Negative:**
- `LogExecution()` signature changes — all callers must be updated.
  Currently one caller: `commands.go`. No external API surface change.
- Small increase in `execution_history` row size — the JSON snapshot
  for a typical project is ~200 bytes. Negligible for SQLite.

**Migration safety:**
- Migration v4 uses `ALTER TABLE ... ADD COLUMN` with a `NOT NULL DEFAULT ''`
  — safe to apply to a live database. SQLite handles this without a table
  rebuild.
- Existing rows read back with `PreflightSnapshot{}` zero value (empty
  JSON unmarshals cleanly to zero struct). No data loss.

---

## Compliance

| ADR | Status |
|-----|--------|
| ADR-003 | ✅ No new inter-service calls — snapshot captured from existing check |
| ADR-004 | ✅ Command object pipeline unchanged |
| ADR-006 | ✅ Atlas provides facts. Forge decides policy. Snapshot is a fact record. |
| ADR-008 | ✅ No new HTTP calls — existing auth unchanged |
| ADR-010 | ✅ Extends execution_history schema additively |

---

## Next ADR

ADR-022 — to be determined.
Candidate: Forge Phase 5 capability-gated execution
(intent → required capability mapping, currently deferred from ADR-010).
