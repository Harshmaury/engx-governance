# Versioning Standards

**Version:** 2.0
**Date:** 2026-03-22
**Scope:** All engx repositories
**Status:** Adopted

---

## Philosophy

Version numbers communicate contract guarantees to consumers — not
implementation detail to developers. A version number answers one question:
"what can I rely on?" Phases, sessions, and fix counts are internal bookkeeping.
They never appear in a tag.

This is the same principle Python uses. Python 3.11 → 3.12 is a named capability
milestone. The patch counter (3.12.1 → 3.12.2) moves slowly and only for real
fixes. Nobody cuts 3.12.1 because they tidied a comment.

---

## Rule 1 — Gate passing is a precondition, not a trigger

The stability gate (all repos: `go build ./...` + `go test ./...` clean) must
pass before any tag is cut. Passing the gate does not mean a tag is cut.
The trigger is a named capability being complete, tested, and stable on `main`.

```
Gate passes + capability complete → cut tag
Gate passes + fix still needed   → commit fix, re-run gate, then tag
```

---

## Rule 2 — Fix commits never earn a tag

A commit that corrects a mistake in the same session is not a release.
It goes on `main` with a descriptive message. The tag is cut only after
the full capability is stable.

```
feat: actor recording on execution history    ← capability commit
fix: AppendEvent call site — add actor arg    ← fix, no tag
fix: remove redundant newlines in fmt.Println ← fix, no tag
[gate passes]
git tag v0.6.0                                ← ONE tag for the capability
```

---

## Rule 3 — No phase suffixes in tags. Ever.

`-phase5`, `-phase21`, `-phase3` are internal development markers.
They communicate nothing to a consumer and produce noise in `git tag --list`.

```
WRONG:  v0.5.0-phase5   v1.5.0-phase21   v0.3.0-phase3
RIGHT:  v0.5.0          v1.5.0           v0.3.0
```

Phases are tracked in `WORKFLOW-SESSION.md` and `AI_CONTEXT.md`. Never in tags.

---

## Rule 4 — Version numbers encode capability level

| Increment | Meaning | Trigger |
|-----------|---------|---------|
| MAJOR | Breaking API or contract change | Endpoint removed, response shape changed, auth model changed |
| MINOR | New named capability, backward compatible | New endpoint, new CLI command, new policy rule |
| PATCH | Bug fix — no new capability, no contract change | Crash fix, wrong return value, missing lock |

A minor version must be justifiable in one sentence.
> "v2.2.0 — AppendEvent actor field wired end-to-end (ADR-042)"

If the sentence cannot be written, the capability is not complete enough to tag.

A patch must be justifiable in one clause.
> "v2.2.1 — goreleaser tag pointed at broken commit"

---

## Rule 5 — Libraries graduate to v1.0 when the contract is stable

`0.x` means "contract still forming — expect changes."
`1.0` means "contract stable — consumers can depend on this."

Graduation criteria (all must be true):
- All planned fields and types for the current capability set are present
- No known breaking changes planned in the next session
- At least two services depend on it in production

```
Canon   — contract stable since v0.3.0 → graduate to v1.0.0 at next change
Accord  — contract still growing       → stays 0.x until DTOs stabilise
Herald  — client API stable            → graduate to v1.0.0 at next change
```

After graduation, increment conservatively:
- New constant or type → MINOR (v1.1.0)
- Bug in existing type → PATCH (v1.0.1)
- Remove or rename anything → MAJOR (v2.0.0)

---

## Rule 6 — Library repos tag once per session at most

Canon, Accord, and Herald accumulate changes in `main` during a session
and receive one tag at session end — not one tag per addition.

```
Session adds:  IdentityTokenHeader + ActorSub field + Gate DTOs
One tag:       Canon v1.0.0  (not v0.4.2 → v0.4.3 → v0.5.0)
```

Exception: a breaking contract change that forces immediate coordination
across repos may require an intermediate tag. Note this explicitly in the
session plan before cutting.

---

## Rule 7 — Session tag plan written before any code

At the start of every session, declare the tag plan before any ZIP is produced:

```
Session tag plan — 2026-MM-DD
  Forge    v0.6.0  — actor recording on execution history (ADR-042)
  Guardian v0.3.0  — G-009 unattributed execution rule (ADR-042)
  Canon    v1.0.0  — graduate: contract stable
  Nexus    no tag  — infra fix only, no new capability
```

If a declared capability is not completed, the tag is not cut.
The plan carries forward to the next session.
Tags not in the session plan require an explicit decision before cutting.

---

## Version registry

Single source of truth. Update this table when a tag is cut.

| Repo      | Latest tag | Next planned | Trigger                                      |
|-----------|------------|--------------|----------------------------------------------|
| Nexus     | v2.2.0     | v2.3.0       | next named capability                        |
| Forge     | v0.5.0     | v0.6.0       | actor recording on execution history (ADR-042) |
| Atlas     | v0.5.0     | v0.6.0       | next named capability                        |
| Gate      | v1.0.1     | v1.1.0       | team workspace mode                          |
| Guardian  | v0.2.1     | v0.3.0       | G-009 unattributed execution (ADR-042)       |
| Observer  | v0.2.0     | —            | no planned change                            |
| Sentinel  | v0.3.0     | —            | no planned change                            |
| Metrics   | v0.2.0     | —            | no planned change                            |
| Navigator | v0.1.0     | —            | no planned change                            |
| Canon     | v0.4.1     | v1.0.0       | graduate: contract stable                    |
| Accord    | v0.1.6     | v0.2.0       | next contract addition                       |
| Herald    | v0.1.7     | v1.0.0       | graduate: client API stable                  |
| ZP        | v2.0.0     | —            | no planned change                            |
