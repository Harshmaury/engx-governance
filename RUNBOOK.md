# RUNBOOK.md
# @version: 1.0.0
# @updated: 2026-03-16
# @scope: developer platform — Nexus, Atlas, Forge

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

---

## 2. Build

```bash
# Build all three binaries
cd ~/workspace/projects/apps/nexus && go build -o ~/bin/engxd ./cmd/engxd/ && \
  go build -o ~/bin/engx ./cmd/engx/ && go build -o ~/bin/engxa ./cmd/engxa/

cd ~/workspace/projects/apps/atlas && go build -o ~/bin/atlas ./cmd/atlas/

cd ~/workspace/projects/apps/forge && go build -o ~/bin/forge ./cmd/forge/
```

---

## 3. Start

```bash
engxd &
sleep 3
~/bin/atlas &
sleep 4
~/bin/forge &
```

Start in this order. Atlas and Forge retry Nexus connection automatically —
the sleeps prevent log noise but are not required for correctness.

---

## 4. Stop

```bash
pkill -f engxd
pkill -f "/home/harsh/bin/atlas"
pkill -f "/home/harsh/bin/forge"
```

---

## 5. Verify

```bash
# All three healthy
curl -s http://127.0.0.1:8080/health
curl -s http://127.0.0.1:8081/health
curl -s http://127.0.0.1:8082/health

# Auth enforced on Nexus
curl -s http://127.0.0.1:8080/projects                                        # → 401
curl -s -H "X-Service-Token: $ATLAS_SERVICE_TOKEN" http://127.0.0.1:8080/projects  # → 200

# Platform state
curl -s http://127.0.0.1:8081/workspace/projects
curl -s http://127.0.0.1:8081/workspace/conflicts
```

---

## 6. Deliver a fix

```bash
# All three projects use the same drop folder
# Drop folder: C:\Users\harsh\Downloads\engx-drop\
# WSL2 path:   /mnt/c/Users/harsh/Downloads/engx-drop/

cd ~/workspace/projects/apps/<nexus|atlas|forge> && \
unzip -o /mnt/c/Users/harsh/Downloads/engx-drop/<ZIP>.zip -d . && \
go build ./... && \
git add <files> WORKFLOW-SESSION.md && \
git commit -m "<type>: <description>" && \
git push origin main
```

`go build ./...` must pass before `git add`. Always.

---

## 7. Register a project with Nexus

```bash
cat > /path/to/project/.nexus.yaml << 'EOF'
name: my-project
type: web-api
language: go
EOF

engx register /path/to/project
engx project status my-project
curl -s http://127.0.0.1:8081/workspace/project/my-project
```

---

## 8. Rollback

```bash
# Each repo has a rollback tag
git -C ~/workspace/projects/apps/nexus checkout -b rollback/nexus v1.0.0-fixes-complete
git -C ~/workspace/projects/apps/atlas checkout -b rollback/atlas v0.3.0-fixes-complete
git -C ~/workspace/projects/apps/forge checkout -b rollback/forge v0.4.0-fixes-complete
```

---

## 9. Token rotation

```bash
# Regenerate tokens
python3 -c "import uuid; print('atlas ', uuid.uuid4()); print('forge ', uuid.uuid4())" \
  > ~/.nexus/service-tokens && chmod 600 ~/.nexus/service-tokens

# Update ~/.bashrc export lines (replace old values)
# Then restart all services
source ~/.bashrc && pkill -f engxd; pkill -f atlas; pkill -f forge
sleep 2 && engxd & sleep 3 && ~/bin/atlas & sleep 4 && ~/bin/forge &
```

---

## 10. Add a new ADR

```bash
# ADRs live in developer-platform repo — not in service repos
cd ~/workspace/projects/engx/governance
# Create: architecture/decisions/ADR-NNN-title.md
# Format: Date, Status, Context, Decision, Implications, Alternatives, Consequences
# Commit before writing any implementation code (architecture-evolution-rules.md Rule 1)
git add architecture/decisions/ADR-NNN-title.md && \
git commit -m "feat: ADR-NNN — title" && git push origin main
```

---

## 11. Add a new platform service

1. Write ADR for the new domain (Rule 1)
2. Create repo following existing scaffold (Go, HTTP/JSON, 127.0.0.1 only)
3. Assign next sequential port (current: Nexus 8080, Atlas 8081, Forge 8082)
4. Add to PROJECTS.md and AI_CONTEXT.md in developer-platform
5. Generate service token and add to `~/.nexus/service-tokens`

---

## 12. Ports and env vars

| Service | Port | Env override       | Token env var          |
|---------|------|--------------------|------------------------|
| Nexus   | 8080 | NEXUS_HTTP_ADDR    | — (reads service-tokens file) |
| Atlas   | 8081 | ATLAS_HTTP_ADDR    | ATLAS_SERVICE_TOKEN    |
| Forge   | 8082 | FORGE_HTTP_ADDR    | FORGE_SERVICE_TOKEN    |

Other env vars:
```
NEXUS_WORKSPACE    ~/workspace       workspace root for watcher
NEXUS_DROP_DIR     ~/nexus-drop      drop intelligence folder
ATLAS_WORKSPACE    ~/workspace       workspace root for indexer
FORGE_WORKSPACE    ~/workspace       workspace root for executor
```
