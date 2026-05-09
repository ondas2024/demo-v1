#!/usr/bin/env bash
# =============================================================================
# teardown.sh — Reverse of setup-arc.sh
#
# Purpose: Cleanly remove all Azure Arc and Flux resources, then optionally
#          delete the resource group. Run this after a demo to avoid leaving
#          Azure resources running (and billing) or to reset for another run.
#
# Reproducibility is the demo. If you can't tear it down cleanly and rebuild
# from code, it isn't really working.
#
# Required environment variables (same as setup-arc.sh):
#   RESOURCE_GROUP   — Azure resource group name  (e.g. "rg-arc-demo")
#   CLUSTER_NAME     — Arc connected cluster name  (e.g. "arc-demo-cluster")
#
# Optional:
#   SKIP_RG_DELETE   — Set to "true" to skip resource group deletion prompt
#                      (useful in CI cleanup jobs where you want full teardown
#                      without interactive prompts)
# =============================================================================

set -euo pipefail

# ─── Colour helpers ──────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ─── Step 1: Validate required environment variables ─────────────────────────
info "Validating required environment variables..."

: "${RESOURCE_GROUP:?'RESOURCE_GROUP is not set. Export it before running this script.'}"
: "${CLUSTER_NAME:?'CLUSTER_NAME is not set. Export it before running this script.'}"

info "  RESOURCE_GROUP : ${RESOURCE_GROUP}"
info "  CLUSTER_NAME   : ${CLUSTER_NAME}"

# ─── Step 2: Check prerequisites ─────────────────────────────────────────────
info "Checking prerequisites..."
command -v az >/dev/null 2>&1 || error "Azure CLI (az) not found."
az account show --output none    || error "Not logged in to Azure. Run: az login"
info "  ✓ Azure CLI ready — $(az account show --query 'name' -o tsv)"

# ─── Step 3: Remove the Flux GitOps configuration ────────────────────────────
# Removing the configuration resource from Azure tells Flux to stop reconciling.
# With prune=true this also removes all Flux-managed resources from the cluster
# (namespace, deployment, service) — a clean slate for the next demo run.
info "Removing Flux GitOps configuration 'demo-app-config'..."
if az k8s-configuration flux show \
     --resource-group "${RESOURCE_GROUP}" \
     --cluster-name "${CLUSTER_NAME}" \
     --cluster-type connectedClusters \
     --name "demo-app-config" \
     --output none 2>/dev/null; then
  az k8s-configuration flux delete \
    --resource-group "${RESOURCE_GROUP}" \
    --cluster-name "${CLUSTER_NAME}" \
    --cluster-type connectedClusters \
    --name "demo-app-config" \
    --yes
  info "  ✓ Flux configuration removed."
else
  warn "  Flux configuration 'demo-app-config' not found — skipping."
fi

# ─── Step 4: Remove the Flux Arc extension ───────────────────────────────────
# This uninstalls the Flux controllers from the cluster. Must happen after the
# configuration is removed to avoid orphaned Flux resources.
info "Removing Flux Arc extension 'flux-gitops'..."
if az k8s-extension show \
     --resource-group "${RESOURCE_GROUP}" \
     --cluster-name "${CLUSTER_NAME}" \
     --cluster-type connectedClusters \
     --name "flux-gitops" \
     --output none 2>/dev/null; then
  az k8s-extension delete \
    --resource-group "${RESOURCE_GROUP}" \
    --cluster-name "${CLUSTER_NAME}" \
    --cluster-type connectedClusters \
    --name "flux-gitops" \
    --yes
  info "  ✓ Flux extension removed."
else
  warn "  Flux extension 'flux-gitops' not found — skipping."
fi

# ─── Step 5: Disconnect the cluster from Azure Arc ───────────────────────────
# az connectedk8s delete removes the Arc agent pods from the cluster's
# azure-arc namespace and deregisters the cluster as an Azure resource.
info "Disconnecting cluster '${CLUSTER_NAME}' from Azure Arc..."
if az connectedk8s show \
     --resource-group "${RESOURCE_GROUP}" \
     --name "${CLUSTER_NAME}" \
     --output none 2>/dev/null; then
  az connectedk8s delete \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${CLUSTER_NAME}" \
    --yes
  info "  ✓ Cluster disconnected from Arc."
else
  warn "  Connected cluster '${CLUSTER_NAME}' not found — skipping."
fi

# ─── Step 6: Delete the resource group (with confirmation) ───────────────────
# This is the destructive step. We prompt before proceeding unless SKIP_RG_DELETE
# is set — useful for CI/scripted teardowns where interaction is not possible.
echo ""
warn "The next step will DELETE resource group '${RESOURCE_GROUP}' and all resources in it."
warn "This cannot be undone."
echo ""

SKIP_RG_DELETE="${SKIP_RG_DELETE:-false}"

if [[ "${SKIP_RG_DELETE}" == "true" ]]; then
  info "SKIP_RG_DELETE=true — skipping resource group deletion."
else
  read -r -p "  Type 'yes' to delete resource group '${RESOURCE_GROUP}': " CONFIRM
  if [[ "${CONFIRM}" != "yes" ]]; then
    info "Resource group deletion cancelled. Azure resources in '${RESOURCE_GROUP}' were NOT deleted."
    echo ""
    info "Teardown complete (partial — resource group retained)."
    exit 0
  fi

  info "Deleting resource group '${RESOURCE_GROUP}'..."
  az group delete \
    --name "${RESOURCE_GROUP}" \
    --yes \
    --no-wait

  # --no-wait returns immediately; deletion runs asynchronously in Azure.
  # For demo teardown this is fine — we don't need to wait for it.
  info "  ✓ Resource group deletion initiated (runs asynchronously in Azure)."
fi

# ─── Step 7: Summary ─────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║            Teardown complete!                           ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  What was removed:"
echo "    ✓ Flux GitOps configuration (demo-app-config)"
echo "    ✓ Flux Arc extension (flux-gitops)"
echo "    ✓ Arc connected cluster (${CLUSTER_NAME})"
if [[ "${SKIP_RG_DELETE}" != "true" ]] && [[ "${CONFIRM:-}" == "yes" ]]; then
  echo "    ✓ Resource group (${RESOURCE_GROUP}) — deletion in progress"
fi
echo ""
echo "  K3s is still running on this machine."
echo "  To remove K3s: sudo /usr/local/bin/k3s-uninstall.sh"
echo ""
echo "  If K3s was running on an Azure VM provisioned via provision-demo-vm.sh,"
echo "  the VM is part of resource group ${RESOURCE_GROUP} and was already deleted"
echo "  above. No separate VM cleanup is needed."
echo ""
echo "  To rebuild from scratch:"
echo "    bash scripts/setup-cluster.sh"
echo "    bash scripts/setup-arc.sh"
echo ""
