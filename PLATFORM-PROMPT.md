# PLATFORM-PROMPT.md
# Single-prompt AI onboarding for the developer platform
# Paste this at the start of any session involving this platform
# @updated: 2026-03-16

---

You are assisting Harsh Maury with a local developer platform built in Go on Ubuntu 24.04 (WSL2).

## Platform Structure

| Role       | Project | Port | Path                              | Repo                                     |
|------------|---------|------|-----------------------------------|------------------------------------------|
| Control    | Nexus   | 8080 | ~/workspace/projects/apps/nexus   | github.com/Harshmaury/Nexus              |
| Knowledge  | Atlas   | 8081 | ~/workspace/projects/apps/atlas   | github.com/Harshmaury/Atlas              |
| Execution  | Forge   | 8082 | ~/workspace/projects/apps/forge   | github.com/Harshmaury/Forge              |
| Governance | —       | —    | ~/workspace/developer-platform    | github.com/Harshmaury/developer-platform |

## Status (2026-03-16)

| Service | Phase | Tag                    |
|---------|-------|------------------------|
| Nexus   | 1–14 complete + ADR-002 + ADR-008 | v1.0.0-fixes-complete |
| Atlas   | Phase 1+2 complete + ADR-008      | v0.3.0-fixes-complete |
| Forge   | Phase 1+2+3 complete + ADR-008    | v0.4.0-fixes-complete |

## Read These Before Writing Code

1. `~/workspace/developer-platform/AI_CONTEXT.md` — platform rules, open gaps
2. `~/workspace/developer-platform/architecture/platform-capability-boundaries.md` — who owns what
3. The relevant project's `WORKFLOW-SESSION.md` — build status, what was last changed

Session key prefixes: `NX-` (Nexus) `AT-` (Atlas) `FG-` (Forge)

## Delivery Pattern

Drop folder (all projects): `/mnt/c/Users/harsh/Downloads/engx-drop/`

```bash
cd ~/workspace/projects/apps/<project> && \
unzip -o /mnt/c/Users/harsh/Downloads/engx-drop/<ZIP>.zip -d . && \
go build ./... && \
git add <files> WORKFLOW-SESSION.md && \
git commit -m "<type>: <description>" && \
git push origin main
```

Rules: `go build ./...` passes before `git add`. WORKFLOW-SESSION.md in every commit.
Grep all import usages before adding or removing any import.

## Six Hard Rules

1. **Nexus owns permanently**: project registry (ADR-001), filesystem observation (ADR-002), service runtime state.
2. **Topic constants**: declared in `Nexus/internal/eventbus/bus.go`, re-exported via `pkg/events`. Import `pkg/events` — never `internal/eventbus` from outside Nexus. Never redefine locally.
3. **No cross-imports**: services communicate via HTTP/JSON only. Atlas and Forge never import Nexus internal packages except `pkg/events`.
4. **ADR first**: new capability → ADR committed to `developer-platform/architecture/decisions/` → then code.
5. **Auth**: all inter-service calls carry `X-Service-Token` header (ADR-008). `/health` is always exempt.
6. **Migrations**: all schema migrations in one ordered slice in `db.go`. Never in `init()` functions.

## Commands

All platform commands are in `~/workspace/developer-platform/RUNBOOK.md`.
