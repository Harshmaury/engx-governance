# ADR-017 — Sentinel: Platform Insights Service

**Status:** Accepted
**Date:** 2026-03-17
**Author:** Harsh Maury
**Scope:** Sentinel service — Phase 1 (deterministic) + Phase 2 (AI reasoning)
**Port:** 8087
**Governed by:** ADR-020 (observer governance)
**Supersedes:** ADR-017-sentinel-insights.md + ADR-018-sentinel-ai-reasoning.md

---

## Context

The platform generates rich operational data across Atlas, Nexus, Forge,
and the four observer services. No component synthesizes these signals
into cross-service insights. A developer debugging an incident must
manually query multiple services and mentally correlate the results.

Sentinel fills this gap in two phases:
- Phase 1: deterministic rule-based correlation (no AI)
- Phase 2: AI narrative reasoning on top of Phase 1 output

---

## Governance

All observer rules from ADR-020 apply. Additional Sentinel constraints:

- Sentinel NEVER calls LLM APIs on background polling cycles
- LLM is called ONLY on explicit GET /insights/explain requests
- LLM input is Phase 1 structured output ONLY — never raw events
- If LLM API is unavailable, /insights/explain degrades to Phase 1 output

---

## Phase 1 — Deterministic Correlation Rules

Sentinel evaluates these rules on every 30s collection cycle:

| Rule | Name | Signals | Severity |
|------|------|---------|----------|
| S-001 | Cascade detection | Nexus crashes + Atlas depends_on | error |
| S-002 | Deploy correlation | Forge deploy timing + crash cluster | error |
| S-003 | Dependency risk | Unverified projects in dependency paths | warning |
| S-004 | Stale project | Verified project with no Nexus activity | info |
| S-005 | High denial rate | Forge denials + Guardian G-001 findings | warning |

### Health classification

- `incident` — S-001 or S-002 present
- `degraded` — S-003, S-004, or S-005 present
- `healthy` — no findings

---

## Phase 1 Endpoints

```
GET /health                → health check (ADR-020 Rule 8)
GET /insights/system       → full SystemReport with all findings
GET /insights/incidents    → error-severity findings only
GET /insights/deploy-risk  → deployment risk assessment (live query)
```

---

## Phase 2 — AI Reasoning Layer

### Backend: Google Gemini 1.5 Flash (free tier)
### Endpoint: GET /insights/explain
### Trigger: explicit HTTP request only — never background polling

The AI layer receives the Phase 1 SystemReport as structured JSON
and returns a plain-prose narrative (≤ 250 words) explaining:
1. What is happening on the platform
2. Why it matters
3. What to investigate first

### Configuration

```bash
GEMINI_API_KEY=<key>           # enables AI layer
SENTINEL_SERVICE_TOKEN=<token> # outbound auth (ADR-020 Rule 2)
```

If `GEMINI_API_KEY` is absent:
- Service starts normally
- GET /insights/explain returns Phase 1 output with `ai_available: false`
- No error, no crash

### Response shape

```json
{
  "health": "degraded",
  "ai_reasoning": "The platform shows two dependency warnings...",
  "ai_available": true,
  "structured_insights": [...],
  "collected_at": "..."
}
```

---

## Data sources

| Source | Endpoint | Interval |
|--------|----------|----------|
| Atlas | GET /workspace/projects | 30s |
| Atlas | GET /graph/services | 30s |
| Nexus | GET /events?since=<id> | 10s |
| Nexus | GET /metrics | 15s |
| Forge | GET /history?limit=200 | 30s |
| Guardian | GET /guardian/findings | 30s |

---

## Implementation files

```
sentinel/
├── cmd/sentinel/main.go
├── internal/
│   ├── ai/reasoner.go         — Gemini client (Phase 2)
│   ├── insight/
│   │   ├── model.go           — Insight, Incident, SystemReport types
│   │   └── engine.go          — S-001 to S-005 rule evaluation
│   ├── collector/platform.go  — PlatformState assembly
│   └── api/
│       ├── handler/insights.go — Phase 1 handlers
│       ├── handler/explain.go  — Phase 2 handler
│       └── server.go
```

---

## Compliance

Governed by ADR-020. Additional:

| Rule | Status |
|------|--------|
| ADR-003 | ✅ HTTP/JSON only (Gemini API is external HTTP) |
| ADR-005 | ✅ AI layer never suggests start/stop |
| ADR-006 | ✅ AI reads structured output only — never raw Atlas state |
| ADR-020 | ✅ All observer governance rules apply |

---

## Next ADR

ADR-021 — devtest contract validation tool (when needed).
