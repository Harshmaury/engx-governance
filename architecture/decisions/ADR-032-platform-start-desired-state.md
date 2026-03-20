# ADR-032 — platform start Must Persist desired=running

**Status:** Accepted
**Date:** 2026-03-20
**Author:** Harsh Maury
**Scope:** Nexus — `engx platform start` command
**Depends on:** ADR-023 (startup grace reset), ADR-022 (service registration)

---

## Context

`engx platform start` sends `CmdProjectStart` for each platform project via the
daemon socket. The command queues services and the response says "started (1
service)" — but the reconciler immediately stops them because the DB still holds
`desired=stopped` from the previous session.

The root cause: `platform start` relies on the services already being registered
**and** having `desired=running` persisted. On a fresh boot or after a daemon
restart, neither condition is guaranteed:

1. Services may not be registered (no `.nexus.yaml` → no record in DB)
2. Even when registered, the desired state defaults to `stopped` until
   `engx project start <id>` explicitly sets it to `running`

The result observed on 2026-03-20: `platform start` said ✓ for all 7 services,
`engx services` showed `desired=stopped / actual=running`, and within 5 seconds
the reconciler killed all processes. The only working workaround was running
`engx project start` for each service individually — which writes `desired=running`
to the DB before the reconciler cycle.

---

## Decision

### 1. platform start performs a preflight registration check

Before queuing any services, `platform start` checks that each platform project
is registered. If any are missing it prints a clear actionable error:

```
✗ atlas: not registered — run: engx register ~/workspace/projects/engx/services/atlas
✗ forge: not registered — run: engx register ~/workspace/projects/engx/services/forge
  2 project(s) not registered. Register them first, then retry platform start.
```

### 2. platform start sets desired=running via project start (not just queue)

`forEachProject` with `CmdProjectStart` already sends the correct command.
The fix is sequencing: reset → register check → project start → verify.

The verify step waits up to 5 seconds for `actual=running` on each service
and reports the real outcome, not just "queued":

```
Starting platform services...
  ✓ atlas: running (pid 12345)
  ✓ forge: running (pid 12346)
  ✗ metrics: failed to start — check: engx logs metrics-daemon
```

### 3. platform start --register flag auto-registers missing projects

```
engx platform start --register
```

If `--register` is passed, missing projects are auto-registered using the
`.nexus.yaml` in their default paths before starting. This makes first-boot
a single command:

```bash
engxd &
sleep 2
engx platform start --register
```

### 4. Default service paths are defined in config

The default path for each platform service is derived from
`~/.nexus/platform-paths.json` (written by `engx platform install`).
If absent, falls back to `~/workspace/projects/engx/services/<id>`.

---

## Implementation scope — Nexus

### Modified files

```
cmd/engx/main.go
  — platformStartCmd: add --register flag
  — platformStartCmd: preflight registration check
  — platformStartCmd: post-start verify loop (5s timeout)
  — add: checkPlatformRegistered(httpAddr, projects) []string
  — add: autoRegisterPlatform(socketPath, httpAddr, missing []string)
  — add: verifyPlatformRunning(httpAddr, serviceIDs []string, timeout time.Duration)
```

---

## What does NOT change

- `CmdProjectStart` daemon command — unchanged
- `forEachProject` — unchanged  
- Reconciler logic — unchanged
- `engx project start` — unchanged
- Service registration format — unchanged

---

## Compliance

| ADR | Status |
|-----|--------|
| ADR-022 | ✅ Uses existing register command path |
| ADR-023 | ✅ Reset still runs before start |
| ADR-003 | ✅ No new inter-service calls |

---

## Closes

- Root cause of 2026-03-20 platform start incident
- `desired=stopped` / `actual=running` divergence on fresh boot
- Ghost maintenance state accumulation across sessions
