# Azure Arc Demo — Architecture

> Designed by Ripley (Lead/Architect) — 2026-05-09

## 1. Demo Objective

**What the audience sees:** A developer pushes a code change to GitHub. Without touching the on-prem cluster directly, the change flows through a CI pipeline, gets packaged as a container image, and Azure Arc + Flux GitOps automatically deploys it to an on-premises Kubernetes cluster. The presenter refreshes the browser and the change is live — on-prem, managed from the cloud.

**The "wow moment":** The presenter makes a visible change to a web app (changes a banner message or theme color), pushes to `main`, and within ~2 minutes the on-prem app reflects the change. No `kubectl apply`. No SSH. No VPN. Just Git push → Arc → on-prem. The audience sees the Azure Portal showing the Arc-connected cluster reconciling in real time.

**Secondary wow:** The presenter opens the Azure Portal and shows the Flux configuration, GitOps compliance state, and workload status — all for an on-prem cluster, managed exactly like a cloud-native one.

---

## 2. Components

### Azure-Side

| Component | Purpose |
|-----------|---------|
| **Azure Arc-enabled Kubernetes** | Projects the on-prem cluster into Azure for centralized management |
| **Azure Arc Flux v2 Extension** | Installs Flux on the cluster via Arc; manages GitOps configuration as an Azure resource |
| **Azure Resource Group** | Houses the Arc connected cluster resource and Flux config |
| **GitHub Repository (this repo)** | Single repo for app code, CI pipeline, and GitOps manifests |
| **GitHub Actions** | CI pipeline: build image, push to registry, update GitOps manifests |
| **GitHub Container Registry (ghcr.io)** | Hosts the demo app container image |

### On-Prem Side

| Component | Purpose |
|-----------|---------|
| **K3s single-node cluster** | Lightweight Kubernetes cluster simulating on-prem infrastructure. Can run on physical hardware, self-managed VM, or Azure VM (as documented in quick-start). |
| **Azure Arc agent (pods)** | Connects the cluster to Azure Arc control plane (outbound HTTPS only) |
| **Flux controllers (via Arc)** | Watches the Git repo and reconciles desired state onto the cluster |
| **Demo web app (pods)** | The running application that the audience sees change |

> **For live demos:** An Azure Linux VM (Standard_B2s) simulates the on-premises cluster. The Arc architecture and GitOps flow are identical regardless of whether the K3s node runs on physical hardware, a self-managed VM, or an Azure VM. See "Quick Start (No Hardware Required)" in the README for the automated VM provisioning path.

---

## 3. Flow

```
Developer                GitHub                 GHCR             On-Prem Cluster
   │                       │                     │                     │
   │  1. git push main     │                     │                     │
   │──────────────────────>│                     │                     │
   │                       │                     │                     │
   │                 2. GitHub Actions            │                     │
   │                 triggers CI workflow          │                     │
   │                       │                     │                     │
   │                 3. Build Docker image         │                     │
   │                 Tag: ghcr.io/org/demo:sha    │                     │
   │                       │────────────────────>│                     │
   │                       │  4. Push image       │                     │
   │                       │                     │                     │
   │                 5. Update image tag in        │                     │
   │                 gitops/demo-app/deployment.yaml                    │
   │                 (automated commit to main)   │                     │
   │                       │                     │                     │
   │                       │                     │      6. Flux polls   │
   │                       │                     │      repo (1min)     │
   │                       │                     │<─────────────────────│
   │                       │                     │                     │
   │                       │                     │  7. Flux detects     │
   │                       │                     │  manifest change,    │
   │                       │                     │  reconciles          │
   │                       │                     │         ────────────>│
   │                       │                     │                     │
   │                       │                     │  8. New pods roll    │
   │                       │                     │  out on cluster      │
   │                       │                     │                     │
   │  9. Presenter refreshes browser — new version visible             │
```

### Step-by-step detail:

1. **Code push** — Presenter edits `src/` (e.g., changes banner text), commits, pushes to `main`.
2. **CI triggers** — GitHub Actions workflow `.github/workflows/ci.yml` runs on push to `main`.
3. **Build** — Dockerfile builds the demo app image. Tagged with the Git SHA for traceability.
4. **Push** — Image pushed to `ghcr.io/<org>/arc-demo-app:<sha>`.
5. **Update manifests** — The CI workflow writes the new image tag into `gitops/demo-app/deployment.yaml` and commits it back to `main`. This is the GitOps bridge: CI produces artifacts, GitOps consumes them.
6. **Flux polls** — Flux (installed on-cluster via Arc extension) polls this repo's `gitops/` path every 60 seconds.
7. **Reconcile** — Flux detects the updated image tag in the deployment manifest and applies the change.
8. **Rollout** — Kubernetes rolls out new pods with the updated image. Old pods terminate.
9. **Verify** — Presenter refreshes the browser pointing at the on-prem app. Change is live.

**How we prove it worked:**
- Browser shows the updated app (visual change)
- Azure Portal shows Flux compliance state: "Succeeded"
- `kubectl get pods` shows new pod age (seconds old)
- Flux logs show the reconciliation event

---

## 4. Repository Structure

```
demo-v1/
├── src/                          # Application source code
│   ├── server.js                 # Express.js web server
│   ├── views/
│   │   └── index.html            # Main page (what the audience sees)
│   └── package.json              # Node.js dependencies
│
├── Dockerfile                    # Container build definition
│
├── gitops/                       # GitOps manifests (Flux watches this path)
│   ├── demo-app/
│   │   ├── namespace.yaml        # Namespace: arc-demo
│   │   ├── deployment.yaml       # Deployment (image tag updated by CI)
│   │   └── service.yaml          # NodePort service for browser access
│   └── kustomization.yaml        # Kustomize root for Flux
│
├── .github/
│   └── workflows/
│       └── ci.yml                # CI pipeline: build, push, update gitops
│
├── docs/
│   └── architecture.md           # This document
│
├── scripts/
│   ├── setup-arc.sh              # One-time Arc onboarding script
│   └── setup-cluster.sh          # K3s cluster bootstrap
│
└── README.md                     # Demo overview and run instructions
```

**Key design choice:** Single repo (monorepo) for app + GitOps config. In production you'd separate these. For a demo, one repo keeps the flow visible and the audience doesn't lose track of which repo does what.

---

## 5. Azure Arc Topology

### Connectivity Model: **Semi-connected (outbound only)**

The on-prem cluster initiates all connections outbound to Azure. No inbound firewall rules needed. This is Arc's default and most realistic model for demos — it mirrors how actual enterprises connect on-prem clusters.

### Arc Resources

```
Resource Group: rg-arc-demo
├── Connected Cluster: arc-demo-cluster
│   ├── Arc Agent (azure-arc namespace)
│   └── Flux Extension: flux-gitops
│       └── Flux Configuration: demo-app-config
│           ├── Source: GitRepository (this repo, main branch)
│           └── Kustomization: gitops/ path
```

### Arc Extensions Required

| Extension | Purpose | Install Method |
|-----------|---------|---------------|
| **microsoft.flux** | Installs Flux v2 controllers on the cluster | `az k8s-extension create --extension-type microsoft.flux` |

That's it. One extension. The Flux extension is the only Arc extension needed for this demo. No Azure Monitor, no Azure Policy, no Key Vault — those are production concerns, not demo concerns.

### Arc Agent Communication

- Arc agents run in `azure-arc` namespace
- Outbound HTTPS to Azure (no inbound)
- Agents handle: inventory, configuration, extension management
- Cluster appears in Azure Portal under the resource group

---

## 6. GitOps Model

### Engine: **Flux v2 (via Azure Arc Extension)**

Why Flux v2 over ArgoCD:
- Flux is the Arc-native GitOps engine — first-class Azure support via `microsoft.flux` extension
- Flux config is an Azure resource (visible in Portal, queryable via Azure CLI)
- ArgoCD would require separate setup, its own UI, and has no Arc integration
- For this demo, Arc + Flux is the story. ArgoCD would split the audience's attention.

### Flux Configuration

```yaml
# Created via Azure CLI, not manually applied
az k8s-configuration flux create \
  --resource-group rg-arc-demo \
  --cluster-name arc-demo-cluster \
  --cluster-type connectedClusters \
  --name demo-app-config \
  --namespace flux-system \
  --scope cluster \
  --url https://github.com/<org>/demo-v1 \
  --branch main \
  --kustomization name=demo-app path=./gitops interval=1m prune=true
```

### Reconciliation Behavior

- **Poll interval:** 60 seconds (fast enough for demo pacing)
- **Prune:** Enabled — deleting a manifest removes the resource (clean demo resets)
- **Scope:** Cluster-wide (not namespace-scoped; simpler for demo)
- **Source path:** `./gitops` — Flux only watches the GitOps directory, ignores app source code

### Image Tag Update Strategy

CI updates the `deployment.yaml` directly with the new image tag and commits to `main`. Flux sees the commit and reconciles.

Why not Flux Image Automation? It adds complexity (image reflector, image automation controllers, marker comments in YAML) for zero demo value. A simple `sed` + `git commit` in CI is transparent and easy to explain on stage.

---

## 7. Demo App

### Choice: **Node.js (Express) — Single-page status board**

**What it is:** A minimal Express.js web server serving a single HTML page. The page shows:
- App name / banner message (the thing we change to demo the flow)
- Current version (Git SHA, injected at build time)
- Hostname (pod name — proves it's running in Kubernetes)
- Timestamp of last deployment

**Why Node.js:**
- Universally understood — audience won't get stuck on language-specific concepts
- Fast container builds (~10 seconds)
- Tiny image size with `node:20-alpine` (~50MB)
- Express is ~15 lines of code for this use case

**Why not a compiled language (Go, .NET, Java):**
- Longer build times distract during live demo
- The app isn't the point — the deployment pipeline is

### App Spec

- **Runtime:** Node.js 20 (Alpine)
- **Framework:** Express.js
- **Port:** 3000
- **Endpoints:** `GET /` (HTML page), `GET /health` (liveness probe)
- **Configuration:** Environment variables for `APP_VERSION`, `BANNER_MESSAGE`
- **Dockerfile:** Multi-stage not needed — single `FROM node:20-alpine`, `COPY`, `npm ci --production`, `CMD`

---

## 8. Scope Boundaries

### IN Scope

- ✅ Single K3s cluster connected via Azure Arc
- ✅ Flux v2 GitOps via Arc extension
- ✅ GitHub Actions CI (build, push, update manifests)
- ✅ Simple Node.js demo app
- ✅ Azure Portal showing Arc + GitOps status
- ✅ One-time setup scripts for cluster + Arc onboarding
- ✅ Demo run instructions in README

### OUT of Scope — Explicitly

| Item | Why it's out |
|------|-------------|
| **Multi-cluster** | Adds complexity without adding to the core story. One cluster is enough. |
| **Azure Monitor / Container Insights** | Production concern. Distracts from the GitOps flow. |
| **Azure Policy for Kubernetes** | Great feature, different demo. |
| **Key Vault integration** | No secrets management needed for a demo app. |
| **Helm charts** | Raw Kubernetes YAML with Kustomize is more transparent for a demo audience. Helm adds a layer of abstraction that obscures what's happening. |
| **Multiple environments (dev/staging/prod)** | One environment. The demo shows the flow, not an environment promotion strategy. |
| **HTTPS/TLS/Ingress** | NodePort is fine. The audience isn't evaluating our TLS setup. |
| **Image pull secrets** | Using ghcr.io public or org-scoped packages. No secret management needed. |
| **Persistent storage** | Stateless app. No databases, no volumes. |
| **RBAC / namespace isolation** | Single-tenant demo. Not relevant. |
| **Terraform / Bicep for Azure resources** | Setup scripts use `az` CLI directly. IaC for two resources is over-engineering. |

**Rule:** If someone says "can we also show X?" — the answer is "that's a separate demo." This demo has one story: code push → GitOps → on-prem deployment via Arc.

---

## 9. Prerequisites

### For the presenter's machine:

| Prerequisite | Version | Purpose |
|-------------|---------|---------|
| Azure CLI (`az`) | 2.60+ | Arc onboarding and Flux config |
| `az connectedk8s` extension | Latest | Arc cluster connection |
| `az k8s-configuration` extension | Latest | Flux configuration |
| `kubectl` | 1.28+ | Cluster verification and demo commands |
| Docker Desktop or Rancher Desktop | Latest | Local image builds (if testing locally) |
| Git | 2.40+ | Code push |
| GitHub CLI (`gh`) | Latest | Repo and secrets management |

### Azure resources (pre-provisioned):

- Azure subscription with Contributor access
- Resource group: `rg-arc-demo`
- Service principal or `az login` session for Arc onboarding

### On-prem environment (pre-provisioned):

- Linux VM or machine (Ubuntu 22.04+ recommended)
- K3s installed and running (`curl -sfL https://get.k3s.io | sh -`)
- Outbound HTTPS access to Azure endpoints (no inbound required)
- `kubeconfig` accessible for Arc onboarding

### GitHub setup:

- Repository created with Actions enabled
- `GHCR_TOKEN` (or GitHub token with `packages:write`) stored as repository secret
- Repository secret: `ARC_DEMO_PAT` — a PAT with `contents:write` for the CI workflow to push manifest updates back to the repo

### One-time setup order:

1. Provision the Linux VM / machine
2. Install K3s
3. Run `scripts/setup-arc.sh` (connects cluster to Azure Arc)
4. Run Flux configuration via Azure CLI (creates the GitOps config pointing to this repo)
5. Push initial app code and GitOps manifests
6. Verify Flux reconciliation in Azure Portal
7. Ready to demo

---

## Architectural Decisions Summary

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | K3s over AKS-on-HCI or full K8s | Lightest-weight option; installs in 30 seconds; perfect for simulating on-prem |
| 2 | Flux v2 over ArgoCD | Arc-native; Portal-visible; one extension install; no separate UI to manage |
| 3 | Single repo (monorepo) | Demo clarity; audience follows one repo, one flow |
| 4 | Node.js over Go/.NET | Fastest build; universal readability; app is not the focus |
| 5 | ghcr.io over ACR | Free; no Azure dependency for image hosting; simpler setup |
| 6 | Raw YAML + Kustomize over Helm | Transparency; audience sees exactly what's deployed |
| 7 | CI updates manifests (not Flux Image Automation) | Simpler; more transparent; easier to explain on stage |
| 8 | NodePort over Ingress | Minimal moving parts; demo doesn't need TLS or routing |
| 9 | Single cluster, single environment | One story, clearly told |
| 10 | `az` CLI scripts over Terraform | Two resources don't need IaC overhead |

---

*This architecture is designed to be built by the team in ~2–3 days. It's demo-grade: tight scope, clear flow, no unnecessary complexity. The audience should walk away understanding exactly how Azure Arc + GitOps enables cloud-managed on-prem deployments.*
