# ADR-025 — engx init: Project Onboarding Command

**Status:** Accepted
**Date:** 2026-03-19
**Author:** Harsh Maury
**Scope:** Nexus — new `engx init` CLI command
**Depends on:** ADR-009 (nexus.yaml contract), ADR-022 (service registration)

---

## Context

`engx register <path>` requires a `.nexus.yaml` file to exist. Without it,
registration fails with `.nexus.yaml not found`. A new user with an arbitrary
project has no path to onboarding — they must understand the `.nexus.yaml`
schema, write it correctly, and know the valid type values before the platform
will accept their project.

This is the primary distribution blocker. The platform currently only works
for projects that already have `.nexus.yaml` files written by the author.

---

## Decision

### 1. New command: engx init [path]

```
engx init [path]           — generate .nexus.yaml in current or target dir
engx init [path] --dry-run — print what would be written, do not write
```

`engx init` detects the project's language, guesses the type, generates a
complete `.nexus.yaml`, and optionally runs `engx register` automatically.

### 2. Auto-detection logic

| Signal | Detected language | Detected type |
|--------|-------------------|---------------|
| `go.mod` present | `go` | `platform-daemon` if `cmd/*/main.go` exists, else `library` |
| `package.json` present | `node` | `web-api` if `express`/`fastify` in deps, else `cli` |
| `pyproject.toml` or `requirements.txt` | `python` | `web-api` if `fastapi`/`flask` in deps, else `worker` |
| `Cargo.toml` | `rust` | `cli` |
| `*.csproj` | `dotnet` | `web-api` |
| None of above | `""` | `tool` |

Entry point detection for runtime.command:

| Language | Entry point candidates | Command |
|----------|------------------------|---------|
| go | `cmd/<name>/main.go` → first found | `go`, args: `[run, ./cmd/<name>/]` |
| go | `main.go` (root) | `go`, args: `[run, .]` |
| node | `package.json` `main` field | `node`, args: `[<main>]` |
| python | `main.py` or `app.py` | `python3`, args: `[main.py]` |
| rust | `src/main.rs` | `cargo`, args: `[run]` |

### 3. Generated .nexus.yaml schema

```yaml
name: <dirname>
id: <dirname-lowercased>
type: <detected-type>
language: <detected-language>
version: 1.0.0
keywords: []
capabilities: []
depends_on: []
runtime:
  provider: process
  command: <detected-command>
  args: [<detected-args>]
  dir: <absolute-path>
```

All fields are populated. The user can edit after generation. The file is
immediately valid for `engx register`.

### 4. Auto-register option

If `--register` flag is passed (default: false):

```
engx init --register
```

After writing `.nexus.yaml`, `engx init` calls `engx register .` automatically.
The user goes from zero to registered in one command.

### 5. Dry-run

`--dry-run` prints the `.nexus.yaml` content to stdout without writing.
Safe for inspection before committing.

### 6. .nexus.yaml vs nexus.yaml

`engx init` writes `.nexus.yaml` (dot-prefixed, runtime file, in `.gitignore`).
It does NOT write `nexus.yaml` (Atlas capability descriptor).

If the user wants Atlas verification (`status=verified`), they must separately
create `nexus.yaml` with capabilities declared. `engx init` prints a reminder:

```
  ✓ .nexus.yaml written
  ○ For Atlas verification, also create nexus.yaml with capabilities
    See: developer-platform/definitions/glossary.md#project
```

---

## What does NOT change

- `engx register` — unchanged, still reads `.nexus.yaml`
- `.nexus.yaml` schema — unchanged
- Atlas validation logic — unchanged
- `nexus.yaml` (Atlas descriptor) — not created by `engx init`

---

## Implementation scope — Nexus

### Modified files
```
cmd/engx/main.go
    — Add initCmd()
    — Add detectProject() — language/type/entrypoint detection
    — Add writeNexusYAML() — file generation
    — Add initProjectCmds: language detectors per ecosystem
```

---

## Compliance

| ADR | Status |
|-----|--------|
| ADR-009 | ✅ Generated .nexus.yaml matches Atlas validator requirements |
| ADR-022 | ✅ Generated file works with engx register auto-service-registration |
| ADR-003 | ✅ No new HTTP calls — init is purely local file generation |

---

## Next ADR

ADR-026 — Atlas auth normalisation for CLI (`engx check` and `engx build`
should not require `--token` flag in local dev mode).
