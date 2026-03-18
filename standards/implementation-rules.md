# Implementation Rules

Coding discipline rules for the engx developer platform.
These rules exist because the 2026-03-18 platform scan found silent bugs
that violated each of them. Every rule is checkable in code review.

Scope: all Go services — Nexus, Atlas, Forge, Metrics, Navigator,
Guardian, Observer, Sentinel, Canon, zp.

Updated: 2026-03-18

---

## Rule 1 — Shared Mutable State Requires Explicit Synchronization

Any field accessed by more than one goroutine must be protected by a
`sync` primitive. No exceptions.

**Check:** Search for struct fields that are read or written in goroutines
other than the one that owns the struct. If the field has no `sync.Mutex`,
`sync.RWMutex`, or `sync/atomic` operation guarding it, the code is wrong.

**What it prevents:** ISSUE-001 — `Sentinel.Collector.lastEventID` was read
from the polling goroutine and written from the `GET /insights/deploy-risk`
HTTP handler with no lock. Cursor corruption, skipped events,
non-deterministic behavior.

**Correct pattern:**
```go
type Collector struct {
    mu          sync.Mutex
    lastEventID int64
}

func (c *Collector) advance(id int64) {
    c.mu.Lock()
    defer c.mu.Unlock()
    if id > c.lastEventID {
        c.lastEventID = id
    }
}
```

---

## Rule 2 — Canon Is the Only Source of Protocol Constants

No header name, event type string, service name, context key, or
descriptor field may be defined outside `github.com/Harshmaury/Canon`.

**Check:** Search all Go files for string literals matching
`"X-Service-Token"`, `"X-Trace-ID"`, `"SERVICE_CRASHED"`, `"verified"`,
or any other string that has a canonical constant in Canon. If the literal
exists outside Canon, it must be replaced with the Canon constant.

**What it prevents:**

- ISSUE-002 — Atlas `internal/nexus/client.go` defined its own
  `traceIDKey struct{}` in package `nexus`. The middleware sets the context
  value using `middleware.traceIDKey{}`. Because Go's `context.Value()`
  uses type identity, the two identical-looking struct types are different
  types in different packages — `ctx.Value()` silently returned nil and
  X-Trace-ID never propagated, despite code that appeared to handle it.

- ISSUE-003 — Sentinel `internal/collector/platform.go` used the hardcoded
  string `"X-Service-Token"` instead of `identity.ServiceTokenHeader`.

**Correct pattern:**
```go
// Import Canon — never define locally
import "github.com/Harshmaury/Canon/identity"

req.Header.Set(identity.ServiceTokenHeader, token)
req.Header.Set(identity.TraceIDHeader, traceID)

// For context keys: use middleware.TraceIDFromContext, never a local key
import "github.com/Harshmaury/Forge/internal/api/middleware"

if id := middleware.TraceIDFromContext(ctx); id != "" {
    req.Header.Set(identity.TraceIDHeader, id)
}
```

---

## Rule 3 — Every Non-Success Path Must Log

Every non-success response from an upstream service must produce a log
entry at WARNING level or above. Silent returns on error are prohibited.

**Check:** Search for `if resp.StatusCode != http.StatusOK` blocks and
`if err != nil` blocks that contain only `return` with no log call.
Every such block must have a `logger.Printf("WARNING: ...")` or equivalent.

**What it prevents:** ISSUE-004 — both `forge/internal/trigger/subscriber.go`
and `atlas/internal/nexus/subscriber.go` silently returned on non-200
HTTP responses. A 401 (wrong token), 503 (Nexus restarting), or 429
produced zero diagnostic output, making failures invisible during debugging.

**Correct pattern:**
```go
if resp.StatusCode != http.StatusOK {
    s.logger.Printf("WARNING: Nexus poll returned HTTP %d — will retry next tick",
        resp.StatusCode)
    return
}
```

For structs without a logger field, use `fmt.Printf` with a
`[service/package]` prefix until a logger is added.

---

## Engineering Notes (Non-Rules)

These are guidelines, not checkable rules.

**Context deadline hierarchy:** Any `context.WithTimeout` that wraps an
HTTP operation should set a deadline greater than the HTTP client's
`Timeout` field. If the parent context fires first, the operation returns
an empty result with no error — the client timeout never fires.
Example: Observer `GET /traces/:trace_id` uses a 12s context deadline
with 10s HTTP client timeouts (fixed in ISSUE-005).

**Event polling limits:** Polling limits should be set high enough that a
full polling interval cannot realistically produce more events than the
limit under expected load. For this platform, 500 events per 5-second
window is sufficient headroom (fixed in ISSUE-006).
