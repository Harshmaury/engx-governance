# ADR-023 — Platform Startup Grace: engx platform start Resets Fail Counts

**Status:** Accepted
**Date:** 2026-03-19
**Author:** Harsh Maury
**Scope:** Nexus — new HTTP endpoint + engx platform start behaviour
**Depends on:** ADR-022 (service registration), ADR-001 (Nexus as sole registry)

---

## Context

During the first full platform run (2026-03-19) a consistent operational
friction was observed: services accumulate `fail_count` from port-conflict
crashes during development sessions. Once `fail_count` exceeds
`MaintenanceFailureThreshold` (3) within the last 60 minutes, the recovery
controller moves them to `maintenance` and the reconciler skips them entirely.

The result: `engx platform start` queues 7 services, they start briefly,
crash because ports are still held by old processes, accumulate fail counts,
enter maintenance, and the platform sits at 0/7 healthy for ~7 minutes until
the maintenance window expires.

This is the single biggest blocker for a clean first-run experience for new
users. Every fresh boot after a development session triggers this cycle.

---

## Decision

### 1. New endpoint: POST /services/:id/reset

Resets a service from any stuck state back to a clean `stopped` baseline:

```
POST /services/:id/reset
```

What it does (all four in one transaction):
- `actual_state = stopped`
- `fail_count = 0`
- `last_failed_at = NULL`
- `restart_after = NULL`

Does NOT change `desired_state` — the reconciler reads desired and will
re-queue the service on its next cycle.

Response:
```json
{"ok": true, "data": {"id": "atlas-daemon", "reset": true}}
```

Returns 404 if service not found. Idempotent — safe to call on a healthy
service (no-op in practice, desired_state unchanged).

### 2. engx platform start resets before queuing

`engx platform start` is extended to:
1. Call `POST /services/:id/reset` for every platform service
2. Then call `POST /projects/:id/start` as before

This ensures every `engx platform start` begins from a clean state
regardless of how many crashes accumulated in the previous session.

The reset is a fire-and-forget best-effort — if a service doesn't exist yet
(first run), the 404 is silently ignored.

### 3. New engx service reset command

```
engx service reset <service-id>
```

Calls `POST /services/:id/reset` for a single service. Useful for manually
clearing a service stuck in maintenance without restarting the whole platform.

---

## What does NOT change

- Recovery controller logic — unchanged, still moves to maintenance after
  threshold. The reset just clears the counters before startup.
- Health controller — unchanged
- Reconciler — unchanged
- `MaintenanceFailureThreshold` — unchanged (still 3)
- `MaintenanceWindowMinutes` — unchanged (still 60)

---

## Implementation scope — Nexus

### New file
```
internal/api/handler/services_reset.go
    — Reset() method on ServicesHandler
```

### Modified files
```
internal/api/server.go
    — Add: mux.HandleFunc("POST /services/{id}/reset", servicesH.Reset)

cmd/engx/main.go
    — platformStartCmd: call resetService() for each project before start
    — Add: engx service reset <id> subcommand
```

---

## Consequences

**Positive:**
- `engx platform start` works cleanly on every invocation — no 7-minute wait
- New users get a clean first-run experience
- Developers can recover individual stuck services without restarting everything

**Negative:**
- Reset clears the failure history — a genuinely broken service that keeps
  crashing will be reset and retried rather than staying in maintenance.
  Acceptable because: (a) the reconciler will move it back to maintenance
  after 3 more crashes, (b) the service logs at `~/.nexus/logs/<id>.log`
  provide the diagnosis.

---

## Compliance

| ADR | Status |
|-----|--------|
| ADR-001 | ✅ Nexus remains sole authority for service state |
| ADR-003 | ✅ HTTP/JSON on 127.0.0.1 only |
| ADR-008 | ✅ X-Service-Token required on non-health routes |

---

## Next ADR

ADR-024 — candidate: `engx init` command that generates `.nexus.yaml` for
a user's arbitrary project (onboarding for non-platform projects).
