# Platform Projects

Complete registry of all developer platform repositories.

---

## Core Platform Triangle

| Project | Domain    | Purpose                              | Port  | Repository                            |
|---------|-----------|--------------------------------------|-------|---------------------------------------|
| Nexus   | Control   | System coordination, service runtime | 8080  | https://github.com/Harshmaury/Nexus   |
| Atlas   | Knowledge | Workspace awareness, source indexing | 8081  | https://github.com/Harshmaury/Atlas   |
| Forge   | Execution | Intent execution, workflow engine    | 8082  | https://github.com/Harshmaury/Forge   |

---

## Governance

| Repository         | Purpose                                      |
|--------------------|----------------------------------------------|
| developer-platform | Platform architecture, ADRs, design rules    |

https://github.com/Harshmaury/developer-platform

---

## Local Workspace Paths

```
~/workspace/projects/apps/nexus/
~/workspace/projects/apps/atlas/
~/workspace/projects/apps/forge/
```

---

## Ports

```
Nexus   127.0.0.1:8080   NEXUS_HTTP_ADDR
Atlas   127.0.0.1:8081   ATLAS_HTTP_ADDR
Forge   127.0.0.1:8082   FORGE_HTTP_ADDR
```

Override any port via environment variable before starting the service.

---

## Binaries

```
~/bin/engxd    Nexus daemon
~/bin/engx     Nexus CLI
~/bin/engxa    Nexus remote agent
~/bin/atlas    Atlas knowledge service    (Phase 1 — not yet built)
~/bin/forge    Forge execution engine     (Phase 1 — not yet built)
```

---

## Adding a New Project

Before creating a new repository:

1. Identify which capability domain it belongs to.
2. Confirm it does not duplicate an existing capability.
3. Create an ADR in `architecture/decisions/`.
4. Add it to this registry.
5. Create the repository following the project scaffold pattern.

Capability boundaries: `architecture/platform-capability-boundaries.md`
