# ADR-020 — Observer Service Governance Standard

**Status:** Accepted
**Date:** 2026-03-17
**Author:** Harsh Maury
**Scope:** All observer services — Metrics, Navigator, Guardian, Observer, Sentinel
**Supersedes:** Duplicated governance sections in ADR-011 through ADR-017

---

## Context

The platform has five observer services (ports 8083–8087). Each was
specified in a separate ADR with identical governance boilerplate:
read-only constraints, authentication rules, protocol rules, and
polling patterns. This duplication means governance changes must be
applied to five documents manually, creating drift risk.

ADR-020 extracts shared governance into a single authoritative
reference. Individual service ADRs (ADR-011 through ADR-017) retain
their capability-specific decisions and reference this document for
all shared governance rules.

---

## Decision

### Rule 1 — Observer services are strictly read-only

An observer service MUST NOT:
- Call POST /projects/:id/start or /stop on Nexus
- Call POST /commands on Forge
- Call POST /workflows or /triggers on Forge
- Write to any platform database
- Modify Atlas, Nexus, or Forge state in any way

An observer service MAY ONLY:
- Call GET endpoints on platform services
- Store derived data in its own in-memory state
- Expose its own HTTP GET endpoints

Violation of this rule is a breaking ADR violation requiring
immediate rollback and a new ADR before re-introduction.

---

### Rule 2 — Authentication

All outbound HTTP calls from observer services to platform services
MUST carry the `X-Service-Token` header (ADR-008).

The `/health` endpoint is the only exception — health checks are
always unauthenticated.

Inbound GET endpoints on observer services require NO authentication.
Observer data is read-only and safe to expose locally.

---

### Rule 3 — Protocol

Observer services use HTTP/JSON only (ADR-003).

SSE consumption from Nexus `/events/stream` is permitted (ADR-015).
Observer services MUST NOT expose their own SSE or WebSocket endpoints
without a new ADR explicitly permitting it.

---

### Rule 4 — Polling intervals

Observer services poll upstream services on fixed intervals.
Default intervals (may be tightened per service ADR):

| Upstream | Default interval |
|----------|-----------------|
| Nexus /events | every 5–10s |
| Nexus /metrics | every 10–15s |
| Atlas /workspace/projects | every 15–30s |
| Atlas /graph/services | every 15–30s |
| Forge /history | every 10–30s |
| Navigator /topology | every 15–30s |
| Guardian /findings | every 30s |

Polling MUST use `?since=<id>` on event endpoints to avoid
re-processing seen events.

---

### Rule 5 — Graceful degradation

Observer services MUST NOT crash if an upstream service is
unavailable. Every upstream query MUST have:
- A timeout (≤ 10 seconds)
- A nil/empty return on error — not a panic
- A log line at WARNING level identifying the unavailable upstream

The observer continues running and serving stale data until the
upstream recovers.

---

### Rule 6 — Startup behaviour

Observer services MUST perform one full collection pass before
starting the HTTP server. This ensures GET endpoints return
data from first request, not empty responses.

---

### Rule 7 — No persistence (default)

Observer services are in-memory by default. If an observer requires
persistence (SQLite), this must be explicitly justified in its
individual ADR. No observer may write to a platform service database.

---

### Rule 8 — Health endpoint

Every observer service MUST expose:
```
GET /health → {"ok":true,"status":"healthy","service":"<name>"}
```
No authentication required. Returns 200 while the process is alive.

---

### Rule 9 — Service token

Every observer service reads its outbound token from an environment
variable named `<SERVICE>_SERVICE_TOKEN`. If not set, the service
logs a WARNING and continues without authentication (development mode).

---

## Services governed by this ADR

| Service  | Port | Individual ADR |
|----------|------|----------------|
| Metrics  | 8083 | ADR-011 |
| Navigator| 8084 | ADR-012 |
| Guardian | 8085 | ADR-013 |
| Observer | 8086 | ADR-014 |
| Sentinel | 8087 | ADR-017 |

---

## Amendment process

Changes to any shared rule above require amendment of ADR-020.
Changes specific to one service require amendment of that service's
individual ADR only.

---

## Compliance

This ADR IS the compliance reference for all observer services.
Individual service ADRs reference it as: "Governed by ADR-020."
