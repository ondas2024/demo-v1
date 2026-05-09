# Naomi — History

## Session 2026-05-09: Azure VM Provisioning Path (naomi-1)

**Deliverables:**
- `scripts/provision-demo-vm.sh` — Full VM + K3s provisioning script
  - Creates Azure Linux VM (Standard_B2s, Ubuntu 22.04 LTS)
  - Installs K3s via `az vm run-command invoke`
  - Retrieves and patches kubeconfig to `~/.kube/arc-demo-config`
  - Idempotent: checks for existing VM before creation

- `scripts/setup-arc.sh` — Updated with KUBECONFIG guidance
  - Added Step 2 header note explaining KUBECONFIG export requirement

- `scripts/teardown.sh` — Updated with VM cleanup notes
  - Clarified that VM is deleted as part of resource group teardown

**Decisions Logged:**
- VM SKU selection: Standard_B2s
- Installation method: `az vm run-command invoke`
- Kubeconfig location: `~/.kube/arc-demo-config`
- VM cleanup: Implicit in resource group deletion

**Status:** Complete. Ready for commit.
