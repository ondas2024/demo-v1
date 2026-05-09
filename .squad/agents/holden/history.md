# Project Context

- **Owner:** (user)
- **Project:** demo-v1 — Azure Arc on-prem code deployment demo
- **Stack:** Azure Arc, Kubernetes (on-prem), Flux GitOps, GitHub Actions, Docker, Helm
- **Goal:** Demonstrate pushing application code to on-prem infrastructure via Azure Arc
- **Created:** 2026-05-09

## Learnings

- **2026-05-09 | Ripley architecture decisions locked** — K3s on-prem, Flux v2 Arc extension, single monorepo, Node.js Express app, ghcr.io, Kustomize, CI-driven manifest updates. Scope: one cluster, one app, one environment. See squad/decisions.md for full details.
