# Developer Platform

Platform governance repository for the developer platform.

This repository contains architecture documentation, design philosophy,
and architectural decision records for the platform as a whole.

It does not contain implementation code for any project.

---

## Platform Capability Triangle

```
Control    Nexus   coordinates the system   github.com/Harshmaury/Nexus
Knowledge  Atlas   understands the system   github.com/Harshmaury/Atlas
Execution  Forge   acts on the system       github.com/Harshmaury/Forge
```

---

## Contents

```
architecture/
  decisions/                    Architecture Decision Records (ADRs)
  platform-capability-boundaries.md
  architecture-evolution-rules.md

AI_CONTEXT.md                   Workspace context for AI systems
workflow-philosophy.md          Platform design philosophy
PROJECTS.md                     Platform project registry
```

---

## Key Rules

- Platform governance lives here. Implementation lives in project repos.
- Every new platform capability requires an ADR in `architecture/decisions/`.
- Project-specific architecture lives inside each project repository.
- The three capability domains — Control, Knowledge, Execution — are stable.

---

## Architecture Reference

Start here: `architecture/platform-capability-boundaries.md`

Evolution rules: `architecture/architecture-evolution-rules.md`

Decisions: `architecture/decisions/`
