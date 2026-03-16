# PROJECTS.md
# @version: 3.0.0
# @updated: 2026-03-16

Platform project registry. One entry per service. No commands here — see RUNBOOK.md.

---

## Core Platform

| Project | Domain    | Port | Tag                    | Status                     |
|---------|-----------|------|------------------------|----------------------------|
| Nexus   | Control   | 8080 | v1.0.0-fixes-complete  | Feature-complete           |
| Atlas   | Knowledge | 8081 | v0.3.0-fixes-complete  | Phase 1+2 complete         |
| Forge   | Execution | 8082 | v0.4.0-fixes-complete  | Phase 1+2+3 complete       |

## Paths and Repos

| Project | Path                            | Repository                            |
|---------|---------------------------------|---------------------------------------|
| Nexus   | ~/workspace/projects/apps/nexus | github.com/Harshmaury/Nexus           |
| Atlas   | ~/workspace/projects/apps/atlas | github.com/Harshmaury/Atlas           |
| Forge   | ~/workspace/projects/apps/forge | github.com/Harshmaury/Forge           |
| Platform governance | ~/workspace/developer-platform | github.com/Harshmaury/developer-platform |

## Binaries

```
~/bin/engxd    Nexus daemon
~/bin/engx     Nexus CLI
~/bin/engxa    Nexus remote agent
~/bin/atlas    Atlas knowledge service
~/bin/forge    Forge execution engine
```

## Phase Dependency Chain

```
Nexus 1–14 ✅ → Atlas Phase 1 ✅ → Atlas Phase 2 ✅ → Forge Phase 1 ✅ → Forge Phase 2 ✅ → Forge Phase 3 ✅
```

Next: Atlas Phase 3 (ADR required) or Forge Phase 4 (ADR required).

## Adding a New Project

1. Identify capability domain (Control / Knowledge / Execution)
2. Confirm no duplication — check `architecture/platform-capability-boundaries.md`
3. Write ADR in `architecture/decisions/`
4. Assign next sequential port (next available: 8083)
5. Add entry to this file and to `AI_CONTEXT.md`
6. Generate service token and add to `~/.nexus/service-tokens`
