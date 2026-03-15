# AI_CONTEXT.md

Context document for AI systems working within this developer platform.

Read this file at the start of any session involving platform architecture,
new service design, or cross-project integration work.

---

## What This Platform Is

A local developer control plane built on three capability domains:

    Control    Nexus   coordinates the system   :8080
    Knowledge  Atlas   understands the system   :8081
    Execution  Forge   acts on the system       :8082

Each domain is a separate Go project with its own repository.
This repository governs the platform — it contains no implementation code.

---

## Key Rules for AI Systems

**1. Capability ownership is fixed.**
Before suggesting a feature, check `architecture/platform-capability-boundaries.md`.
Every capability has exactly one owner. Duplication is a design failure.

**2. ADRs gate implementation.**
No new platform capability is built without an ADR in `architecture/decisions/`.
If a proposed change does not have an ADR, the ADR comes first.

**3. Projects are independent.**
Atlas does not import Nexus internal packages (except eventbus constants).
Forge does not import Atlas or Nexus internal packages.
Integration is always HTTP API or event subscription.

**4. Nexus owns three things permanently.**
Project registry (ADR-001), filesystem observation (ADR-002),
and service runtime state. These never move to another service.

**5. Event topics are declared in one place.**
All platform event topic constants live in Nexus `internal/eventbus/bus.go`.
No service redefines topic strings locally.

**6. Atlas phases are sequential.**
Phase 2 (graph, conflict detection) requires Phase 1 (index) to exist.
Do not suggest Phase 2 Atlas work until Phase 1 is running.

**7. Forge command schema is fixed.**
The five-field command object (id, intent, target, parameters, context)
is the ADR-004 contract. Suggest extensions additively, never breaking changes.

---

## Platform Architecture Files

This repository:
  architecture/decisions/                 ADR-001 through ADR-004
  architecture/platform-capability-boundaries.md
  architecture/architecture-evolution-rules.md
  workflow-philosophy.md                  The ten platform constraints
  PROJECTS.md                             All repositories and ports

Project-specific architecture:
  ~/workspace/projects/apps/nexus/architecture/nexus-evolution-guide.md
  ~/workspace/projects/apps/atlas/architecture/atlas-specification.md
  ~/workspace/projects/apps/forge/architecture/forge-specification.md

---

## Current Implementation State

```
Nexus   complete   14 phases on main   full control plane
Atlas   scaffold   documentation only  Phase 1 not started
Forge   scaffold   documentation only  Phase 1 not started
```

Nexus Phase 1 for Atlas: ADR-002 implementation (workspace event topics)
must be added to Nexus before Atlas Phase 1 can subscribe to events.

---

## Session Workflow Keys

Each project uses a unique prefix for its session key:

    Nexus   NX-<hash>-<date>    WORKFLOW-SESSION.md in nexus repo
    Atlas   AT-<hash>-<date>    WORKFLOW-SESSION.md in atlas repo
    Forge   FG-<hash>-<date>    WORKFLOW-SESSION.md in forge repo

---

## Developer

Harsh Maury
GitHub: https://github.com/Harshmaury
OS: Ubuntu 24.04 (WSL2) + Windows 11
Workspace: ~/workspace/
