# Project Context

- **Owner:** (user)
- **Project:** demo-v1 — Azure Arc on-prem code deployment demo
- **Stack:** Azure Arc, Kubernetes (on-prem), Flux GitOps, GitHub Actions, Docker, Helm
- **Goal:** Demonstrate pushing application code to on-prem infrastructure via Azure Arc
- **Created:** 2026-05-09

## Learnings

- **2026-05-09 | Ripley architecture decisions locked** — K3s on-prem, Flux v2 Arc extension, single monorepo, Node.js Express app, ghcr.io, Kustomize, CI-driven manifest updates. Scope: one cluster, one app, one environment. See squad/decisions.md for full details.
- **2026-05-09 | Demo app built** — Created `src/server.js` (Express, inline HTML, `/` + `/health`), `src/package.json` (express-only), `Dockerfile` (single-stage node:20-alpine), `scripts/verify-deployment.sh` (smoke test: /health status + / Azure Arc string check, exit 1 on any failure). Inline HTML chosen over template engine — one page, no added concepts on stage. Single-stage Docker build is correct for pure JS — no compiled assets, `npm ci --production` handles dev dep exclusion. `/health` returns `{status, version, timestamp}` — version is the Git SHA, proves rollout happened without opening the browser.

- **2026-05-09 | Cross-team coordination** — Naomi built all infrastructure-as-code (scripts/setup-cluster.sh, scripts/setup-arc.sh, scripts/teardown.sh, gitops/ manifests, .github/workflows/ci.yml) with fixed NodePort 30080 and [skip ci] guards. Clarissa built documentation (README.md, docs/demo-script.md, docs/troubleshooting.md, docs/architecture.md) with presenter-focused recovery steps. All three agents' decisions merged to squad/decisions.md.

