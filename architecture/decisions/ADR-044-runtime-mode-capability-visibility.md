# ADR-044 — Runtime Mode and Capability Visibility

Date: 2026-03-22
Status: Accepted
Domain: Platform-wide — engxd, Nexus API, engx CLI
Depends on: ADR-008 (inter-service auth), ADR-013 (Guardian), ADR-042 (Gate identity)

---

## Context

The platform currently runs in one of three operational states depending
on which capabilities are present at startup:

- Identity available, all observers healthy → full capability
- Identity absent, observers healthy → execution works, actor attribution silent
- One or more observers down → policy findings stale or absent

None of these states are declared, named, or surfaced. The system
behaves correctly in each — but it does so silently. A developer
cannot tell from `engx doctor`, `engx status`, or any API endpoint
what mode the platform is in, which capabilities are active, or what
the operational impact of a missing capability is.

Three concrete consequences observed in production:

**Problem 1 — Silent insecure mode.**
`engxd` logs `WARNING: no service-tokens file found` at startup and
continues. Gate being unreachable produces no platform-level signal at
all — `extractActor` returns an empty `ActorInfo` silently. G-009
fires only if `GUARDIAN_REQUIRE_IDENTITY=true` is set, which it is not
by default. A developer can run the entire platform without identity
enforcement and receive no indication that this is the case.

**Problem 2 — Degraded observers produce false-clean doctor output.**
If Guardian crashes, `engx doctor` shows `○ guardian` but does not
indicate that policy findings are stale. A developer reading a clean
doctor output has no way to know that G-003 stopped evaluating ten
minutes ago because the Guardian process died.

**Problem 3 — No capability API for v3 consumers.**
Relay and Conduit (ADR-041, ADR-046) need to know, before accepting
an external connection, whether the local platform has identity
enforcement active. There is no endpoint they can query. Without this,
Relay cannot make a safe decision about whether to accept an
unauthenticated inbound request.

The proposal document (2026-03-22) names this correctly:

> "The goal is not to restrict the system, but to ensure that as it
> grows, it remains understandable, predictable, and self-consistent."

This ADR defines the minimal enforcement layer that makes runtime mode
explicit without changing any existing behavior.

---

## Decision

### 1. Define three named runtime modes

```go
// internal/mode/mode.go (new package in Nexus)

type RuntimeMode string

const (
    // ModeFull — identity enforced, all observers healthy.
    // All platform capabilities are active.
    ModeFull RuntimeMode = "full"

    // ModeDegraded — core runtime operational, one or more
    // optional capabilities unavailable (observer down, SSE
    // broker absent, AI key missing). Execution continues.
    // Findings may be stale.
    ModeDegraded RuntimeMode = "degraded"

    // ModeInsecure — identity capability absent. Gate is
    // unreachable or service-tokens file is missing.
    // Execution continues but actor attribution is disabled.
    // G-009 findings are suppressed regardless of
    // GUARDIAN_REQUIRE_IDENTITY setting.
    ModeInsecure RuntimeMode = "insecure"
)
```

Mode is determined once at startup and re-evaluated every reconcile
cycle (5s). Mode transitions are logged:

```
[engxd] runtime mode: insecure — identity disabled (Gate unreachable)
[engxd] runtime mode: degraded → full — Guardian recovered
```

### 2. Define capability registry

Each optional capability has a fixed descriptor:

```go
type Capability struct {
    Name    string          // "identity" | "policy" | "insights" | "ai" | "sse" | "relay"
    Status  CapabilityStatus // enabled | disabled | degraded
    Source  string          // "gate:8088" | "local" | "external" | "-"
    Impact  CapabilityImpact // required | optional
    Reason  string          // populated when disabled/degraded
}

type CapabilityStatus string
const (
    CapabilityEnabled  CapabilityStatus = "enabled"
    CapabilityDisabled CapabilityStatus = "disabled"
    CapabilityDegraded CapabilityStatus = "degraded"
)

type CapabilityImpact string
const (
    ImpactRequired CapabilityImpact = "required" // absence = ModeInsecure
    ImpactOptional CapabilityImpact = "optional" // absence = ModeDegraded
)
```

| Capability | Impact   | Disabled when |
|------------|----------|---------------|
| identity   | required | Gate unreachable OR service-tokens absent |
| policy     | optional | Guardian unhealthy |
| insights   | optional | Sentinel unhealthy |
| ai         | optional | ANTHROPIC_API_KEY absent |
| sse        | optional | SSE broker not attached |
| relay      | optional | Relay not connected (future) |

### 3. Expose GET /system/mode

New endpoint on Nexus HTTP API (port 8080). Auth: `X-Service-Token`
required (standard service auth — ADR-008). Health endpoint
(`/health`) remains exempt.

```
GET /system/mode

Response 200:
{
  "ok": true,
  "data": {
    "mode": "insecure",
    "capabilities": [
      {
        "name": "identity",
        "status": "disabled",
        "source": "-",
        "impact": "required",
        "reason": "Gate unreachable at 127.0.0.1:8088"
      },
      {
        "name": "policy",
        "status": "enabled",
        "source": "local",
        "impact": "optional",
        "reason": ""
      },
      {
        "name": "ai",
        "status": "disabled",
        "source": "-",
        "impact": "optional",
        "reason": "ANTHROPIC_API_KEY not set"
      }
    ],
    "evaluated_at": "2026-03-22T07:13:08Z"
  }
}
```

### 4. Surface mode in engx status and engx doctor

`engx status` gains a mode line as the first output item:

```
  engx status
  ────────────────────────────────────────────────
  ● mode     insecure — identity disabled
  ✓ engxd    running  uptime 2m
  ...
```

`engx doctor` adds a mode check:

```
  ✗ runtime-mode   insecure — Gate unreachable (127.0.0.1:8088)
                   → start Gate: cd services/gate && ./gate &
```

Mode `full` produces a `✓` with no suggested action.
Mode `degraded` produces `○` listing which capabilities are absent.
Mode `insecure` produces `✗` — it is the only capability state that
renders as a hard failure in doctor output.

### 5. Guardian G-010 — platform running in insecure mode

New rule added to Guardian alongside G-009:

```
G-010  severity: warning
       trigger:  GET /system/mode returns mode="insecure"
       message:  "platform running in insecure mode — identity
                  capability disabled. Start Gate or set
                  GUARDIAN_REQUIRE_IDENTITY=false to suppress."
```

G-010 fires on every Guardian evaluation cycle while mode is insecure.
It does not block execution. It is the policy layer's acknowledgement
that an architectural boundary (identity) is inactive.

### 6. Startup log line (engxd)

After all capability probes complete during startup, engxd emits one
structured summary line before the ready message:

```
[engxd] runtime mode: insecure — capabilities: identity=disabled policy=enabled insights=enabled ai=disabled sse=enabled
[engxd] ✓ Nexus ready — socket=/tmp/engx.sock http=127.0.0.1:8080 ...
```

This line is always present. In `full` mode:

```
[engxd] runtime mode: full — all capabilities active
```

---

## Compliance

A Nexus implementation satisfies this ADR when:

1. `GET /system/mode` exists and returns a valid `RuntimeMode` and
   `[]Capability` on every call.

2. `engxd` emits the capability summary log line before the ready
   message on every startup.

3. `engx doctor` renders `✗ runtime-mode` when mode is `insecure`.

4. Mode transitions during operation are logged by engxd.

5. Guardian evaluates G-010 on every cycle and clears it when mode
   returns to `degraded` or `full`.

---

## What this ADR does not change

- No existing behavior changes. Services continue to operate in all
  three modes exactly as they do today.
- No capability is made mandatory by this ADR. Identity enforcement
  remains opt-in (`GUARDIAN_REQUIRE_IDENTITY`).
- The `insecure` mode label is descriptive, not blocking. Execution
  is never prevented by mode alone.
- Observer read-only guarantees (ADR-020) are unchanged.
- Sentinel Actuator bounds (ADR-024) are unchanged.

---

## Implementation order

This ADR is implemented in two phases to keep each delivery atomic:

**Phase A — Nexus (v2.3.0)**
- `internal/mode` package: `RuntimeMode`, `Capability`, `Evaluator`
- `GET /system/mode` endpoint
- Startup log line
- `engx doctor` mode check
- `engx status` mode line

**Phase B — Guardian (v0.3.0)**
- G-010 rule: poll `GET /system/mode`, fire on `insecure`
- G-010 clears when mode returns to `degraded` or `full`

Phase B depends on Phase A. Phase A can ship independently.

---

## Relationship to v3

`GET /system/mode` is the probe endpoint Relay uses to determine
whether to accept unauthenticated inbound connections. Before
forwarding any external request, Relay calls `/system/mode` on the
local Nexus. If `identity` capability is `disabled`, Relay rejects
the connection with `503 identity capability unavailable` and logs the
rejection. This prevents Relay from accidentally exposing an insecure
local runtime to the public internet.

This is the first concrete API contract between v2 and v3. It must
exist and be stable before any Relay code is written.

---

## Next ADR

ADR-045 — Observer cursor persistence (restart-safe sinceID for all
five observer collectors). This is the second pre-Relay stabilisation
requirement identified in the 2026-03-22 pre-launch audit.
