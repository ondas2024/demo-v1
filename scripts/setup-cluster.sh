#!/usr/bin/env bash
# =============================================================================
# setup-cluster.sh — K3s single-node cluster bootstrap
#
# Purpose: Install K3s on this machine and verify the cluster is ready before
#          running setup-arc.sh. This simulates the "on-prem" Kubernetes cluster
#          that Azure Arc will connect to.
#
# Run once on the Linux machine that will act as the on-prem cluster host.
# =============================================================================

set -euo pipefail

# ─── Colour helpers ──────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Colour

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ─── Step 1: Preflight checks ────────────────────────────────────────────────
info "Checking prerequisites..."

# K3s requires curl to download the installer
command -v curl >/dev/null 2>&1 || error "curl is required. Install it with: sudo apt-get install -y curl"

# Must be run as root or with sudo available for the K3s installer
if [[ $EUID -ne 0 ]]; then
  command -v sudo >/dev/null 2>&1 || error "This script must be run as root, or sudo must be available."
  SUDO="sudo"
else
  SUDO=""
fi

info "Preflight checks passed."

# ─── Step 2: Install K3s ─────────────────────────────────────────────────────
# Using the official K3s install script. Installs the K3s binary, systemd service,
# kubeconfig at /etc/rancher/k3s/k3s.yaml, and starts the cluster automatically.
#
# --write-kubeconfig-mode 644 makes the kubeconfig world-readable so non-root
# users (including the Arc setup script) can access the cluster without sudo.
info "Installing K3s..."
curl -sfL https://get.k3s.io | $SUDO INSTALL_K3S_EXEC="--write-kubeconfig-mode 644" sh -

info "K3s installation complete. Waiting for the node to become Ready..."

# ─── Step 3: Export kubeconfig to standard location ──────────────────────────
# K3s writes its kubeconfig to /etc/rancher/k3s/k3s.yaml. We copy it to the
# standard ~/.kube/config location so that kubectl, az connectedk8s, and other
# tools pick it up automatically without needing KUBECONFIG env var overrides.
KUBECONFIG_SRC="/etc/rancher/k3s/k3s.yaml"
KUBECONFIG_DEST="${HOME}/.kube/config"

mkdir -p "${HOME}/.kube"

# Use cp + chmod instead of a symlink so that tools that write to kubeconfig
# (e.g., merging contexts) don't accidentally clobber the K3s-owned file.
$SUDO cp "${KUBECONFIG_SRC}" "${KUBECONFIG_DEST}"
$SUDO chown "$(id -u):$(id -g)" "${KUBECONFIG_DEST}"
chmod 600 "${KUBECONFIG_DEST}"

info "Kubeconfig exported to ${KUBECONFIG_DEST}"

# Export for the remainder of this session (in case the shell doesn't reload)
export KUBECONFIG="${KUBECONFIG_DEST}"

# ─── Step 4: Verify the cluster is up ────────────────────────────────────────
# Poll kubectl get nodes until the node reaches Ready status. K3s is usually
# ready within 30 seconds; we give it up to 120 seconds before failing.
MAX_WAIT=120
WAITED=0
POLL=5

info "Waiting for node to reach Ready state (max ${MAX_WAIT}s)..."

until kubectl get nodes 2>/dev/null | grep -q " Ready"; do
  if [[ ${WAITED} -ge ${MAX_WAIT} ]]; then
    error "Node did not become Ready within ${MAX_WAIT} seconds. Check: sudo journalctl -u k3s -n 50"
  fi
  sleep ${POLL}
  WAITED=$((WAITED + POLL))
  info "  Still waiting... (${WAITED}s elapsed)"
done

echo ""
info "Cluster node status:"
kubectl get nodes -o wide
echo ""

info "System pods:"
kubectl get pods -n kube-system
echo ""

# ─── Step 5: Print next steps ────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           K3s cluster is up and ready!                  ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Next step: run the Arc onboarding script."
echo ""
echo "  export RESOURCE_GROUP=\"rg-arc-demo\""
echo "  export CLUSTER_NAME=\"arc-demo-cluster\""
echo "  export LOCATION=\"eastus\""
echo "  export REPO_URL=\"https://github.com/<your-org>/demo-v1\""
echo "  bash scripts/setup-arc.sh"
echo ""
