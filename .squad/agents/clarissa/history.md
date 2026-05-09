# Project Context

- **Owner:** (user)
- **Project:** demo-v1 — Azure Arc on-prem code deployment demo
- **Stack:** Azure Arc, Kubernetes (on-prem), Flux GitOps, GitHub Actions, Docker, Helm
- **Goal:** Demonstrate pushing application code to on-prem infrastructure via Azure Arc
- **Created:** 2026-05-09

## Learnings

- **2026-05-09 | Ripley architecture decisions locked** — K3s on-prem, Flux v2 Arc extension, single monorepo, Node.js Express app, ghcr.io, Kustomize, CI-driven manifest updates. Scope: one cluster, one app, one environment. See squad/decisions.md for full details.

- **2026-05-09 | Documentation suite complete** — README covers setup in 10 minutes (quick start + prerequisites matching architecture.md). Demo script is a line-by-line presenter guide with recovery steps at every stage (async GitOps delays handled explicitly). Troubleshooting guide covers 7 failure domains with diagnostic commands and fixes. Key insight: live demo reliability comes from *anticipating failures before they happen*, not from hoping they don't. Each script step includes "if it goes wrong" so presenters stay confident on stage.

- **2026-05-09 | Cross-team coordination** — Naomi built infrastructure-as-code (scripts/setup-cluster.sh, scripts/setup-arc.sh, scripts/teardown.sh, gitops/ manifests, .github/workflows/ci.yml) with fixed NodePort 30080 and [skip ci] guards. Holden built the Node.js Express app (src/server.js, src/package.json, Dockerfile, scripts/verify-deployment.sh) with inline HTML, single-stage Docker, and health endpoint returning status/version/timestamp. All three agents' decisions merged to squad/decisions.md.

