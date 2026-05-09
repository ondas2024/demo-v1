# Squad Decisions

## Active Decisions

### Architecture Decisions — Azure Arc Demo

> Author: Ripley (Lead/Architect)
> Date: 2026-05-09
> Status: Proposed
> Scope: Full demo architecture

**Context:** Demo showing how Azure Arc enables cloud-managed deployments to on-prem Kubernetes. Focused, reliable, ~5 minute on-stage presentation.

**Decisions:**
1. **K3s as on-prem cluster** — Single-node K3s simulates on-prem infrastructure (installs in 30s, real Kubernetes, no enterprise overhead)
2. **Flux v2 via Arc extension** — Arc-native GitOps engine, visible in Portal, manageable via az CLI (not ArgoCD)
3. **Single monorepo** — App source in src/, GitOps in gitops/, CI in .github/workflows/ (focused demo flow)
4. **Node.js Express demo app** — Fast builds (~10s), tiny images (~50MB alpine), status page with banner/version/hostname
5. **ghcr.io for images** — Free, no Azure setup needed, keeps Arc as focus (not ACR)
6. **Raw YAML + Kustomize** — Audience sees exact deployment, Kustomize Flux-native and readable (not Helm)
7. **CI updates manifests directly** — Pipeline writes new image tag to deployment.yaml and commits to main (transparent, not Flux Image Automation)
8. **Strict scope** — One cluster, one app, one environment (code push → GitOps → Arc → on-prem, focused message)

**Impact:** Defines work for Holden (app), Naomi (pipeline + cluster setup), Clarissa (docs). Full architecture at docs/architecture.md.

## Governance

- All meaningful changes require team consensus
- Document architectural decisions here
- Keep history focused on work, decisions focused on direction
