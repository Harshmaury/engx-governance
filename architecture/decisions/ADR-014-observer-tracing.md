# ADR-014 — Observer Tracing Service

**Status:** Accepted
**Date:** 2026-03-17
**Author:** Harsh Maury
**Scope:** New observer service — Observer
**Port:** 8086
**Depends on:** Nexus Phase 15 (X-Trace-ID on events), Forge Phase 4 (history with trace_id)

---

## Context

The platform now propagates X-Trace-ID across all three core services.
Nexus stores trace_id on every event. Forge stores trace_id on every
execution record. However, there is no service that correlates these
signals into a unified trace view. A developer debugging a workflow
must manually query Nexus /events?trace=<id> and Forge /history/:trace_id
and mentally assemble the picture.

Observer is the fourth and final observer service in the planned
ecosystem. It provides distributed tracing — given a trace ID, it
assembles the full chain of events from Nexus and execution records
from Forge into a single ordered timeline.

---

## Decision

### 1. Observer is strictly read-only

Only reads from:
- Nexus GET /events?trace=<id>
- Forge GET /history/:trace_id
- Nexus GET /events?since=<id>  (for recent trace discovery)

Never writes. Never calls start/stop.

### 2. What Observer exposes

**GET /traces/recent** — list of recently seen trace IDs (last 50):
```json
{"traces": [{"trace_id": "nexus-123", "first_seen": "...", "event_count": 3}]}
```

**GET /traces/:trace_id** — full correlated trace timeline:
```json
{
  "trace_id": "forge-456",
  "timeline": [
    {"at": "...", "source": "forge", "type": "execution", "status": "success", "target": "nexus"},
    {"at": "...", "source": "nexus", "type": "SERVICE_STARTED", "component": "nexus", "outcome": "success"}
  ],
  "summary": {"duration_ms": 120, "event_count": 2, "execution_count": 1}
}
```

**GET /health** — always exempt.

### 3. Recent trace discovery

Observer polls Nexus GET /events?since=<id> every 5s to discover new
trace IDs. It stores the last 50 unique trace IDs in memory (no SQLite).
On GET /traces/:trace_id it performs live queries to Nexus and Forge
to assemble the full timeline.

### 4. Authentication

Observer uses X-Service-Token on all outbound calls.
GET /traces/* requires no inbound auth — read-only trace data.

### 5. No persistence

Observer stores only the last 50 trace IDs in memory. No SQLite DB.
Timeline data is assembled on demand via live HTTP queries.
This keeps Observer stateless and restartable without data loss concern.

---

## Implementation scope

```
observer/
├── cmd/observer/main.go
├── internal/
│   ├── config/env.go
│   ├── trace/
│   │   ├── model.go     — TraceRef, TimelineEntry, Trace, Summary types
│   │   └── store.go     — in-memory ring buffer of recent trace IDs
│   ├── collector/
│   │   ├── nexus.go     — fetches events by trace ID + recent polling
│   │   └── forge.go     — fetches history by trace ID
│   └── api/
│       ├── handler/traces.go
│       └── server.go
├── go.mod
└── nexus.yaml
```

---

## Consequences

**Positive:**
- Single endpoint to reconstruct any operation's full trace
- Completes the observability stack (Metrics + Navigator + Guardian + Observer)
- Zero persistence risk — fully stateless, restartable anytime

**Negative:**
- GET /traces/:trace_id performs live queries — latency proportional to
  upstream response times (acceptable at local scale)

---

## Compliance

| ADR | Status |
|-----|--------|
| ADR-003 | ✅ HTTP/JSON only |
| ADR-005 | ✅ Never calls start/stop |
| ADR-008 | ✅ X-Service-Token on all outbound calls |

---

## Next ADRs

ADR-015 — SSE streaming from Nexus (now that all observers exist).
ADR-016 — Platform shared types module.
