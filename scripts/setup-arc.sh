#!/usr/bin/env bash
# =============================================================================
# setup-arc.sh — Azure Arc cluster onboarding + Flux GitOps configuration
#
# Purpose: Connect the K3s cluster to Azure Arc, install the Flux extension,
#          and create the GitOps configuration that points at this repo's
#          gitops/ path. Run this once after setup-cluster.sh succeeds.
#
# Required environment variables (set before running):
#   RESOURCE_GROUP   — Azure resource group name  (e.g. "rg-arc-demo")
#   CLUSTER_NAME     — Arc connected cluster name  (e.g. "arc-demo-cluster")
#   LOCATION         — Azure region               (e.g. "eastus")
#   REPO_URL         — GitHub repo HTTPS URL       (e.g. "https://github.com/org/demo-v1")
#
# Why env vars instead of hardcoded values: keeps this script reusable across
# environments (presenter's laptop, CI, staging) without editing the file. Also
# prevents accidental commits of org-specific values.
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
: "${LOCATION:?'LOCATION is not set. Export it before running this script.'}"
: "${REPO_URL:?'REPO_URL is not set. Export it before running this script.'}"

info "  RESOURCE_GROUP : ${RESOURCE_GROUP}"
info "  CLUSTER_NAME   : ${CLUSTER_NAME}"
info "  LOCATION       : ${LOCATION}"
info "  REPO_URL       : ${REPO_URL}"

# ─── Step 2: Check prerequisites ─────────────────────────────────────────────
# All tools must be present before we start making Azure API calls.
#
# NOTE — if kubectl was configured via provision-demo-vm.sh, the kubeconfig is
# at ~/.kube/arc-demo-config. Export it before running this script:
#   export KUBECONFIG=~/.kube/arc-demo-config
# If kubectl is already configured (e.g. from setup-cluster.sh on a local machine),
# no action is needed — this script works with any valid KUBECONFIG.
info "Checking prerequisites..."

check_tool() {
  local tool="$1"
  if ! command -v "${tool}" >/dev/null 2>&1; then
    error "Required tool '${tool}' not found in PATH. Please install it and re-run."
  fi
  info "  ✓ ${tool}"
}

check_tool az
check_tool kubectl

# Verify az CLI extensions are installed — these provide the connectedk8s and
# k8s-configuration commands used later in this script.
info "Checking required Azure CLI extensions..."

check_az_extension() {
  local ext="$1"
  if ! az extension show --name "${ext}" &>/dev/null; then
    info "  Extension '${ext}' not found — installing..."
    az extension add --name "${ext}" --yes
  fi
  info "  ✓ az extension: ${ext}"
}

check_az_extension "connectedk8s"
check_az_extension "k8s-configuration"
check_az_extension "k8s-extension"

# Verify we have an active az login session
info "Verifying Azure login..."
az account show --output none || error "Not logged in to Azure. Run: az login"
info "  ✓ Azure login active: $(az account show --query 'name' -o tsv)"

# Verify kubectl can reach the local K3s cluster
info "Verifying kubectl connectivity..."
kubectl get nodes --no-headers | grep -q "Ready" || \
  error "No Ready nodes found. Is K3s running? Run: sudo systemctl status k3s"
info "  ✓ kubectl connected — $(kubectl get nodes --no-headers | wc -l | tr -d ' ') node(s) Ready"

# ─── Step 3: Ensure the resource group exists ────────────────────────────────
# Idempotent: if the group already exists az group create is a no-op.
info "Ensuring resource group '${RESOURCE_GROUP}' exists in '${LOCATION}'..."
az group create \
  --name "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --output none
info "  ✓ Resource group ready."

# ─── Step 4: Connect the cluster to Azure Arc ────────────────────────────────
# az connectedk8s connect installs the Arc agent pods into the 'azure-arc'
# namespace on the local cluster and registers the cluster as an Azure resource.
# All communication is outbound HTTPS — no inbound firewall rules needed.
info "Connecting cluster '${CLUSTER_NAME}' to Azure Arc..."
az connectedk8s connect \
  --name "${CLUSTER_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --location "${LOCATION}"

info "  ✓ Cluster connected to Arc."

# Confirm Arc agent pods are running before proceeding with the extension install
info "Waiting for Arc agents to become ready..."
kubectl wait pod \
  --namespace azure-arc \
  --for=condition=Ready \
  --all \
  --timeout=300s
info "  ✓ Arc agent pods are Ready."

# ─── Step 5: Install the Flux v2 extension via Arc ───────────────────────────
# This installs Flux controllers on the cluster as an Arc-managed extension.
# Using Arc to install Flux (rather than raw flux bootstrap) keeps everything
# visible and manageable through the Azure Portal and az CLI — which is the
# whole point of the demo.
info "Installing Flux v2 extension on cluster..."
az k8s-extension create \
  --name "flux-gitops" \
  --cluster-name "${CLUSTER_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --cluster-type connectedClusters \
  --extension-type microsoft.flux \
  --scope cluster \
  --release-train stable \
  --auto-upgrade-minor-version true

info "  ✓ Flux extension installed."

# ─── Step 6: Create the Flux GitOps configuration ────────────────────────────
# This creates an Azure resource (Microsoft.KubernetesConfiguration/fluxConfigurations)
# that tells Flux what to watch:
#   - Source: this GitHub repo, main branch
#   - Path: ./gitops  (Flux ignores src/ and other app code)
#   - Interval: 1 minute (good demo pacing — changes show up within ~90 seconds)
#   - Prune: true — removing a manifest from the repo removes the resource from
#     the cluster (clean demo resets)
info "Creating Flux GitOps configuration 'demo-app-config'..."
az k8s-configuration flux create \
  --resource-group "${RESOURCE_GROUP}" \
  --cluster-name "${CLUSTER_NAME}" \
  --cluster-type connectedClusters \
  --name "demo-app-config" \
  --namespace flux-system \
  --scope cluster \
  --url "${REPO_URL}" \
  --branch master \
  --kustomization name=demo-app path=./gitops interval=1m prune=true

info "  ✓ Flux GitOps configuration created."

# ─── Step 7: Print summary and portal URL ────────────────────────────────────
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
PORTAL_URL="https://portal.azure.com/#resource/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Kubernetes/connectedClusters/${CLUSTER_NAME}/overview"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         Azure Arc onboarding complete!                          ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Resource Group : ${RESOURCE_GROUP}"
echo "  Cluster Name   : ${CLUSTER_NAME}"
echo "  Flux Config    : demo-app-config (watching ${REPO_URL}/gitops)"
echo ""
echo "  View in Azure Portal:"
echo "  ${PORTAL_URL}"
echo ""
echo "Next steps:"
echo "  1. Open the portal URL above and confirm cluster status is 'Connected'."
echo "  2. Push your first commit to main — the CI pipeline will build the image"
echo "     and Flux will deploy it within ~2 minutes."
echo ""
