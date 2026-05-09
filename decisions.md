# Decisions Log

> Project: demo-v1
> Last Updated: 2026-05-09

---

## Decision: Azure VM Provisioning for Demo Cluster

> Author: Naomi (DevOps / Platform Engineer)
> Date: 2026-05-09
> Status: Active
> Scope: Azure Arc demo — on-prem cluster simulation

### Context

The Azure Arc demo requires a Kubernetes cluster that Arc can connect to and manage.
The original setup assumed a physical Linux machine (or local VM) where `setup-cluster.sh`
would install K3s. This creates a friction point for presenters: they need dedicated hardware
or a running local hypervisor before the demo can even be staged.

The request: eliminate the hardware dependency by provisioning an Azure Linux VM that plays
the role of the "on-prem" cluster. From Arc's perspective, it is an on-prem cluster — a
Kubernetes node that Arc connects to and manages over outbound HTTPS. The fact that the VM
lives in Azure is an implementation detail invisible to the demo flow.

### Decision: Standard_B2s Ubuntu 22.04 VM via `az vm create`

**VM size:** Standard_B2s (2 vCPUs, 4 GB RAM)
- Fits K3s + Arc agents + the demo app comfortably (K3s needs ~512 MB; Arc agents ~256 MB)
- Cheapest burstable size that doesn't risk OOM during the Arc onboarding step
- At ~$0.04/hour it costs under $1 for a full demo day

**Image:** Ubuntu2204 (Ubuntu 22.04 LTS)
- K3s officially tested and supported on Ubuntu 22.04
- Long-term support image: no mid-demo OS update nags

**SSH key:** `--generate-ssh-keys`
- Uses `~/.ssh/id_rsa` if it exists, generates a new pair if not
- Zero interaction required — no password prompts
- Private key stays on the presenter's machine; public key is injected into the VM at create time

### Decision: `az vm run-command invoke` for K3s install (no SSH during setup)

The K3s install runs via:
```
az vm run-command invoke \
  --command-id RunShellScript \
  --scripts "curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='--write-kubeconfig-mode 644' sh -"
```

**Why run-command instead of SSH:**
- `az vm run-command invoke` uses the Azure VM agent channel, not network SSH
- Works immediately after VM creation — no waiting for SSH to become ready, no known_hosts management
- The command exits with the shell's return code, so errors surface clearly
- Keeps the script self-contained: no `ssh -i key user@ip 'curl ...'` fragility

`--write-kubeconfig-mode 644` is required so that `azureuser` can scp the kubeconfig
without sudo. Without it, `/etc/rancher/k3s/k3s.yaml` is `root:root 600` and the scp fails.

### Decision: Kubeconfig patched and saved to `~/.kube/arc-demo-config`

K3s writes `server: https://127.0.0.1:6443` in its kubeconfig because from the VM's perspective
the API server is local. We `sed -i 's/127.0.0.1/{VM_IP}/g'` after the scp to make the
address reachable from the presenter's machine.

Destination: `~/.kube/arc-demo-config` (not `~/.kube/config`)
- Avoids clobbering any existing kubeconfig the presenter may have
- Requires `export KUBECONFIG=~/.kube/arc-demo-config` — this is explicit and visible
- Documented in `setup-arc.sh` Step 2 header so presenters know what to do

### Decision: Idempotent VM creation (check before create)

`az vm show` is run before `az vm create`. If the VM already exists, creation is skipped.
This handles interrupted runs (e.g., VM created but K3s failed) cleanly: re-running the
script will skip VM creation and retry K3s install and kubeconfig fetch.

### Decision: VM cleanup is a non-event

The VM is in the same resource group (`rg-arc-demo`) as all other demo resources.
`teardown.sh`'s `az group delete` removes everything — VM, NIC, NSG, disk, public IP —
in a single call. No separate VM teardown step needed.

This was noted in `teardown.sh` under the summary section to prevent presenters from
wondering "what about the VM?" after running teardown.

### Files Changed

| File | Change |
|------|--------|
| `scripts/provision-demo-vm.sh` | **New** — full VM + K3s provisioning script |
| `scripts/setup-arc.sh` | Added KUBECONFIG note to Step 2 header |
| `scripts/teardown.sh` | Added note that VM is deleted with resource group |

---

## Decision: Azure VM Demo Path Documentation

> Author: Clarissa (DevRel/Docs)
> Date: 2026-05-09
> Status: Complete
> Scope: Documentation updates to support Azure VM-based demo setup

### Context

Naomi has built `scripts/provision-demo-vm.sh`, which automates creation of an Azure Linux VM (Standard_B2s) running K3s, allowing demos to run without requiring physical on-premises hardware. Presenters and audience don't care about infrastructure deployment details — they only care that "on-prem" is set up correctly and demo pacing is maintained. Documentation must make this path clear, obvious, and fast to execute.

### Documentation Changes

#### README.md

**Added:** "Quick Start (No Hardware Required)" section after "What This Demo Shows" and before "Architecture."

**Content:**
- Headline explaining the Azure VM path is recommended for demos
- 3-step flow showing exact bash commands (`provision-demo-vm.sh` → `setup-arc.sh` → `verify-deployment.sh`)
- Setup time estimate (~8 minutes for VM, ~2 minutes for Arc setup)
- Cost note ($0.10/hour, Standard_B2s)
- Cleanup instructions (`teardown.sh`)

**Updated:** Prerequisites section to show two paths:
- Option A: Azure VM (recommended) — click-and-go automation
- Option B: Physical on-prem — for presenters with existing hardware

**Rationale:** Presenters looking at the README should immediately see the Azure VM path as the default. It removes decision paralysis ("do I have hardware?") and puts the easy button first. The physical hardware path still exists for users who need it.

#### docs/demo-script.md

**Added:** "Pre-Demo Setup (15 Minutes Before)" section as the first step, before "Step 1: Introduce the Demo."

**Content:**
- Explains both paths (Azure VM vs. physical hardware)
- Azure VM path: `provision-demo-vm.sh` + `setup-arc.sh` (~8–12 min total)
- Physical hardware path: K3s validation + `setup-arc.sh` (~5 min)
- Verification step (`verify-deployment.sh`) with expected output
- Link to troubleshooting guide if verification fails

**Rationale:** Presenters need to know exactly what to do *before* they go on stage. Splitting paths by time and prerequisites makes it clear which one applies to their situation. "15 minutes before" sets expectation for when to start. Expected verification output prevents presenters from going live with a broken setup.

#### docs/architecture.md

**Added:** Parenthetical note in the "On-Prem Side" component table, clarifying Azure VM simulation.

**Content:**
```
> In a live demo environment, an Azure Linux VM (Standard_B2s) simulates 
> the on-premises cluster. The Arc architecture and GitOps flow are identical 
> regardless of whether the K3s node runs on physical hardware, a self-managed VM, 
> or an Azure VM.
```

**Rationale:** Architecture docs are read by technically curious audience members and future maintainers. The note explains that the "on-prem" infrastructure is abstraction — what matters is the Arc + GitOps pattern, not whether bits run on physical servers. Keeps architecture docs focused (no new section, just clarification).

#### docs/troubleshooting.md

**Added:** "Azure VM Path Issues" section as the first troubleshooting category, before "Flux Not Reconciling."

**Scenarios covered:**
1. **SSH connection refused** — VM still initializing. Fix: wait 60s, retry.
2. **kubectl connection refused on 6443** — NSG rule not applied yet. Fix: wait 30s, verify NSG rule.
3. **K3s install error from vm run-command** — No internet access. Fix: verify public IP, check NSG outbound rules, retry.

**Rationale:** These are the most likely failure modes when using the Azure VM path. Covering them upfront saves presenters 10+ minutes of debugging. Each scenario includes diagnosis steps and exact fix steps — no guessing.

### Writing Style Maintained

- **Clear, imperative:** "Do X, then Y" — not explanatory prose
- **Audience-aware:** Presenters want speed. Users without hardware want reassurance.
- **Example commands:** Bash snippets are copy-pasteable (with placeholders for resource names)
- **Recovery mindset:** Every step includes "if it goes wrong" paths

### Impact

- ✅ New presenters can provision and run a demo in ~15 minutes (setup) + ~7 minutes (demo) without owning physical hardware
- ✅ Existing presenters with hardware can still use their setup (no breaking changes)
- ✅ Troubleshooting guide is now predictive — it covers known failure modes with quick fixes
- ✅ Architecture story is unchanged (on-prem is just a K3s node wherever it runs)
- ✅ Cost is transparent ($0.10/hr) and cleanup is one command
