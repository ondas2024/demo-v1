# Azure Arc Demo — Live Presentation Script

**Designed for a 5-minute live demo with 1–2 minute buffer.**

Each step is written as a script: **what you do**, **what the audience sees**, and **what you say**. Read the talking points naturally — don't read verbatim.

---

## Pre-Demo Setup (15 Minutes Before)

**You do:** Choose your path and prepare the cluster.

### Option A: Azure VM (Recommended)

If you don't have on-premises hardware, use an Azure VM to simulate your infrastructure:

```bash
export RESOURCE_GROUP="rg-arc-demo"
export LOCATION="eastus"
export VM_NAME="arc-demo-vm"
bash scripts/provision-demo-vm.sh
```

**Setup time:** ~8 minutes. While the VM is provisioning (K3s installs remotely), proceed to setting up Arc.

Once K3s is running:
```bash
export CLUSTER_NAME="arc-demo-cluster"
export REPO_URL="https://github.com/<YOUR_ORG>/demo-v1"
export KUBECONFIG=~/.kube/arc-demo-config
bash scripts/setup-arc.sh
```

**Total time:** ~10–12 minutes. Start 15 minutes before demo time.

### Option B: Physical On-Prem Hardware

If you're using existing on-prem infrastructure or a self-managed VM:

```bash
# Ensure K3s is installed on your machine
curl -sfL https://get.k3s.io | sh -

# Then run Arc setup
export CLUSTER_NAME="arc-demo-cluster"
export REPO_URL="https://github.com/<YOUR_ORG>/demo-v1"
bash scripts/setup-arc.sh
```

**Setup time:** ~5 minutes if K3s is already running.

### Before You Go Live

Verify everything works:
```bash
bash scripts/verify-deployment.sh
```

Expected output:
- ✓ Flux compliance: Succeeded
- ✓ Pods: Running
- ✓ App: Reachable (HTTP 200)

**If any checks fail, see** [`docs/troubleshooting.md`](../docs/troubleshooting.md) **for recovery steps.**

---

## Step 1: Introduce the Demo

**You do:** Open a terminal, show the repo on your machine (run `ls -la` or open the folder in an IDE).

**Audience sees:** 
- Terminal or file explorer showing the demo-v1 folder structure
- Three main directories: `src/`, `gitops/`, `.github/workflows/`

**Say:** 
*"This is a single GitHub repository that holds everything for this demo. We have our application source code, our GitOps configuration for Kubernetes, and our CI pipeline. Everything is in one place, so you can follow the entire flow from code to deployment."*

**If it goes wrong:** If the repo structure isn't visible or you're in the wrong directory, `cd demo-v1` and run `tree -L 2` or `ls -la` again.

---

## Step 2: Show the On-Premises Cluster in Azure Portal

**You do:** 
1. Open the Azure Portal in a browser
2. Navigate to your resource group (`rg-arc-demo`)
3. Click on the Arc-connected cluster resource (`arc-demo-cluster`)

**Audience sees:**
- The Azure Portal showing the Arc-connected cluster blade
- Status showing "Connected" (green checkmark)
- The cluster overview showing it's a Kubernetes cluster (cluster type, API server address, etc.)

**Say:**
*"This is our on-premises Kubernetes cluster, now visible in the Azure Portal through Azure Arc. Arc projects on-prem infrastructure into Azure for centralized management. To Azure, it looks like any other cluster — but it's actually running on our local machine. No inbound firewall rules, no VPN — just an outbound connection to Azure."*

**If it goes wrong:** If the cluster shows "Disconnected," check network connectivity on the on-prem machine. Re-run `scripts/setup-arc.sh` if needed. If the cluster doesn't appear, wait 1–2 minutes and refresh the Portal.

---

## Step 3: Show the Flux GitOps Configuration

**You do:**
1. Stay in the Azure Portal on the Arc-connected cluster blade
2. Scroll down or click on "GitOps configurations" or "Flux configurations" (Portal layout varies)
3. Click on the Flux configuration named `demo-app-config`

**Audience sees:**
- The Flux configuration details
- **Compliance state: "Succeeded"** (green)
- Source repository pointing to `https://github.com/<org>/demo-v1` on the `main` branch
- Kustomization path: `./gitops`

**Say:**
*"This is the Flux GitOps configuration. It's watching our GitHub repository for changes in the `gitops` directory. When a manifest changes in Git, Flux automatically applies it to the cluster. The compliance state shows 'Succeeded' — meaning the cluster's actual state matches the desired state in our Git repository. That's GitOps."*

**If it goes wrong:** If compliance state shows "Error," hover over it to see the error message. Common issue: incorrect GitHub token permissions. Verify `ARC_DEMO_PAT` has `contents:read` scope. If it shows "Unknown," wait 1–2 minutes and refresh.

---

## Step 4: Show the Running Application

**You do:**
1. Open a new browser tab (or split-screen view)
2. Navigate to the on-prem app URL: `http://<on-prem-machine-ip>:30080`

**Audience sees:**
- The demo app homepage
- A banner message (initially something like "Welcome to Arc Demo")
- App version (Git SHA)
- Hostname (the Kubernetes pod name)
- A timestamp showing when the app was deployed

**Say:**
*"This is our demo application running on the on-prem cluster. It's a simple Node.js app that shows the banner message, version, and pod hostname. Watch this banner — we're about to change it by pushing code to GitHub, and it will update live, deployed through Arc and GitOps."*

**If it goes wrong:** If the app isn't reachable, check that the service is running: `kubectl get svc -n arc-demo`. Verify the NodePort (e.g., 30080) and that your firewall/network allows access. If it's been more than 2–3 minutes since setup, Flux may not have reconciled yet — refresh the Portal to check Flux compliance state.

---

## Step 5: Make the Code Change

**You do:**
1. Go back to your terminal or IDE
2. Open `gitops/demo-app/deployment.yaml`
3. Find the `BANNER_MESSAGE` environment variable
4. Change its value to something visible and memorable (e.g., `"🚀 Deployed via Arc GitOps!"`)

**Audience sees:**
- The YAML file on screen
- The banner message being edited in real time

**Say:**
*"I'm going to change the banner message in the deployment manifest. This is the Git source of truth — when I commit and push this change, Flux will see it and deploy the new version automatically."*

**If it goes wrong:** If you can't find the file or environment variable, check the file path is correct: `gitops/demo-app/deployment.yaml`. Search for `BANNER_MESSAGE` in your editor.

---

## Step 6: Commit and Push to GitHub

**You do:**
```bash
git add gitops/demo-app/deployment.yaml
git commit -m "Demo: update banner message"
git push origin main
```

**Audience sees:**
- Terminal output showing the commit and push

**Say:**
*"We're pushing the change to GitHub on the `main` branch. GitHub Actions will now trigger our CI pipeline to build a new container image with this updated manifest and push it back to the repository."*

**If it goes wrong:** If `git push` fails with a permissions error, verify you have write access to the repository and your SSH key or GitHub credentials are configured.

---

## Step 7: Watch GitHub Actions CI Run

**You do:**
1. Go to the GitHub repository in a browser (if not already there)
2. Click on the "Actions" tab
3. Watch the latest workflow run in real time

**Audience sees:**
- The GitHub Actions workflow running
- Job names: e.g., "Build and Push", "Update Manifests"
- Status progressing from "In progress" (yellow) to "Completed" (green)
- Logs showing Docker build steps, image push to ghcr.io, manifest update commit

**Say:**
*"Our CI pipeline is running. It's building a new Docker image from the updated code, pushing it to our container registry (ghcr.io), and then automatically updating the manifest with the new image tag. The CI pipeline commits that change back to the repository, which is the trigger for Flux to reconcile."*

**If it goes wrong:** If the workflow fails, click into it to see logs. Common issues: GitHub token permissions (check `GHCR_TOKEN` and `ARC_DEMO_PAT` in repository secrets), or a syntax error in the manifest (check the workflow logs for `sed` or YAML parsing errors).

---

## Step 8: Watch Flux Reconcile

**You do:**
Choose one of these two options (or both):

**Option A (Portal):**
1. Go back to the Azure Portal
2. Open the Flux configuration (`demo-app-config`)
3. Look at the "Compliance state" and "Last deployment" timestamp
4. Refresh and watch it update

**Option B (kubectl on the on-prem machine):**
```bash
kubectl get pods -n arc-demo -w
```
Watch new pods appear and old ones terminate.

**Audience sees:**
- (Portal) Compliance state stays "Succeeded", timestamp updates to current time
- (kubectl) Pod rolling update in real time (new pods with age "0s", old pods terminating)

**Say:**
*"Flux detected the manifest change in Git. It's now reconciling — pulling the new image and rolling out new pods on the cluster. Within 60 seconds, the new version will be live. You can see it happening in the Azure Portal (compliance state) or directly on the cluster (new pods spinning up)."*

**If it goes wrong:** If no new pods appear after 2 minutes, check Flux compliance state in Portal for errors. If it shows an image pull error, verify the ghcr.io image exists and is accessible (check the GitHub Actions workflow logs to confirm the push succeeded).

---

## Step 9: Refresh the Browser and See the Change

**You do:**
1. Go back to the browser tab with the demo app
2. Refresh the page (F5 or Cmd+R)

**Audience sees:**
- The app homepage now shows the **new banner message**
- All other details (version, hostname, timestamp) may have updated

**Say:**
*"There it is. The banner changed. We didn't SSH into the cluster. We didn't run `kubectl apply`. We just pushed code to GitHub, and GitOps handled the rest. The on-prem cluster is now running our new version, managed entirely from the cloud through Azure Arc and Flux."*

**If it goes wrong:** If the banner didn't change, wait a few more seconds and refresh again. Flux polls every 60 seconds; you may need to wait up to a minute from the time the manifest was committed. If it's been more than 2 minutes, check Flux compliance state in Portal for errors.

---

## Step 10: Verify Deployment with the Script

**You do:**
Run the verification script:
```bash
./scripts/verify-deployment.sh
```

**Audience sees:**
- Script output showing:
  - ✓ Flux compliance state (Succeeded)
  - ✓ Pod status (Running)
  - ✓ App reachable (HTTP 200)
  - ✓ New banner message in response

**Say:**
*"This script confirms everything is working: Flux is in compliance, the app is running, and the change is live. From a single `git push`, we went from code to a live deployment on an on-premises cluster, managed through the cloud."*

**If it goes wrong:** If the script shows any failures, check the error messages. Common issues:
- Flux compliance: check Portal for Flux configuration errors
- Pod status: check `kubectl describe pod` in the failing pod
- App reachability: check the NodePort and firewall rules

---

## Step 11: Close with the Story

**You do:** 
Take a breath and summarize. You can keep the Portal and browser visible behind you.

**Say:**
*"What we just showed is the core of Azure Arc + GitOps: Infrastructure as Code. Every change flows through Git, gets built in CI, and deployed through a declarative GitOps engine. It works the same whether the cluster is on Azure, on-premises, or in another cloud. No direct access needed. Just Git. That's the promise of Arc and GitOps."*

---

## Recovery Guide: If Things Go Wrong Mid-Demo

| Issue | Quick Fix |
|-------|-----------|
| **App still shows old banner** | Wait 30–60 seconds (Flux polls every minute). Then refresh. If >2 min: check Portal for Flux errors. |
| **GitHub Actions stuck on "In progress"** | It might just be slow. Give it 2–3 minutes. If it hangs, there may be a network issue; check workflow logs. |
| **Flux compliance shows "Error"** | Click into the error message in Portal. Most likely: GitHub token permissions. Quick fix: re-run `scripts/setup-arc.sh` to reinitialize. |
| **App unreachable on browser** | Check pod is running: `kubectl get pods -n arc-demo`. Check firewall rules on the on-prem machine. If pods aren't running, check Flux logs: `kubectl logs -n flux-system -l app=kustomize-controller`. |
| **Terminal command fails** | Copy-paste the exact command from the README. Verify Azure CLI is logged in: `az account show`. |

**Nuclear option (if everything breaks):** 
1. Run `./scripts/teardown.sh` to clean up
2. Run `./scripts/setup-arc.sh` again
3. Re-deploy Flux config with the `az k8s-configuration flux create` command
4. Push a commit to trigger CI
5. Resume demo from Step 3

---

## Timing Notes

| Step | Time |
|------|------|
| Steps 1–4 (Setup & explanation) | ~1 min |
| Step 5–6 (Code change + push) | ~30 sec |
| Step 7 (CI runs) | ~1–2 min |
| Step 8 (Flux reconciles) | ~1 min |
| Step 9 (Browser refresh) | ~10 sec |
| Step 10 (Verification script) | ~20 sec |
| Step 11 (Close) | ~30 sec |
| **Total** | **~5 min** (plus up to 2 min buffer if steps run slow) |

Keep an eye on the CI workflow. If it's taking longer than 2 minutes, it might be pulling base images for the first time — this is fine, just explain to the audience.

---

## Presenter Checklist (Before You Present)

- [ ] Azure Portal is open and you're logged in
- [ ] Resource group `rg-arc-demo` exists and is visible
- [ ] Arc-connected cluster shows "Connected"
- [ ] Flux configuration shows compliance "Succeeded"
- [ ] Demo app is running and reachable in browser
- [ ] Terminal is ready (you're in the repo root)
- [ ] GitHub repo is open in a browser tab
- [ ] You know the current banner message (so you can announce the change)
- [ ] Firewall/network doesn't block your access to the on-prem app

---

## Notes for Your Team

- This script assumes ~5 minutes of stage time. Adjust timing if you have more or less.
- If you have 10 minutes, you can slow down, add context, and show more Portal details.
- If you have 2 minutes, skip the verification script and just show the browser refresh.
- The script is designed so one failure doesn't kill the demo — you have recovery steps at each stage.
