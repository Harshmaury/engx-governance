# PLATFORM-PROMPT.md
# Single-prompt AI onboarding for the developer platform
# Paste this at the start of any session involving this platform

---

You are assisting Harsh Maury with a local developer platform built in Go on Ubuntu 24.04 (WSL2).

## Platform Structure

Three capability domains. Three repos. One governance repo.

| Role       | Project | Repo                              | Port  | Path                              |
|------------|---------|-----------------------------------|-------|-----------------------------------|
| Control    | Nexus   | github.com/Harshmaury/Nexus       | 8080  | ~/workspace/projects/apps/nexus   |
| Knowledge  | Atlas   | github.com/Harshmaury/Atlas       | 8081  | ~/workspace/projects/apps/atlas   |
| Execution  | Forge   | github.com/Harshmaury/Forge       | 8082  | ~/workspace/projects/apps/forge   |
| Governance | —       | github.com/Harshmaury/developer-platform | — | ~/workspace/developer-platform |

## Navigation — Read These First

Before writing any code, fetch:

1. `~/workspace/developer-platform/AI_CONTEXT.md` — platform rules, current state
2. `~/workspace/developer-platform/architecture/platform-capability-boundaries.md` — who owns what
3. The relevant project's `WORKFLOW-SESSION.md` — build status, delivery pattern

Session key prefixes: Nexus=`NX-` Atlas=`AT-` Forge=`FG-`

## Delivery Pattern (mandatory)

```
zip naming:   <project>-<phase>-<what>-<YYYYMMDD>-<HHMM>.zip
drop folders: /mnt/c/Users/harsh/Downloads/nexus-drop/
                                            atlas-drop/
                                            forge-drop/

apply command:
  cd ~/workspace/projects/apps/<project> && \
  unzip -o /mnt/c/Users/harsh/Downloads/<project>-drop/<ZIP>.zip -d . && \
  go build ./... && \
  git add <files> WORKFLOW-SESSION.md && \
  git commit -m "<type>: <description>" && \
  git push origin <branch>
```

`go build ./...` must pass before `git add`. WORKFLOW-SESSION.md always in commit.

## Four Hard Rules

1. **Nexus owns**: project registry, event bus topics, filesystem watcher, service state. Nothing moves out.
2. **Topic constants**: declared only in `Nexus/internal/eventbus/bus.go`. All services import, never redefine.
3. **No cross-imports**: services talk HTTP/JSON only. Atlas/Forge never import Nexus internals (except eventbus constants).
4. **ADR first**: new capability → ADR in `~/workspace/developer-platform/architecture/decisions/` → then code.

## Current State (2026-03-15)

- Nexus: complete, all 14 phases on main
- Atlas: scaffold only, Phase 1 not started
- Forge: scaffold only, Phase 1 not started
- Next: Nexus ADR-002 impl (workspace event topics) → Atlas Phase 1

## Before Writing Any Code

State your understanding in 2 lines. List every file to create or modify. Wait for approval.
