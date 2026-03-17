# Platform Navigation

**Purpose:** Pinpoint file-level map of the engx developer platform.
**Rule:** Every concept exists here once. All other docs reference this.
**Updated:** 2026-03-17

---

## Quick Reference — Ports

| Service   | Port | Binary | Start command |
|-----------|------|--------|---------------|
| Nexus     | 8080 | engxd  | `engxd &` |
| Atlas     | 8081 | atlas  | `ATLAS_SERVICE_TOKEN=<t> atlas &` |
| Forge     | 8082 | forge  | `FORGE_SERVICE_TOKEN=<t> forge &` |
| Metrics   | 8083 | metrics | `METRICS_SERVICE_TOKEN=<t> metrics &` |
| Navigator | 8084 | navigator | `NAVIGATOR_SERVICE_TOKEN=<t> navigator &` |
| Guardian  | 8085 | guardian | `GUARDIAN_SERVICE_TOKEN=<t> guardian &` |
| Observer  | 8086 | observer | `OBSERVER_SERVICE_TOKEN=<t> observer &` |
| Sentinel  | 8087 | sentinel | `SENTINEL_SERVICE_TOKEN=<t> GEMINI_API_KEY=<k> sentinel &` |

Service token `<t>` = `7d5fcbe4-44b9-4a8f-8b79-f80925c1330e`

---

## Quick Reference — Key Commands

```bash
# Platform health
curl -s http://127.0.0.1:8080/health   # nexus
curl -s http://127.0.0.1:8087/health   # sentinel (all others follow same pattern)

# Topology
curl -s http://127.0.0.1:8084/topology/summary | jq '.data'

# Guardian findings
curl -s http://127.0.0.1:8085/guardian/findings | jq '.data.summary'

# Sentinel insights
curl -s http://127.0.0.1:8087/insights/system | jq '.data | {health,summary}'
curl -s http://127.0.0.1:8087/insights/explain | jq '.data.ai_reasoning'

# Observer traces
curl -s http://127.0.0.1:8086/traces/recent | jq '.data.traces'

# Packaging
zp                    # package current project
zp nexus -H           # nexus handlers only
zp dev forge          # isolated forge sandbox
```

---

## Nexus — Control Plane (port 8080)

**Root:** `~/workspace/projects/apps/nexus`
**Module:** `github.com/Harshmaury/Nexus`
**Tag:** `v1.2.0-phase16`

### Entry point
```
cmd/engxd/main.go          — daemon startup, all wiring
```

### API layer
```
internal/api/server.go               — HTTP server, route registration
internal/api/middleware/logging.go   — request logging + Flusher support
internal/api/middleware/traceid.go   — X-Trace-ID injection
internal/api/middleware/auth.go      — X-Service-Token validation
internal/api/handler/projects.go     — GET/POST /projects
internal/api/handler/events.go       — GET /events?since=<id>
internal/api/handler/agents.go       — agent management
internal/api/handler/stream.go       — GET /events/stream (SSE, Phase 16)
```

### State layer
```
internal/state/db.go          — SQLite migrations, all queries
internal/state/storer.go      — Storer interface
internal/state/events.go      — EventWriter, event type constants, SSEPublisher
```

### SSE broker
```
internal/sse/broker.go        — fan-out broker, slow-client eviction
```

### Controllers
```
internal/controllers/project.go    — project lifecycle state machine
internal/controllers/health.go     — periodic health checks
internal/controllers/recovery.go   — crash recovery
```

### Drop intelligence
```
internal/watcher/           — fsnotify filesystem watcher
internal/drop/detector.go   — weighted scoring (filename/header/content/ext)
internal/drop/router.go     — auto-move / prompt / UNROUTED thresholds
```

### Shared exports
```
pkg/events/topics.go        — TraceIDHeader, topic constants (import this)
```

### Key DB
```
~/.nexus/nexus.db           — projects, events, agents, schema_migrations
```

---

## Atlas — Knowledge Graph (port 8081)

**Root:** `~/workspace/projects/apps/atlas`
**Module:** `github.com/Harshmaury/Atlas`
**Tag:** `v0.5.0-phase3`

### Entry point
```
cmd/atlas/main.go           — startup, workspace indexing, Nexus subscriber
```

### API layer
```
internal/api/server.go               — HTTP server + TraceID middleware
internal/api/handler/workspace.go    — GET /workspace/projects, /project/:id
                                       GET /graph/services (verified only)
                                       GET /workspace/graph (edges)
```

### Discovery
```
internal/discovery/scanner.go    — workspace scanner, nexus.yaml validator
```

### Validator
```
internal/validator/nexus_yaml.go — nexus.yaml parse + validate
                                    lenient: unknown fields ignored
                                    parse error → unverified status
```

### Store
```
internal/store/db.go         — SQLite migrations v1-v3
                                projects: id, name, path, language, type,
                                          source, status, capabilities_json,
                                          depends_on_json
internal/store/storer.go     — Storer interface, GetVerifiedProjects()
```

### Nexus subscriber
```
internal/nexus/subscriber.go — polls GET /events?since=<id> every 3s
internal/nexus/client.go     — X-Trace-ID propagation on all calls
```

### Key DB
```
~/.nexus/atlas.db            — projects, graph_edges, schema_migrations
```

---

## Forge — Execution Engine (port 8082)

**Root:** `~/workspace/projects/apps/forge`
**Module:** `github.com/Harshmaury/Forge`
**Tag:** `v0.5.0-phase4`

### Entry point
```
cmd/forge/main.go            — startup, preflight checker, all wiring
```

### API layer
```
internal/api/server.go               — HTTP server + TraceID middleware
internal/api/handler/commands.go     — POST /commands (preflight + history log)
internal/api/handler/history.go      — GET /history, GET /history/:trace_id
internal/api/handler/workflow.go     — POST/GET /workflows
internal/api/handler/trigger.go      — POST/GET/DELETE /triggers
internal/api/middleware/traceid.go   — X-Trace-ID middleware
```

### Preflight (Phase 4)
```
internal/preflight/checker.go        — Atlas graph check before execution
                                       fail-open if Atlas unreachable
```

### Execution
```
internal/executor/engine.go          — dispatches Command to intent handlers
internal/executor/intent/build.go    — build intent
internal/executor/intent/test.go     — test intent
internal/executor/intent/run.go      — run intent
internal/executor/intent/deploy.go   — deploy intent
```

### Command pipeline
```
internal/command/model.go      — Command, RawCommandRequest, ExecutionResult
internal/command/translator.go — RawCommandRequest → Command
internal/command/validator.go  — ADR-004 schema validation
```

### Workflow + triggers
```
internal/workflow/executor.go  — runs workflow steps sequentially
internal/trigger/registry.go   — event → workflow mapping
internal/trigger/subscriber.go — polls Nexus events, fires triggers
```

### Store
```
internal/store/db.go           — SQLite migrations v1-v3
                                  v1: workflows + workflow_steps
                                  v2: triggers
                                  v3: execution_history (Phase 4)
internal/store/storer.go       — Storer interface + ExecutionRecord type
```

### Atlas client
```
internal/atlas/client.go       — GetVerifiedServices() for preflight
                                  GetProject(), GetWorkspaceContext()
```

### Key DB
```
~/.nexus/forge.db              — workflows, workflow_steps, triggers,
                                  execution_history, schema_migrations
```

---

## Observer Services

All governed by ADR-020. Same pattern: poll → compute → expose GET endpoints.

### Metrics (port 8083)
```
~/workspace/projects/apps/metrics
internal/collector/nexus.go     — polls /events + /metrics
internal/collector/forge.go     — polls /history
internal/collector/atlas.go     — polls /workspace/projects
internal/api/handler/snapshot.go — GET /metrics/snapshot
internal/snapshot/model.go      — Snapshot type (NexusMetrics, ForgeMetrics, etc)
```

### Navigator (port 8084)
```
~/workspace/projects/apps/navigator
internal/collector/atlas.go      — polls /workspace/projects + /workspace/graph
internal/api/handler/topology.go — GET /topology/graph
                                    GET /topology/project/:id
                                    GET /topology/summary
internal/topology/model.go       — Node, Edge, Graph, Summary types
```

### Guardian (port 8085)
```
~/workspace/projects/apps/guardian
internal/policy/engine.go        — evaluates G-001 to G-005
internal/policy/model.go         — Finding, Report types
internal/collector/forge.go      — polls Forge /history
internal/collector/navigator.go  — polls Navigator /topology/graph
internal/collector/nexus.go      — polls Nexus /events
internal/api/handler/findings.go — GET /guardian/findings
                                    GET /guardian/findings/:rule_id
```

### Observer (port 8086)
```
~/workspace/projects/apps/observer
internal/trace/store.go          — ring buffer of 50 recent trace IDs
internal/trace/model.go          — TraceRef, TimelineEntry, Trace types
internal/collector/nexus.go      — PollRecent() for trace discovery
internal/collector/forge.go      — GetByTrace() for timeline assembly
internal/api/handler/traces.go   — GET /traces/recent
                                    GET /traces/:trace_id
```

### Sentinel (port 8087)
```
~/workspace/projects/apps/sentinel
internal/insight/engine.go       — S-001 to S-005 correlation rules
internal/insight/model.go        — Insight, Incident, SystemReport, DeployRisk
internal/collector/platform.go   — PlatformState from all upstreams
internal/ai/reasoner.go          — Gemini 1.5 Flash client (Phase 2)
internal/api/handler/insights.go — GET /insights/system, /incidents, /deploy-risk
internal/api/handler/explain.go  — GET /insights/explain (AI layer)
```

---

## Shared Modules

### Platform types (github.com/Harshmaury/Platform)
```
~/workspace/projects/apps/platform
events/events.go       — EventType, ComponentType, OutcomeType constants
identity/identity.go   — TraceIDHeader, ServiceTokenHeader, service names
descriptor/descriptor.go — canonical Descriptor (nexus.yaml schema)
```

### zp — packaging tool
```
~/workspace/projects/tools/zp
cmd/zp/main.go              — CLI entry: zp, zp <id>, zp dev, zp all, zp help
internal/pack/filter.go     — FilterMode: Full/Handlers/Go/YAML/API/Core
internal/pack/zipper.go     — ZIP creation, naming convention enforcement
internal/pack/dev.go        — isolated sandbox creation
internal/manifest/manifest.go — nexus.yaml reader
```

**Usage:**
```bash
zp                    # package current project (reads nexus.yaml)
zp nexus              # package by ID
zp atlas forge -api   # multi-project, API layer only
zp -H                 # handlers only
zp dev forge          # isolated sandbox → /tmp/zp-dev/forge-<ts>/
zp all                # package entire platform
```

---

## Governance

```
~/workspace/developer-platform/
├── architecture/decisions/
│   ├── ADR-001  Project registry authority (Nexus)
│   ├── ADR-002  Workspace observation ownership (Nexus)
│   ├── ADR-003  Service communication protocol (HTTP/JSON)
│   ├── ADR-004  Forge intent model (Command object)
│   ├── ADR-005  Forge → Nexus lifecycle protocol
│   ├── ADR-006  Atlas as context source for Forge
│   ├── ADR-007  Forge automation triggers
│   ├── ADR-008  Inter-service authentication (X-Service-Token)
│   ├── ADR-009  Atlas Phase 3 nexus.yaml contract
│   ├── ADR-010  Forge Phase 4 preflight + history
│   ├── ADR-011  Metrics observer (port 8083)
│   ├── ADR-012  Navigator observer (port 8084)
│   ├── ADR-013  Guardian observer (port 8085)
│   ├── ADR-014  Observer tracing (port 8086)
│   ├── ADR-015  SSE streaming from Nexus
│   ├── ADR-016  Platform shared types module
│   ├── ADR-017  Sentinel insights (Phase 1 + Phase 2)  ← merged
│   ├── ADR-018  [merged into ADR-017]
│   ├── ADR-019  zp developer packaging tool
│   └── ADR-020  Observer governance standard          ← new
└── standards/
    └── navigation.md                                  ← this file
```

---

## AI Navigation Model

When working with an AI assistant on this platform, use these modes:

### Locate — "where is X?"
```
"Where is the Nexus event handler?"
→ internal/api/handler/events.go

"Where is the preflight checker?"
→ forge/internal/preflight/checker.go

"Where are Guardian policy rules?"
→ guardian/internal/policy/engine.go
```

### Understand — "what does X do?"
```
"What does the SSE broker do?"
→ See: navigation.md#sse-broker + ADR-015

"What is the preflight check?"
→ See: ADR-010 + forge/internal/preflight/checker.go
```

### Act — "build/fix/extend X"
```
"Fix Nexus handlers"
→ zp nexus -H  (package handlers)
→ edit internal/api/handler/
→ go build ./...
→ zp nexus -H  (deliver fix)
```

---

## WORKLOG

Location: `~/workspace/WORKLOG.md`
Format:
```
## YYYY-MM-DD HH:MM | <SESSION-KEY> | <project(s)>
Task:    <one line>
Docs:    <ADR files>
ZIPs:    <zip files>
Commit:  <before> → <after> (project)
```
Session key prefixes: `NX-` | `AT-` | `FG-` | `MT-` | `NV-` | `GD-` | `OB-` | `ST-` | `ZP-` | `PL-`
