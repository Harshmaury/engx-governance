# Versioning Standards

**Version:** 1.0
**Date:** 2026-03-21
**Scope:** All engx repositories
**Status:** Adopted

---

## The Problem This Solves

Tags cut before a capability is complete, fix commits landing between tags,
and `fatal: tag already exists` errors are all symptoms of the same root
cause: tags are being cut when the gate passes, not when a capability is done.

This document defines when tags are earned and how they are numbered.

---

## Rule 1 — Gate passing is a precondition, not a trigger

The stability gate (12/12 build+test) must pass before any tag is cut.
But passing the gate does not mean a tag is cut. The trigger is a named
capability being complete, tested, and stable on `main`.

```
Gate passes + capability complete → cut tag
Gate passes + fix still needed   → commit fix, re-run gate, then tag
```

---

## Rule 2 — Fix commits never earn a tag

A commit that corrects a mistake made in the same session is not a release.
It goes on `main` with a descriptive message. The tag is cut only after the
full capability is stable.

Correct pattern:
```
feat: actor recording on execution history    ← capability commit
fix: AppendEvent call site — add actor arg    ← fix commit, no tag
fix: remove redundant newlines in fmt.Println ← fix commit, no tag
[gate passes 12/12]
git tag v0.6.0                                ← ONE tag for the capability
```

---

## Rule 3 — Library repos tag once per session at most

Canon, Accord, and Herald are contracts. Multiple additions in one session
accumulate in `main` and receive one tag at session end — not one tag per
addition.

```
Session adds:  ErrForbidden + Gate DTOs + PlanSpanDTO + Actor fields
One tag:       Accord v0.2.0  (not v0.1.3 → v0.1.4 → v0.1.5 → v0.1.6)
```

Exception: a breaking contract change that forces immediate coordination
across repos may require an intermediate tag. This must be noted explicitly
in the session plan.

---

## Rule 4 — Service version numbers encode capability level

Version numbers are meaningful, not cosmetic.

| Increment | Meaning | Example |
|-----------|---------|---------|
| MAJOR | Breaking API contract change | Nexus v2.0.0 — identity-aware CLI |
| MINOR | New named capability, backward compatible | Nexus v2.1.0 — plan model complete |
| PATCH | Bug fix, no new capability, no contract change | Nexus v2.0.1 — vet fix |

A minor version must be justifiable in one sentence:
> "v1.8.0 — the CLI now has a structured execution model with --dry-run"

If the sentence cannot be written, the capability is not complete enough
to tag.

---

## Rule 5 — Session tag plan written before any code

At the start of every session, before any ZIP is produced, declare:

```
Session tag plan — 2026-MM-DD
  Forge    v0.6.0  — actor recording on execution history
  Guardian v0.3.0  — G-009 UNATTRIBUTED_EXECUTION rule
  Accord   no tag  — no new contract changes needed
  Nexus    no tag  — no new capability this session
```

If the session ends without completing a declared capability, the tag
is not cut. The plan carries forward to the next session.

Tags not in the session plan require an explicit decision before cutting.

---

## Current version registry

| Repo | Latest tag | Next planned tag | Trigger |
|------|-----------|-----------------|---------|
| Nexus | v2.0.0 | v2.1.0 | platform start + build + check → plan model |
| Forge | v0.5.0-phase5 | v0.6.0 | actor recording on execution history |
| Atlas | main | — | no planned change |
| Guardian | v0.2.1 | v0.3.0 | G-009 UNATTRIBUTED_EXECUTION rule |
| Gate | v1.0.1 | v1.1.0 | team workspace mode |
| Canon | v0.4.1 | v0.5.0 | workspace event constants migration |
| Accord | v0.1.6 | v0.2.0 | next breaking contract change |
| Herald | v0.1.7 | v0.2.0 | next breaking client change |
| Observer | v0.2.0 | — | no planned change |
| Sentinel | v0.3.0 | — | no planned change |
| Metrics | v0.2.0 | — | no planned change |
| Navigator | v0.1.0 | — | no planned change |
| ZP | v2.0.0 | — | no planned change |
| Gate | v1.0.1 | v1.1.0 | team workspace mode |
