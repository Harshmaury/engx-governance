# ADR-009 — Atlas Phase 3: nexus.yaml Metadata Contract

**Status:** Accepted  
**Date:** 2026-03-17  
**Author:** Harsh Maury  
**Scope:** Atlas knowledge service  

---

## Context

Atlas Phase 1+2 discovers projects by polling Nexus (ADR-001) and scanning
the workspace filesystem heuristically. This produces inconsistent results:
projects without predictable structure are misclassified, partially indexed,
or assigned wrong capability domains. There is no deterministic guarantee
that a project appearing in the Atlas graph has declared its capabilities,
dependencies, or runtime requirements.

Additionally, `GET /workspace/projects` and `GET /graph/services` are
currently implementation details — their shape changes between phases.
Forge Phase 4 and future observer services (Metrics, Navigator) need stable
contract endpoints they can depend on without breaking across Atlas releases.

The Phase 15 event enrichment (Nexus v1.1.0) established `component` and
`outcome` fields on the event log. Atlas Phase 3 must provide the matching
structured project metadata surface so Forge can validate commands against
it before execution.

---

## Decision

### 1. nexus.yaml is the mandatory descriptor for graph inclusion

Every project that wants full membership in the Atlas workspace graph must
have a valid `nexus.yaml` at its root. Atlas will enforce this contract
during project indexing.

**Required fields:**
```yaml
name: my-project          # must match Nexus project registry ID
id: my-project            # lowercase, no spaces
type: web-api             # capability domain (see types below)
language: go              # primary language
version: 1.0.0            # semver
keywords:                 # used by Drop Intelligence detector
  - my-project
```

**Optional fields (Phase 3 additions):**
```yaml
capabilities:             # what this project provides
  - rest-api
  - event-emitter
depends_on:               # other project IDs this project needs running
  - postgres
  - redis
runtime:
  provider: process       # process | docker | k8s
  port: 8090
```

**Valid type values:**
`platform-daemon`, `web-api`, `worker`, `cli`, `database`,
`message-broker`, `gateway`, `library`, `automation`, `ml-service`

### 2. Heuristic scanning is demoted to discovery hints only

Atlas may still scan the filesystem to detect candidate projects, but
heuristic detection only produces `status: unverified` entries. These
appear in API responses but are excluded from capability graphs and
conflict detection.

Promotion from `unverified` to `verified` requires a valid `nexus.yaml`.

### 3. Stable contract endpoints

The following endpoints become stable contracts in Atlas Phase 3.
Breaking changes require a new ADR.

| Endpoint | Returns | Notes |
|----------|---------|-------|
| `GET /workspace/projects` | All verified projects | `status` field: verified\|unverified |
| `GET /workspace/project/:id` | Single project detail | Includes capabilities, depends_on |
| `GET /graph/services` | Service dependency graph edges | Verified projects only |
| `GET /workspace/capabilities` | Capability claims by domain | Verified projects only |
| `GET /workspace/conflicts` | Duplicate ownership, orphaned ADRs | Verified projects only |

### 4. Atlas remains read-only

Atlas validates `nexus.yaml` descriptors and builds the graph. It does not
enforce policy, start services, or write to Nexus state. Forge reads Atlas
for facts — Forge decides what is permitted (ADR-006 unchanged).

### 5. X-Trace-ID propagation

All Atlas HTTP responses include `X-Trace-ID` (Phase 15 pattern).
Atlas middleware generates a trace ID at request entry if none is present,
stores it in context, and echoes it in the response header. Atlas outbound
calls to Nexus forward the trace ID via the existing client.go pattern.

---

## Implementation — Atlas Phase 3 scope

### New files
- `internal/validator/nexus_yaml.go` — parse and validate nexus.yaml
- `internal/validator/nexus_yaml_test.go` — table-driven tests
- `internal/api/middleware/traceid.go` — X-Trace-ID middleware (mirrors Nexus)

### Modified files
- `internal/store/db.go` — migration v3: add `status` column to projects
  table (`verified` | `unverified`), add `capabilities_json` and
  `depends_on_json` columns
- `internal/store/storer.go` — updated interface
- `internal/discovery/scanner.go` — heuristic results marked `unverified`
- `internal/graph/builder.go` — only include `verified` projects in graph
- `internal/api/handler/workspace.go` — stable contract responses with
  `status` field
- `internal/api/server.go` — wire TraceID middleware

### nexus.yaml validation rules
- `name` and `id` must match the Nexus project registry entry
- `type` must be one of the valid type values listed above
- `language` must be non-empty
- `version` must be valid semver
- Unknown fields are ignored (forward compatible)
- Parse errors produce `status: unverified` — never a hard failure

---

## Consequences

**Positive:**
- Project discovery becomes deterministic and auditable
- Forge Phase 4 can validate commands against a stable capability surface
- Observer services (Metrics, Navigator) have a reliable graph to consume
- Drop Intelligence keywords move from heuristic to declared contract
- Conflict detection covers only verified, self-describing projects

**Negative:**
- Existing projects without `nexus.yaml` become `unverified` until updated
- Atlas Phase 3 requires updating `nexus.yaml` for all three platform
  services (nexus, atlas, forge) before full graph membership is restored

**Neutral:**
- Heuristic scanning continues running — no existing behaviour removed,
  only its authority is reduced

---

## Compliance

| ADR | Status |
|-----|--------|
| ADR-001 | ✅ Nexus remains canonical project registry. Atlas sources project list from Nexus. |
| ADR-002 | ✅ Nexus owns filesystem observation. Atlas reads nexus.yaml only after Nexus event notifies of project detection. |
| ADR-003 | ✅ HTTP/JSON only. No new protocols. |
| ADR-006 | ✅ Atlas provides facts. Forge decides policy. |
| ADR-008 | ✅ X-Service-Token on all inter-service calls. /health exempt. |

---

## Next ADR

ADR-010 — Forge Phase 4: pre-execution validation + workflow history.
Depends on Atlas Phase 3 stable endpoints being tagged and deployed.
