# ADR-016 — Platform Shared Types Module

**Status:** Accepted
**Date:** 2026-03-17
**Author:** Harsh Maury
**Scope:** New shared Go module — Platform types only
**Module:** github.com/Harshmaury/Platform

---

## Context

After building 8 services across 4 observer phases, the following
drift has accumulated:

**Event type strings duplicated:**
- `state.EventType` in Nexus internal/state/db.go
- `sse.Event.Type` in Nexus internal/sse/broker.go
- Event type strings parsed as raw strings in Metrics, Guardian,
  Sentinel, Observer collectors

**Header constants duplicated:**
- `TraceIDHeader = "X-Trace-ID"` defined in Nexus pkg/events/topics.go
- Referenced by string literal in some middleware files
- Atlas and Forge middleware use `nexusevents.TraceIDHeader` import

**Service token header duplicated:**
- `"X-Service-Token"` hardcoded in 8 service_auth.go / client.go files

**nexus.yaml descriptor schema:**
- Defined in Atlas internal/validator/nexus_yaml.go
- Re-parsed from raw JSON in Sentinel, Guardian, Navigator collectors
- No canonical Go type for the descriptor outside Atlas

**Component name constants:**
- `ComponentNexus`, `ComponentDrop` defined in Nexus internal/state/events.go
- Re-defined as string literals in Metrics, Guardian, Observer collectors

This drift is the exact problem ADR-016 was designed to solve.

---

## Decision

### 1. A thin shared types module — no logic, no HTTP clients

`github.com/Harshmaury/Platform` is a types-only Go module.

**Rules:**
- No HTTP clients
- No database code
- No business logic
- No external dependencies beyond Go standard library
- Types and constants only
- Changes require amendment to this ADR

### 2. Module structure

```
platform/
├── events/
│   └── events.go    — EventType constants, ComponentType, OutcomeType
├── identity/
│   └── identity.go  — TraceIDHeader, ServiceTokenHeader, service name constants
├── descriptor/
│   └── descriptor.go — Descriptor struct (canonical nexus.yaml schema)
└── go.mod
```

### 3. What each service imports

| Package | Imported by |
|---------|-------------|
| `platform/events` | Nexus (replaces internal constants), all collectors |
| `platform/identity` | All services (replaces hardcoded header strings) |
| `platform/descriptor` | Atlas validator, Sentinel, Guardian collectors |

### 4. Migration is gradual — not a breaking change

Services continue to compile with their existing constants. Migration
is done per-service as each next phase is developed. No forced rebuild.

---

## Compliance

| ADR | Status |
|-----|--------|
| ADR-003 | ✅ No new protocols — types only |
| ADR-004 | ✅ Does not change command model |

---

## Next ADR

ADR-018 — Sentinel Phase 2: AI reasoning layer.
