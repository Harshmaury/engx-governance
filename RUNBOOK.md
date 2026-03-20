# RUNBOOK.md
# @version: 2.0.0
# @updated: 2026-03-20
# @scope: developer platform — Nexus, Atlas, Forge, and all observers

Single source of truth for all platform commands.
No other document repeats these commands — they reference this file.

---

## 1. Prerequisites

```bash
# Tokens — generate once, never regenerate unless rotating
python3 -c "import uuid; print('atlas ', uuid.uuid4()); print('forge ', uuid.uuid4())" \
  > ~/.nexus/service-tokens && chmod 600 ~/.nexus/service-tokens

# Add to ~/.bashrc (once)
echo 'export ATLAS_SERVICE_TOKEN=$(awk "/^atlas/{print \$2}" ~/.nexus/service-tokens)' >> ~/.bashrc
echo 'export FORGE_SERVICE_TOKEN=$(awk "/^forge/{print \$2}" ~/.nexus/service-tokens)' >> ~/.bashrc
source ~/.bashrc
```

For local dev (no inter-service auth): leave `~/.nexus/service-tokens` absent.

---

## 2. Install

```bash
# Install engx, engxd, engxa to ~/bin/ via install script (Wave 4)
curl -fsSL https://get.engx.dev/install.sh | bash

# Or upgrade existing install
engx upgrade

# Build service binaries (first time or after source changes)
for svc in atlas forge guardian metrics navigator observer sentinel; do
  cd ~/workspace/projects/engx/services/$svc
  go build -o /tmp/bin/$svc ./cmd/$svc/
done
```

---

## 3. Start (normal session)

```bash
# Start daemon (if not running as system service)
engxd &
sleep 2

# Set desired=running and start all services
for svc in atlas forge guardian metrics navigator observer sentinel; do
  engx project start $svc
done

# Start local agent
/tmp/bin/engxa --id local --server http://127.0.0.1:8080 \
  --token local-agent-token --addr 127.0.0.1:9090 &

# Verify
engx doctor
```

> After ADR-032 ships: `engx platform start` will handle the project start loop.

---

## 4. Start (first boot / fresh registration)

```bash
engxd &
sleep 2

# Register all services (writes .nexus.yaml command paths to DB)
for svc in atlas forge guardian metrics navigator observer sentinel; do
  engx register ~/workspace/projects/engx/services/$svc
done

# Start
for svc in atlas forge guardian metrics navigator observer sentinel; do
  engx project start $svc
done

/tmp/bin/engxa --id local --server http://127.0.0.1:8080 \
  --token local-agent-token --addr 127.0.0.1:9090 &

engx doctor
```

---

## 5. Stop

```bash
engx platform stop
pkill -f engxa
```

---

## 6. Verify

```bash
engx doctor                          # full diagnosis
engx services                        # desired vs actual per service
engx status                          # one-line summary
ss -tlnp | grep -E "808[0-7]"       # confirm ports listening
```

---

## 7. Recovery — services stuck in maintenance

```bash
# Reset all fail counts
for svc in atlas-daemon forge-daemon guardian-daemon metrics-daemon \
           navigator-daemon observer-daemon sentinel-daemon; do
  curl -s -X POST http://127.0.0.1:8080/services/$svc/reset
done

# Then start
for svc in atlas forge guardian metrics navigator observer sentinel; do
  engx project start $svc
done
```

---

## 8. Deliver a fix

```bash
cd ~/workspace/projects/engx/services/<service>
unzip -o /mnt/c/Users/harsh/Downloads/engx-drop/<ZIP>.zip -d .
go build ./...   # must pass before git add
git add <files> WORKFLOW-SESSION.md
git commit -m "<type>: <description>"
git push origin main
```

`go build ./...` must pass before `git add`. Always.

---

## 9. Register a new project

```bash
# 1. Generate .nexus.yaml (auto-detects language/type/entrypoint)
engx init /path/to/project

# 2. Register with platform (--register flag skips step 1+2)
engx register /path/to/project

# 3. Start
engx project start <project-id>
engx project status <project-id>
```

---

## 10. Upgrade engx

```bash
engx upgrade                    # stable channel (default)
engx upgrade --channel beta     # latest pre-release
engx upgrade --dry-run          # preview without writing
```

Upgrade downloads from GitHub Releases, verifies SHA256, runs `engx doctor`
preflight, then atomically swaps binaries in `~/bin/`.
Restart engxd after upgrade: `pkill engxd && engxd &`

---

## 11. Rollback

```bash
git -C ~/workspace/projects/engx/services/nexus checkout v1.5.0
go build -o ~/bin/engx ./cmd/engx/ && go build -o ~/bin/engxd ./cmd/engxd/
pkill engxd && engxd &
```

---

## 12. Token rotation

```bash
python3 -c "import uuid; print('atlas ', uuid.uuid4()); print('forge ', uuid.uuid4())" \
  > ~/.nexus/service-tokens && chmod 600 ~/.nexus/service-tokens

# Update ~/.bashrc export lines, then restart
source ~/.bashrc
engx platform stop && pkill engxd
sleep 1 && engxd &
sleep 2
for svc in atlas forge guardian metrics navigator observer sentinel; do
  engx project start $svc
done
```

---

## 13. Add a new ADR

```bash
# ADRs live in engx-governance repo
cd ~/workspace/projects/engx/engx-governance
# Create: architecture/decisions/ADR-NNN-title.md
# Commit before writing any implementation code (Rule 9)
git add architecture/decisions/ADR-NNN-title.md
git commit -m "feat: ADR-NNN — title"
git push origin main
```

---

## 14. Add a new platform service

1. Write ADR for the new domain (Rule 9 — ADR before code)
2. Create repo: `~/workspace/projects/engx/services/<name>`
3. Add `nexus.yaml` (Atlas descriptor) and `.nexus.yaml` (runtime, generated by `engx init`)
4. Assign next sequential port (current last: sentinel 8087)
5. Add to `AI_CONTEXT.md` service table and platform service lists in nexus `main.go`
6. Generate service token and add to `~/.nexus/service-tokens` if auth is enabled

---

## 15. Ports and env vars

| Service   | Port | Env override        |
|-----------|------|---------------------|
| Nexus     | 8080 | NEXUS_HTTP_ADDR     |
| Atlas     | 8081 | ATLAS_HTTP_ADDR     |
| Forge     | 8082 | FORGE_HTTP_ADDR     |
| Metrics   | 8083 | METRICS_HTTP_ADDR   |
| Navigator | 8084 | NAVIGATOR_HTTP_ADDR |
| Guardian  | 8085 | GUARDIAN_HTTP_ADDR  |
| Observer  | 8086 | OBSERVER_HTTP_ADDR  |
| Sentinel  | 8087 | SENTINEL_HTTP_ADDR  |

```bash
# Workspace env vars
NEXUS_WORKSPACE    ~/workspace       workspace root for watcher
NEXUS_DROP_DIR     ~/nexus-drop      drop intelligence folder
ZP_WORKSPACE       ~/workspace       workspace root for zp scan
ZP_DROP_DIR        ~/Downloads/engx-drop   zp output directory
```
