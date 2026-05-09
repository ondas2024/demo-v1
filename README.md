# Azure Arc GitOps Demo

**A live demonstration showing how to deploy application code to on-premises infrastructure using Azure Arc and Flux GitOps — no direct cluster access required.**

---

## What This Demo Shows

- **Cloud-managed on-prem deployment:** A developer pushes code to GitHub. Without SSH or kubectl access to the on-prem cluster, Azure Arc + Flux automatically deploys the change. Audience sees the app update live in a browser.
- **GitOps in Azure Portal:** The Arc-connected cluster and Flux GitOps configuration are visible and manageable in the Azure Portal — exactly like a cloud cluster.
- **End-to-end flow:** `git push` → GitHub Actions builds and pushes a container image → Flux reconciles the new image onto the on-prem Kubernetes cluster → app is live (all within ~2 minutes).
- **Zero direct cluster access:** The entire deployment happens through Git commits and Azure Arc's outbound connectivity model. No inbound firewall rules. No VPN. No manual `kubectl apply`.

---

## Quick Start (No Hardware Required)

**Don't have on-premises infrastructure?** No problem. You can simulate the on-prem cluster using an Azure Linux VM running K3s. This is the recommended path for demos where physical hardware isn't available.

### 3-Minute Setup Flow

```bash
# 1. Provision an Azure VM to simulate on-prem infrastructure
export RESOURCE_GROUP="rg-arc-demo"
export LOCATION="eastus"
export VM_NAME="arc-demo-vm"
bash scripts/provision-demo-vm.sh

# 2. Connect the VM's K3s cluster to Azure Arc (run after VM is ready)
export CLUSTER_NAME="arc-demo-cluster"
export REPO_URL="https://github.com/<YOUR_ORG>/demo-v1"
export KUBECONFIG=~/.kube/arc-demo-config
bash scripts/setup-arc.sh

# 3. Verify everything is working
bash scripts/verify-deployment.sh
```

### What Happens

- **Step 1** creates a Standard_D2s_v3 Linux VM (Ubuntu 22.04) and installs K3s remotely via Azure VM run-command. K3s is running within ~8 minutes.
- **Step 2** connects the cluster to Azure Arc and deploys Flux. Kubeconfig is copied locally with the VM's public IP patched in.
- **Step 3** checks that Flux is reconciling, pods are running, and the app is reachable.

### Cost & Cleanup

The VM runs at approximately **$0.10/hour.12/hour** (Standard_D2s_v3). After your demo:
```bash
bash scripts/teardown.sh
```
This removes all Azure resources — VM, resource group, Arc resources — and deletes local kubeconfig.

---

## Architecture

```
Developer Push to GitHub
    ↓
GitHub Actions CI (build image, update manifest)
    ↓
Container Image → ghcr.io
    ↓
Flux GitOps (watches repo, reconciles manifests)
    ↓
On-Prem K3s Cluster (via Azure Arc)
    ↓
App Live (browser sees the change)
```

**The key insight:** Flux runs on the on-prem cluster and watches the Git repository. When a manifest changes in Git, Flux applies it automatically. The "deployment" happens entirely through declarative configuration in Git and Kubernetes reconciliation on the cluster — not through manual commands.

For a detailed architecture diagram and component breakdown, see [`docs/architecture.md`](docs/architecture.md).

---

## Prerequisites

### On Your Machine

| Tool | Version | Purpose |
|------|---------|---------|
| Azure CLI (`az`) | 2.60+ | Connect cluster to Azure Arc |
| `az connectedk8s` extension | Latest | Arc cluster operations |
| `az k8s-configuration` extension | Latest | Flux configuration management |
| `kubectl` | 1.28+ | Verify cluster state during demo |
| Git | 2.40+ | Push code to GitHub |
| GitHub CLI (`gh`) | Latest | Manage repository secrets |

Install extensions:
```bash
az extension add --name connectedk8s
az extension add --name k8s-configuration
```

### Azure Setup

- **Azure subscription** with Contributor-level access
- **Resource group** named `rg-arc-demo` (or adjust `scripts/setup-arc.sh`)
- **Service principal** or local `az login` session with permissions to create resources

### On-Premises Environment

**Option A: Azure VM (Recommended for demos without hardware)**
- Run `bash scripts/provision-demo-vm.sh` to automatically create and provision a Standard_D2s_v3 Linux VM with K3s
- Takes ~8 minutes; VM costs ~$0.10/hour.12/hour

**Option B: Physical on-prem machine or self-managed VM**
- **Linux machine** (Ubuntu 22.04+ recommended) to run K3s
- **K3s cluster** installed and running
  ```bash
  curl -sfL https://get.k3s.io | sh -
  ```
- **Outbound HTTPS access** to Azure (no inbound firewall rules required)
- **`kubeconfig`** file accessible for Arc onboarding

### GitHub Repository Setup

- **Repository** created with Actions enabled
- **Secret: `GHCR_TOKEN`** — A GitHub Personal Access Token with `packages:write` scope (for pushing container images)
- **Secret: `ARC_DEMO_PAT`** — A GitHub PAT with `contents:write` scope (for CI to commit manifest updates back to the repo)

Add secrets via GitHub UI or:
```bash
gh secret set GHCR_TOKEN --body "<your-token>"
gh secret set ARC_DEMO_PAT --body "<your-pat>"
```

---

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/<YOUR_ORG>/demo-v1.git
cd demo-v1
```

### 2. Configure Azure Resources

Create the Azure Arc resource group:
```bash
az group create --name rg-arc-demo --location eastus
```

### 3. Setup On-Premises Cluster

On the Linux machine where K3s will run:
```bash
# Run this script to connect the K3s cluster to Azure Arc
./scripts/setup-arc.sh \
  --subscription-id <your-azure-subscription-id> \
  --resource-group rg-arc-demo \
  --cluster-name arc-demo-cluster \
  --location eastus
```

This script:
- Connects the K3s cluster to Azure Arc (creates the Arc-connected cluster resource)
- Installs the Azure Arc agent pods in the `azure-arc` namespace
- Verifies connectivity

### 4. Deploy Flux GitOps Configuration

```bash
az k8s-configuration flux create \
  --resource-group rg-arc-demo \
  --cluster-name arc-demo-cluster \
  --cluster-type connectedClusters \
  --name demo-app-config \
  --namespace flux-system \
  --scope cluster \
  --url https://github.com/<YOUR_ORG>/demo-v1 \
  --branch main \
  --kustomization name=demo-app path=./gitops interval=1m prune=true
```

This creates a Flux GitOps configuration that watches the `gitops/` directory in the `main` branch.

### 5. Verify Flux Reconciliation

Wait 1–2 minutes for Flux to reconcile, then check:
```bash
kubectl get deployment -n arc-demo
kubectl get pods -n arc-demo
```

You should see the `arc-demo-app` deployment running with one or more pods.

### 6. Access the Application

On the on-prem machine, get the service NodePort:
```bash
kubectl get svc -n arc-demo
# Look for arc-demo-app service on port 30080 (or similar)
```

In your browser, visit the on-prem machine on that port:
```
http://<on-prem-machine-ip>:30080
```

You should see the demo app homepage with banner, version, and hostname.

---

## Running the Demo

### Before You Present

1. **Verify the cluster is connected:** In the Azure Portal, navigate to your resource group. You should see the Arc-connected cluster and the Flux configuration showing "Succeeded" compliance state.
2. **Verify the app is running:** Open the app URL in a browser and confirm you see the banner and app details.
3. **Have a code editor ready:** You'll edit the `BANNER_MESSAGE` in `gitops/demo-app/deployment.yaml` during the demo.

### The Demo Flow

1. **Show the repo structure** — Explain single-repo layout: source code in `src/`, GitOps manifests in `gitops/`, CI pipeline in `.github/workflows/`.
2. **Show the Arc-connected cluster in Portal** — Navigate to the resource group, open the Arc-connected cluster blade. Point out it's an on-prem cluster managed from Azure.
3. **Show the Flux configuration** — In the Portal, show the Flux configuration and compliance state.
4. **Make a code change** — Edit `gitops/demo-app/deployment.yaml` and change the `BANNER_MESSAGE` environment variable to something visible (e.g., "Hello from Arc! 🚀").
5. **Commit and push** — `git add`, `git commit`, `git push origin main`.
6. **Watch GitHub Actions** — Open the GitHub Actions tab and watch the CI workflow run. It builds the image, pushes it to ghcr.io, updates the manifest, and commits the change.
7. **Watch Flux reconcile** — In the Portal, open the Flux configuration and watch the compliance state. Or on the cluster: `kubectl get pods -n arc-demo -w` to see new pods rolling out.
8. **Refresh the browser** — The demo app now shows the new banner message. The on-prem app has been updated from the cloud through Git and GitOps.
9. **Verify with the script** — Run `./scripts/verify-deployment.sh` to confirm deployment health. It checks Flux compliance, pod status, and app reachability.

**Total time:** ~2–3 minutes for the entire flow.

For a detailed step-by-step presenter script with talking points, see [`docs/demo-script.md`](docs/demo-script.md).

---

## Cleanup

To tear down all resources:

```bash
./scripts/teardown.sh \
  --resource-group rg-arc-demo \
  --cluster-name arc-demo-cluster
```

This script:
- Removes the Flux configuration
- Disconnects the cluster from Azure Arc
- Cleans up the Arc resource group (optional, can be confirmed interactively)
- Removes deployed application resources

---

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| **Flux not reconciling** | Flux extension not installed, or Git source not accessible | Run `kubectl get fluxconfigs -A` to check status. Verify GitHub token permissions. See full guide in [`docs/troubleshooting.md`](docs/troubleshooting.md). |
| **Image pull error** | ghcr.io package visibility, or image doesn't exist | Ensure `GHCR_TOKEN` is set with `packages:write` scope. Check GitHub Actions workflow logs. |
| **Arc agent disconnected** | Outbound HTTPS blocked, or Arc extension not installed | Check on-prem network connectivity to Azure. Re-run `scripts/setup-arc.sh`. |
| **CI fails to push manifest** | `ARC_DEMO_PAT` token missing or lacks `contents:write` | Verify `ARC_DEMO_PAT` is set in GitHub secrets with correct permissions. |
| **App not reachable on NodePort** | Service not created, or firewall blocking | Run `kubectl get svc -n arc-demo`. Check VM NSG rules and firewall. |

For detailed troubleshooting steps and recovery procedures, see [`docs/troubleshooting.md`](docs/troubleshooting.md).

---

## Architecture & Design

This demo is intentionally scoped:
- **Single K3s cluster** simulates on-prem infrastructure (not multi-cluster)
- **Flux v2 (Arc extension)** is the GitOps engine (not ArgoCD or Helm)
- **Node.js Express app** is the deployable artifact (minimal, fast builds)
- **Raw YAML + Kustomize** shows exactly what's deployed (not Helm abstraction)
- **One repository** keeps the flow visible (not separate app/gitops repos)

See [`docs/architecture.md`](docs/architecture.md) for the full design rationale and component breakdown.

---

## Questions?

Reach out to the demo team or check [`docs/troubleshooting.md`](docs/troubleshooting.md) for common issues and their solutions.
