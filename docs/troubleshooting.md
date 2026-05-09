# Azure Arc Demo — Troubleshooting Guide

**Comprehensive troubleshooting for common issues during setup and demo.**

---

## Azure VM Path Issues

### SSH Connection Refused When Fetching Kubeconfig

#### Symptoms

- `scripts/provision-demo-vm.sh` completes but `kubectl get nodes` fails with "connection refused"
- Error: `ssh: connect to host <IP> port 22: Connection refused`

#### Root Cause & Fix

The VM is still initializing after the script creates it. Azure VMs take 30–60 seconds to become reachable via SSH after creation.

**Fix:** Wait 60 seconds and retry:
```bash
sleep 60
export KUBECONFIG=~/.kube/arc-demo-config
kubectl get nodes
```

If still failing, verify:
1. VM exists in Azure Portal: `az vm list -g rg-arc-demo`
2. VM has a public IP: `az vm show -g rg-arc-demo -n arc-demo-vm -d | grep publicIps`
3. SSH key permissions: `chmod 600 ~/.ssh/id_rsa` (if using key auth)

---

### kubectl Get Nodes Shows Connection Refused After Kubeconfig Copy

#### Symptoms

- `scripts/provision-demo-vm.sh` completes and kubeconfig is copied to `~/.kube/arc-demo-config`
- `export KUBECONFIG=~/.kube/arc-demo-config && kubectl get nodes` fails with "connection refused" on port 6443

#### Root Cause

The kubeconfig is patched with the VM's public IP, but the Azure Network Security Group (NSG) hasn't applied the inbound rule for port 6443 yet. NSG updates take ~30 seconds.

**Fix:** Wait for the NSG rule to apply:
```bash
sleep 30
kubectl get nodes
```

To verify NSG rules were created:
```bash
az vm open-port -g rg-arc-demo -n arc-demo-vm --port 6443
```

Then retry:
```bash
kubectl get nodes
```

---

### K3s Install Returns Error via VM Run-Command

#### Symptoms

- `scripts/provision-demo-vm.sh` runs but the K3s installation step fails
- Error message: `"curl: (6) Could not resolve host get.k3s.io"` or similar network error

#### Root Cause

The VM doesn't have outbound internet access, or DNS resolution is blocked.

**Fix:**

1. **Check VM internet access:**
   ```bash
   az vm run-command invoke -g rg-arc-demo -n arc-demo-vm \
     --command-id RunShellScript \
     --scripts "curl -v https://get.k3s.io"
   ```

2. **If curl fails, check network:**
   - Verify the VM has a public IP or NAT gateway: `az vm show -g rg-arc-demo -n arc-demo-vm -d`
   - Check NSG outbound rules allow port 443 (HTTPS)
   - Try a different DNS: Add `8.8.8.8` to `/etc/resolv.conf` on the VM

3. **Re-run the provisioning script** after verifying internet access:
   ```bash
   bash scripts/provision-demo-vm.sh
   ```

---

## Flux Not Reconciling

### Symptoms

- Azure Portal shows Flux compliance state as "Error" or "Unknown"
- No pods appear in `arc-demo` namespace even after waiting 2+ minutes
- `kubectl get fluxconfigs -A` shows status other than "Reconciled"

### Root Causes & Fixes

#### Flux Extension Not Installed

**Check:**
```bash
kubectl get deployment -n flux-system | grep kustomize
```

**Expected output:**
```
kustomize-controller   1/1     1            1           5m
```

**If not present:**
Re-create the Flux configuration via Azure CLI:
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

Wait 2–3 minutes for Flux controllers to initialize.

---

#### GitHub Token Permissions Missing

**Check:** Verify repository secrets are set:
```bash
gh secret list
```

You should see:
- `GHCR_TOKEN` (for pushing images)
- `ARC_DEMO_PAT` (for CI to commit manifest updates)

**Expected permissions:**
- `GHCR_TOKEN`: `packages:write`, `contents:read`
- `ARC_DEMO_PAT`: `contents:write`, `repo`

**If missing or wrong:**
1. Generate a new Personal Access Token in GitHub Settings → Developer settings → Personal access tokens
2. Set the correct scopes
3. Update the repository secret:
   ```bash
   gh secret set ARC_DEMO_PAT --body "<new-token>"
   ```
4. Wait for next CI run or manually trigger a re-reconciliation:
   ```bash
   kubectl annotate GitRepository demo-v1 \
     -n flux-system \
     reconcile.fluxcd.io/requestedAt="$(date +%s)" \
     --overwrite
   ```

---

#### Repository URL or Branch Incorrect

**Check:** Verify the Flux configuration points to the correct repo:
```bash
az k8s-configuration flux show \
  --resource-group rg-arc-demo \
  --cluster-name arc-demo-cluster \
  --cluster-type connectedClusters \
  --name demo-app-config
```

Look for the `sourceControlProperties.repositoryUrl` and `sourceControlProperties.branch`.

**Expected:**
- URL: `https://github.com/<YOUR_ORG>/demo-v1` (or your repo)
- Branch: `main`

**If wrong:**
Delete and recreate the Flux configuration with the correct values:
```bash
az k8s-configuration flux delete \
  --resource-group rg-arc-demo \
  --cluster-name arc-demo-cluster \
  --cluster-type connectedClusters \
  --name demo-app-config \
  --yes

# Then recreate with correct values
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

---

#### Kustomization Path Incorrect

**Check:** Verify the Flux configuration points to the correct GitOps path:
```bash
kubectl get kustomizations -n flux-system
```

Look at the `kustomization.yaml` in the repo:
```bash
cat gitops/kustomization.yaml
```

**Expected:** Path should be `./gitops` in the Flux configuration, and `gitops/kustomization.yaml` should exist in the repo.

**If wrong:**
Recreate the Flux configuration with the correct kustomization path (see "Repository URL or Branch Incorrect" above, but use correct `--kustomization path=./gitops`).

---

#### Check Flux Logs for Details

If the above doesn't resolve it, inspect Flux controller logs:

**Source controller logs (Git fetch issues):**
```bash
kubectl logs -n flux-system -l app=source-controller --tail=50
```

**Kustomize controller logs (manifest reconciliation issues):**
```bash
kubectl logs -n flux-system -l app=kustomize-controller --tail=50
```

Look for error messages related to:
- `"git clone failed"` → Verify GitHub URL and token permissions
- `"manifest does not exist"` → Verify `kustomization.yaml` path
- `"unauthorized"` → Check token scope

---

## Image Pull Errors

### Symptoms

- Pods in `arc-demo` namespace show status `ImagePullBackOff` or `ErrImagePull`
- `kubectl describe pod <pod-name>` shows error like `"pull access denied for ghcr.io/..."`
- Flux shows compliance error about image pull

### Root Causes & Fixes

#### Image Doesn't Exist in Registry

**Check:** Verify GitHub Actions successfully pushed the image:
1. Go to GitHub Actions workflow logs for the latest run
2. Look for the "Build and Push" step
3. Confirm it shows "Successfully pushed" for the image

**If failed:**
1. Check the workflow logs for Docker build errors
2. Verify `GHCR_TOKEN` has `packages:write` scope
3. Re-run the workflow by pushing a new commit:
   ```bash
   git commit --allow-empty -m "Retry CI"
   git push origin main
   ```

---

#### ghcr.io Package Visibility Private

**Check:** See if the package is visible in GitHub:
1. Go to Settings → Packages and registries
2. Find the `arc-demo-app` package
3. Click "Change visibility" and ensure it's set to "Public" (or adjust as needed)

**If private:** Make it public or ensure the on-prem cluster can access it with credentials.

---

#### Missing Image Pull Secret

**Check:** Verify if the cluster has credentials to pull from ghcr.io:
```bash
kubectl get secret -n arc-demo | grep ghcr
```

**If not present:** Create an image pull secret (if ghcr.io package is private):
```bash
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=<your-github-username> \
  --docker-password=<your-ghcr-token> \
  -n arc-demo
```

Then update the deployment to reference it:
```yaml
# In gitops/demo-app/deployment.yaml
spec:
  imagePullSecrets:
  - name: ghcr-secret
  containers:
  - image: ghcr.io/...
```

Commit and push, then Flux will reconcile.

---

#### Manual Retry

Force a pod restart to trigger a fresh image pull attempt:
```bash
kubectl rollout restart deployment/arc-demo-app -n arc-demo
```

Then watch the pod status:
```bash
kubectl get pods -n arc-demo -w
```

---

## Arc Agent Disconnected

### Symptoms

- Azure Portal shows Arc-connected cluster status as "Disconnected"
- Arc agent pods in `azure-arc` namespace are not running or are in `CrashLoopBackOff`
- `kubectl get nodes` shows `NotReady` status

### Root Causes & Fixes

#### Outbound Network Connectivity Blocked

**Check:** From the on-prem machine, verify outbound HTTPS access to Azure:
```bash
curl -v https://login.microsoftonline.com/
curl -v https://management.azure.com/
```

Both should respond with HTTP 200 or redirect (not "Connection refused" or timeout).

**If blocked:**
- Check firewall rules on the on-prem network
- Verify NSG (Network Security Group) rules if using Azure VMs
- Verify no corporate proxy is blocking the connection
- If behind a proxy, configure the Arc agent to use it

**To re-enable after fixing network:**
```bash
./scripts/setup-arc.sh \
  --subscription-id <your-azure-subscription-id> \
  --resource-group rg-arc-demo \
  --cluster-name arc-demo-cluster \
  --location eastus
```

---

#### Arc Extension Installation Failed

**Check:** Verify Arc extension status:
```bash
kubectl get pod -n azure-arc | grep arcagent
```

**Expected:** Multiple pods running (e.g., `azure-arc-arcagent-xxxxx`).

**If pods are in `CrashLoopBackOff`:**
1. Check pod logs:
   ```bash
   kubectl logs -n azure-arc <pod-name> --tail=50
   ```
2. Look for errors related to:
   - `"connection refused"` → Network connectivity issue
   - `"authentication failed"` → Credentials/permissions issue
   - `"timed out"` → Network latency or DNS resolution

**To re-install Arc:**
1. Disconnect the cluster:
   ```bash
   az connectedk8s delete \
     --resource-group rg-arc-demo \
     --name arc-demo-cluster
   ```
2. Wait 2–3 minutes
3. Re-connect:
   ```bash
   ./scripts/setup-arc.sh \
     --subscription-id <your-azure-subscription-id> \
     --resource-group rg-arc-demo \
     --cluster-name arc-demo-cluster \
     --location eastus
   ```

---

#### DNS Resolution Issue

**Check:** From the on-prem machine, verify DNS:
```bash
nslookup login.microsoftonline.com
nslookup management.azure.com
```

Both should resolve to IP addresses.

**If DNS fails:**
- Check `/etc/resolv.conf` on the machine (Linux)
- Configure proper DNS servers (e.g., `8.8.8.8`)
- Re-run Arc setup after DNS is fixed

---

## CI Failing to Push Manifest Update

### Symptoms

- GitHub Actions workflow completes but shows a failed "Update Manifests" or "Commit" step
- Error message like `"Authentication failed"` or `"Permission denied"`
- Manifest in Git is not updated with new image tag

### Root Causes & Fixes

#### ARC_DEMO_PAT Token Missing or Expired

**Check:** Verify the secret is set:
```bash
gh secret list
```

You should see `ARC_DEMO_PAT` listed.

**If missing:**
1. Create a new Personal Access Token in GitHub (Settings → Developer settings → Personal access tokens)
2. Grant `contents:write` and `repo` scopes
3. Set the secret:
   ```bash
   gh secret set ARC_DEMO_PAT --body "<new-token>"
   ```

**If expired:**
- Create a new token and update the secret (same steps as above)

---

#### Token Lacks Correct Permissions

**Check:** Verify the token has the right scopes in GitHub Settings:
- Required scopes: `contents:write`, `repo`

**If scopes are wrong:**
1. Delete the old token
2. Create a new one with correct scopes:
   - `repo` (full control of private repositories)
   - `write:packages` (write to Container Registry)
3. Update the repository secret:
   ```bash
   gh secret set ARC_DEMO_PAT --body "<new-token>"
   ```

---

#### Branch Protection Rules Blocking Commits

**Check:** Go to GitHub repo Settings → Branches → Branch protection rules. Verify:
- The rule doesn't require reviews for the CI bot
- The rule allows force pushes (if needed) or automated commits

**If blocking:**
1. Add the CI bot (e.g., `github-actions`) to "Dismiss stale pull request approvals"
2. Or, lower the required review count for automated commits
3. Or, create an exception for commits from the CI workflow

Check the GitHub Actions workflow logs to see if the commit was rejected.

---

#### Manifest File Path Incorrect in Workflow

**Check:** Open `.github/workflows/ci.yml` and look for the step that updates the manifest:
```yaml
- name: Update image tag in manifest
  run: |
    sed -i 's|image:.*|image: ghcr.io/...:<TAG>|' gitops/demo-app/deployment.yaml
```

Verify:
- The file path `gitops/demo-app/deployment.yaml` exists in the repo
- The `sed` pattern matches the image line in the manifest

**If wrong:**
1. Fix the `sed` pattern or file path in the workflow
2. Commit and push:
   ```bash
   git add .github/workflows/ci.yml
   git commit -m "Fix: correct manifest path in CI"
   git push origin main
   ```

---

## App Not Reachable on NodePort 30080

### Symptoms

- Browser shows "Connection refused" or times out at `http://<on-prem-ip>:30080`
- `kubectl get svc -n arc-demo` doesn't show the service or shows a different port

### Root Causes & Fixes

#### Service Not Created

**Check:** Verify the service exists:
```bash
kubectl get svc -n arc-demo
```

**Expected output:**
```
NAME           TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
arc-demo-app   NodePort   10.43.x.x      <none>        80:30080/TCP   5m
```

**If missing:**
1. Check if the namespace exists:
   ```bash
   kubectl get ns arc-demo
   ```
2. If not, manually apply the manifests:
   ```bash
   kubectl apply -f gitops/demo-app/namespace.yaml
   kubectl apply -f gitops/demo-app/service.yaml
   ```
3. Or, trigger Flux to reconcile:
   ```bash
   kubectl annotate GitRepository demo-v1 \
     -n flux-system \
     reconcile.fluxcd.io/requestedAt="$(date +%s)" \
     --overwrite
   ```

---

#### Deployment Has No Running Pods

**Check:** Verify pods are running:
```bash
kubectl get pods -n arc-demo
```

**Expected:**
```
NAME                            READY   STATUS    RESTARTS   AGE
arc-demo-app-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
```

**If pods are not running:**
1. Check for image pull errors (see "Image Pull Errors" section)
2. Check pod logs:
   ```bash
   kubectl logs -n arc-demo <pod-name>
   ```
3. Check pod events:
   ```bash
   kubectl describe pod -n arc-demo <pod-name>
   ```

---

#### Firewall or Network Security Group Blocking Port 30080

**Check (on-prem machine):**
1. Verify the port is listening:
   ```bash
   sudo netstat -tlnp | grep 30080
   ```
2. Check firewall rules:
   ```bash
   # On Linux with ufw:
   sudo ufw status
   sudo ufw allow 30080

   # On Linux with iptables:
   sudo iptables -L -n | grep 30080
   ```

**Check (if on Azure VM):**
1. Go to Azure Portal → VM → Networking
2. Check Network Security Group rules
3. Add an inbound rule to allow TCP 30080 from your IP:
   ```
   Protocol: TCP
   Port: 30080
   Source: Your IP (or 0.0.0.0/0 for testing)
   Action: Allow
   ```

**If firewall is the issue:**
Configure firewall rules to allow inbound traffic on port 30080.

---

#### NodePort Assigned to Different Port

**Check:** Look at the service again:
```bash
kubectl get svc -n arc-demo arc-demo-app -o yaml | grep nodePort
```

**Possible output:**
```
nodePort: 30081  # Not 30080!
```

**If port is different:**
Use the actual NodePort shown in the service. Or, manually set the NodePort in the service manifest:
```yaml
# In gitops/demo-app/service.yaml
spec:
  type: NodePort
  ports:
  - port: 80
    targetPort: 3000
    nodePort: 30080  # Explicitly set
```

Commit and push, then Flux will update the service.

---

## Full Reset Procedure

If multiple issues are occurring and you want to start fresh:

### Step 1: Teardown Everything

```bash
./scripts/teardown.sh \
  --resource-group rg-arc-demo \
  --cluster-name arc-demo-cluster
```

This removes:
- Flux configuration
- Arc agent and extension
- Application namespace and workloads
- Arc resource group (optional confirmation)

### Step 2: Wait for Cleanup

Wait 2–3 minutes for Azure to clean up resources.

### Step 3: Re-setup Arc

```bash
./scripts/setup-arc.sh \
  --subscription-id <your-azure-subscription-id> \
  --resource-group rg-arc-demo \
  --cluster-name arc-demo-cluster \
  --location eastus
```

### Step 4: Re-deploy Flux

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

### Step 5: Verify

Wait 2–3 minutes, then check:
```bash
kubectl get deployment -n arc-demo
kubectl get pods -n arc-demo
```

Pods should be running. If not, check Flux compliance in Azure Portal.

### Step 6: Resume Demo

Push a commit to trigger the CI pipeline:
```bash
git commit --allow-empty -m "Resume demo"
git push origin main
```

Watch GitHub Actions run, then verify the app is reachable.

---

## Getting Help

| Resource | When to Use |
|----------|------------|
| **Azure Arc logs** | `kubectl logs -n azure-arc -l app=arcagent --tail=100` for connectivity issues |
| **Flux logs** | `kubectl logs -n flux-system -l app=kustomize-controller --tail=100` for reconciliation issues |
| **GitHub Actions logs** | For CI/CD pipeline failures (see workflow run details) |
| **Azure Portal** | Check Arc-connected cluster status and Flux compliance state |
| **kubectl events** | `kubectl get events -n arc-demo --sort-by='.lastTimestamp'` for deployment issues |

---

## Frequently Asked Questions

**Q: How long does Flux take to reconcile?**
A: Flux polls the Git repository every 60 seconds by default. A full reconciliation (from push to new pods running) typically takes 2–3 minutes.

**Q: Can I make Flux check more frequently?**
A: Yes, set `interval=30s` in the Flux configuration. But for a demo, 1 minute is fast enough.

**Q: What if I need to revert a deployment?**
A: Revert the Git commit and push. Flux will reconcile the previous version.

**Q: Can I manually trigger a Flux reconciliation?**
A: Yes:
```bash
kubectl annotate GitRepository demo-v1 \
  -n flux-system \
  reconcile.fluxcd.io/requestedAt="$(date +%s)" \
  --overwrite
```

**Q: What if the on-prem network goes down during the demo?**
A: Flux is a declarative system — it will reconcile as soon as the network is back. If the cluster reboots, Arc will reconnect automatically on next boot.
