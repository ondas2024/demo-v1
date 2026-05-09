# Project Context

- **Owner:** (user)
- **Project:** demo-v1 — Azure Arc on-prem code deployment demo
- **Stack:** Azure Arc, Kubernetes (on-prem), Flux GitOps, GitHub Actions, Docker, Helm
- **Goal:** Demonstrate pushing application code to on-prem infrastructure via Azure Arc
- **Created:** 2026-05-09

## Learnings

- **2026-05-09 | Ripley architecture decisions locked** — K3s on-prem, Flux v2 Arc extension, single monorepo, Node.js Express app, ghcr.io, Kustomize, CI-driven manifest updates. Scope: one cluster, one app, one environment. See squad/decisions.md for full details.

- **2026-05-09 | Infrastructure-as-code files created** — Built all IaC for the Azure Arc demo per docs/architecture.md. Files created: `scripts/setup-cluster.sh` (K3s bootstrap), `scripts/setup-arc.sh` (Arc onboarding + Flux config), `scripts/teardown.sh` (full cleanup with confirmation gate), `gitops/kustomization.yaml` (Flux root, prune=true), `gitops/demo-app/namespace.yaml` (arc-demo namespace), `gitops/demo-app/deployment.yaml` (1 replica, NodePort 3000, liveness on /health, 128Mi/100m limits), `gitops/demo-app/service.yaml` (NodePort 30080), `.github/workflows/ci.yml` (build → push → sed manifest → commit [skip ci] → push via ARC_DEMO_PAT). Key decisions: NodePort 30080 for bookmark stability, `[skip ci]` is mandatory to prevent infinite CI loop, env vars in scripts for reproducibility across environments. All scripts use `set -euo pipefail` and validate required env vars before making any Azure API calls.

- **2026-05-09 | Cross-team coordination** — Holden built the Node.js Express app (src/server.js, src/package.json, Dockerfile, scripts/verify-deployment.sh) with inline HTML, single-stage Docker, and health endpoint returning status/version/timestamp. Clarissa built documentation (README.md, docs/demo-script.md, docs/troubleshooting.md, docs/architecture.md) with presenter-focused recovery steps at every stage. All three agents' decisions merged to squad/decisions.md.

