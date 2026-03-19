#!/usr/bin/env bash
# start.sh — engx developer platform boot script
# Usage:
#   ./start.sh              boot the platform
#   ./start.sh stop         stop all platform services
#   ./start.sh status       show current platform health
#   ./start.sh rebuild      rebuild all binaries then boot
#
# Requirements:
#   - Go 1.25+ in PATH
#   - Workspace at ~/workspace/projects/apps/<service>
#   - No ~/.nexus/service-tokens file (local dev mode)
#
# On first run: registers all platform projects automatically.
# On subsequent runs: skips registration if projects already exist.

set -euo pipefail

# ── CONFIGURATION ─────────────────────────────────────────────────────────────

WORKSPACE="${ENGX_WORKSPACE:-$HOME/workspace/projects/apps}"
BIN_DIR="${ENGX_BIN_DIR:-/tmp/bin}"
LOG_DIR="${ENGX_LOG_DIR:-/tmp}"
NEXUS_ADDR="${ENGX_NEXUS:-http://127.0.0.1:8080}"
AGENT_TOKEN="${ENGX_AGENT_TOKEN:-local-agent-token}"
AGENT_ADDR="${ENGX_AGENT_ADDR:-127.0.0.1:9090}"

SERVICES="atlas forge metrics navigator guardian observer sentinel"
ALL_PROJECTS="nexus atlas forge metrics navigator guardian observer sentinel"
PORTS="8080 8081 8082 8083 8084 8085 8086 8087"

# ── HELPERS ───────────────────────────────────────────────────────────────────

log()  { echo "  $*"; }
ok()   { echo "  ✓ $*"; }
warn() { echo "  ○ $*"; }
fail() { echo "  ✗ $*" >&2; }
die()  { fail "$*"; exit 1; }

check_health() {
  local port=$1
  curl -s --max-time 2 "http://127.0.0.1:$port/health" \
    | grep -q '"status":"healthy"' 2>/dev/null
}

wait_healthy() {
  local name=$1 port=$2 timeout=${3:-30}
  local elapsed=0
  while [ $elapsed -lt $timeout ]; do
    if check_health "$port"; then
      ok "$name healthy (port $port)"
      return 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done
  warn "$name not responding after ${timeout}s (port $port)"
  return 1
}

kill_platform() {
  pkill -f engxd    2>/dev/null || true
  pkill -f engxa    2>/dev/null || true
  for svc in atlas forge metrics navigator guardian observer sentinel; do
    pkill -f "bin/$svc" 2>/dev/null || true
  done
  sleep 2
}

ports_free() {
  for port in $PORTS; do
    if ss -tlnp 2>/dev/null | grep -q ":$port " || \
       netstat -tlnp 2>/dev/null | grep -q ":$port "; then
      return 1
    fi
  done
  return 0
}

# ── COMMANDS ──────────────────────────────────────────────────────────────────

cmd_stop() {
  echo ""
  echo "Stopping platform..."
  kill_platform
  ok "all processes stopped"
  echo ""
}

cmd_status() {
  echo ""
  echo "Platform status:"
  if ! check_health 8080; then
    warn "engxd not running"
    echo ""
    return
  fi
  "$BIN_DIR/engx" platform status 2>/dev/null || \
    curl -s "$NEXUS_ADDR/services" | \
    python3 -c "
import sys,json
d=json.load(sys.stdin).get('data',[])
r=sum(1 for s in d if s.get('actual_state')=='running')
print(f'  {r}/{len(d)} services running')
" 2>/dev/null || warn "could not get status"
  echo ""
}

cmd_rebuild() {
  echo ""
  echo "Rebuilding all binaries..."
  mkdir -p "$BIN_DIR"
  for svc in engxd engxa engx atlas forge metrics navigator guardian observer sentinel; do
    local src_dir cmd_name
    case $svc in
      engxd|engxa|engx) src_dir="$WORKSPACE/nexus"; cmd_name=$svc ;;
      *) src_dir="$WORKSPACE/$svc"; cmd_name=$svc ;;
    esac
    echo -n "  building $svc... "
    if (cd "$src_dir" && go build -o "$BIN_DIR/$svc" "./cmd/$cmd_name/" 2>/dev/null); then
      echo "✓"
    else
      echo "✗ (check $src_dir)"
    fi
  done
  echo ""
}

cmd_boot() {
  echo ""
  echo "╔══════════════════════════════════════╗"
  echo "║   engx developer platform            ║"
  echo "╚══════════════════════════════════════╝"
  echo ""

  # ── Pre-flight ────────────────────────────────────────────────────────────
  [ -f "$BIN_DIR/engxd" ] || die "engxd not found at $BIN_DIR/engxd — run: ./start.sh rebuild"
  [ -f "$BIN_DIR/engx"  ] || die "engx not found at $BIN_DIR/engx — run: ./start.sh rebuild"
  [ -f "$BIN_DIR/engxa" ] || die "engxa not found at $BIN_DIR/engxa — run: ./start.sh rebuild"

  # Service-tokens must be absent for local dev
  if [ -f "$HOME/.nexus/service-tokens" ]; then
    warn "~/.nexus/service-tokens found — moving to .bak for local dev"
    mv "$HOME/.nexus/service-tokens" "$HOME/.nexus/service-tokens.bak"
  fi

  # Kill anything already running
  if ! ports_free; then
    log "stopping existing processes..."
    kill_platform
    sleep 2
  fi

  # ── Start Nexus ───────────────────────────────────────────────────────────
  log "starting Nexus..."
  "$BIN_DIR/engxd" > "$LOG_DIR/nexus.log" 2>&1 &
  wait_healthy "Nexus" 8080 15 || die "Nexus failed to start — check $LOG_DIR/nexus.log"

  # ── Register projects ─────────────────────────────────────────────────────
  log "registering platform projects..."
  for proj in $ALL_PROJECTS; do
    local proj_path="$WORKSPACE/$proj"
    if [ -d "$proj_path" ]; then
      "$BIN_DIR/engx" register "$proj_path" > /dev/null 2>&1 && \
        ok "registered $proj" || warn "register $proj skipped"
    fi
  done

  # ── Start engxa ───────────────────────────────────────────────────────────
  log "starting engxa agent..."
  "$BIN_DIR/engxa" \
    --id local \
    --server "$NEXUS_ADDR" \
    --token "$AGENT_TOKEN" \
    --addr  "$AGENT_ADDR" \
    > "$LOG_DIR/engxa.log" 2>&1 &
  sleep 3
  ok "engxa started"

  # ── Start platform services ───────────────────────────────────────────────
  log "starting platform services..."
  "$BIN_DIR/engx" platform start > /dev/null 2>&1
  ok "services queued"

  # ── Wait for services ─────────────────────────────────────────────────────
  echo ""
  log "waiting for services to start (up to 60s)..."
  sleep 10
  local ready=0
  for i in $(seq 1 10); do
    ready=0
    for port in 8081 8082 8083 8084 8085 8086 8087; do
      check_health $port && ready=$((ready + 1))
    done
    [ $ready -ge 6 ] && break
    sleep 5
  done

  # ── Health summary ────────────────────────────────────────────────────────
  echo ""
  echo "Service health:"
  local healthy=0
  for port in 8081 8082 8083 8084 8085 8086 8087; do
    case $port in
      8081) name=atlas ;;
      8082) name=forge ;;
      8083) name=metrics ;;
      8084) name=navigator ;;
      8085) name=guardian ;;
      8086) name=observer ;;
      8087) name=sentinel ;;
    esac
    if check_health $port; then
      ok "$name (:$port)"
      healthy=$((healthy + 1))
    else
      warn "$name (:$port) not ready"
    fi
  done

  echo ""
  if [ $healthy -ge 6 ]; then
    echo "  Platform ready — $healthy/7 services healthy"
    echo ""
    echo "  Try:  engx doctor"
    echo "        engx platform status"
    echo "        engx build <project> --path <dir>"
  else
    echo "  Platform partially ready — $healthy/7 services healthy"
    echo "  Check logs: engx logs <service-daemon>"
    echo "  Retry:      engx platform start"
  fi
  echo ""
}

# ── ENTRY POINT ───────────────────────────────────────────────────────────────

case "${1:-boot}" in
  stop)    cmd_stop ;;
  status)  cmd_status ;;
  rebuild) cmd_rebuild; cmd_boot ;;
  boot|"") cmd_boot ;;
  *)
    echo "Usage: ./start.sh [boot|stop|status|rebuild]"
    exit 1
    ;;
esac
