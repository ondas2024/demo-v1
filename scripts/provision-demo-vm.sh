#!/usr/bin/env bash
# =============================================================================
# provision-demo-vm.sh — Provision an Azure Linux VM to simulate "on-prem" K3s
#
# Purpose: Creates a Standard_D2s_v3 Ubuntu 22.04 VM in Azure, installs K3s on it
#          remotely via az vm run-command, and configures a local kubeconfig so
#          that setup-arc.sh can connect to the cluster without any manual SSH.
#
# Why an Azure VM instead of a local machine?
#   The Azure Arc demo needs a Kubernetes cluster that Arc can connect to.
#   Traditionally that means physical on-prem hardware. This script provisions a
#   lightweight Azure VM that plays the role of "on-prem" — same Arc experience,
#   no hardware required. The VM is in a separate resource group but is otherwise
#   just a Linux machine to Arc.
#
# Optional environment variables (defaults shown):
#   VM_NAME          — VM resource name           (default: "arc-demo-vm")
#   RESOURCE_GROUP   — Azure resource group name  (default: "rg-arc-demo")
#   LOCATION         — Azure region               (default: "eastus")
#
# No required variables — all have sensible defaults for the demo.
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

# ─── Configuration (all overridable via env vars) ────────────────────────────
VM_NAME="${VM_NAME:-arc-demo-vm}"
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-arc-demo}"
LOCATION="${LOCATION:-eastus}"
VM_IMAGE="Ubuntu2204"
VM_SIZE="${VM_SIZE:-Standard_D2s_v3}"
VM_ADMIN="azureuser"
KUBECONFIG_DEST="${HOME}/.kube/arc-demo-config"

info "Configuration:"
info "  VM_NAME        : ${VM_NAME}"
info "  RESOURCE_GROUP : ${RESOURCE_GROUP}"
info "  LOCATION       : ${LOCATION}"
info "  VM_SIZE        : ${VM_SIZE}"
info "  KUBECONFIG     : ${KUBECONFIG_DEST}"

# ─── Step 1: Check prerequisites ─────────────────────────────────────────────
# All tools must be present before we start making Azure API calls.
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
check_tool ssh
check_tool scp

# Verify we have an active az login session before doing any resource work.
info "Verifying Azure login..."
az account show --output none || error "Not logged in to Azure. Run: az login"
info "  ✓ Azure login active: $(az account show --query 'name' -o tsv)"

# ─── Step 2: Ensure the resource group exists ────────────────────────────────
# Idempotent: az group create is a no-op if the group already exists.
# We create the resource group here so that provision-demo-vm.sh is fully
# self-contained — the presenter doesn't need to run any prior script.
info "Ensuring resource group '${RESOURCE_GROUP}' exists in '${LOCATION}'..."
az group create \
  --name "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --output none
info "  ✓ Resource group ready."

# ─── Step 3: Create the VM (idempotent) ──────────────────────────────────────
# We check whether the VM already exists before creating it. This makes the
# script safe to re-run if it was interrupted after the VM was created but
# before K3s was installed.
info "Checking if VM '${VM_NAME}' already exists..."

if az vm show \
     --resource-group "${RESOURCE_GROUP}" \
     --name "${VM_NAME}" \
     --output none 2>/dev/null; then
  warn "  VM '${VM_NAME}' already exists — skipping creation."
else
  info "  VM not found — creating..."
  # --generate-ssh-keys uses ~/.ssh/id_rsa if it exists, or creates a new pair.
  # This avoids prompting the user for a password and keeps the setup one-command.
  # Ports opened here:
  #   22   — SSH (required for scp kubeconfig fetch later in this script)
  #   6443 — K3s API server (required for kubectl and Arc agent connectivity)
  #   30080 — NodePort for the demo app (matches service.yaml nodePort)
  az vm create \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${VM_NAME}" \
    --image "${VM_IMAGE}" \
    --size "${VM_SIZE}" \
    --admin-username "${VM_ADMIN}" \
    --generate-ssh-keys \
    --public-ip-sku Standard \
    --output none

  info "  ✓ VM created."

  # Open the required ports via the VM's Network Security Group.
  # We open them as separate rules so each has a clear priority and description.
  info "  Opening port 22 (SSH)..."
  az vm open-port \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${VM_NAME}" \
    --port 22 \
    --priority 900 \
    --output none

  info "  Opening port 6443 (K3s API server)..."
  az vm open-port \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${VM_NAME}" \
    --port 6443 \
    --priority 910 \
    --output none

  info "  Opening port 30080 (NodePort demo app)..."
  az vm open-port \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${VM_NAME}" \
    --port 30080 \
    --priority 920 \
    --output none

  info "  ✓ Ports 22, 6443, 30080 open."
fi

# ─── Step 4: Retrieve the VM's public IP ─────────────────────────────────────
# We need the IP for two things: patching the kubeconfig and printing the SSH
# command at the end. Querying it here means we always have the current value
# even if the VM was pre-existing from a previous run.
info "Retrieving VM public IP..."
VM_IP=$(az vm show \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${VM_NAME}" \
  --show-details \
  --query "publicIps" \
  --output tsv)

[[ -z "${VM_IP}" ]] && error "Could not retrieve public IP for VM '${VM_NAME}'. Is the VM running?"
info "  ✓ VM public IP: ${VM_IP}"

# ─── Step 5: Install K3s on the VM via az vm run-command ─────────────────────
# az vm run-command invoke executes a shell command on the VM over the Azure
# agent (not SSH). This means we don't need to wait for SSH to become fully
# available or manage known_hosts — Azure handles the channel.
#
# INSTALL_K3S_EXEC="--write-kubeconfig-mode 644" makes /etc/rancher/k3s/k3s.yaml
# world-readable so azureuser can scp it without sudo.
info "Installing K3s on the VM via run-command (this may take ~60 seconds)..."
az vm run-command invoke \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${VM_NAME}" \
  --command-id RunShellScript \
  --scripts "curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='--write-kubeconfig-mode 644 --tls-san ${VM_IP}' sh -" \
  --output none

info "  ✓ K3s installation command sent. Waiting 20 seconds for the node to initialise..."
# K3s starts its API server ~10-15 seconds after the install script exits.
# A brief sleep prevents the scp step from racing ahead before the kubeconfig
# file is written at /etc/rancher/k3s/k3s.yaml.
sleep 20

# ─── Step 6: Fetch the kubeconfig from the VM ────────────────────────────────
# K3s writes its kubeconfig to /etc/rancher/k3s/k3s.yaml. We scp it to the
# local machine so kubectl and setup-arc.sh can reach the cluster without
# needing the user to manually SSH in.
#
# -o StrictHostKeyChecking=no avoids an interactive prompt for a freshly
# provisioned VM whose host key hasn't been seen before. This is safe because
# we just created the VM and retrieved the IP from the Azure API — we know
# exactly which machine we're connecting to.
info "Ensuring ~/.kube/ directory exists..."
mkdir -p "${HOME}/.kube"

info "Fetching kubeconfig from VM via scp..."
scp -o StrictHostKeyChecking=no \
    "${VM_ADMIN}@${VM_IP}:/etc/rancher/k3s/k3s.yaml" \
    "${KUBECONFIG_DEST}"

info "  ✓ Kubeconfig saved to ${KUBECONFIG_DEST}"

# ─── Step 7: Patch the kubeconfig server address ─────────────────────────────
# K3s writes 127.0.0.1 as the server address because from the VM's perspective
# the API server is local. We need to replace it with the VM's public IP so
# that kubectl on our local machine can reach it across the internet.
info "Patching kubeconfig server address (127.0.0.1 → ${VM_IP})..."
sed -i "s/127.0.0.1/${VM_IP}/g" "${KUBECONFIG_DEST}"
info "  ✓ Kubeconfig server address updated to ${VM_IP}:6443"

# ─── Step 8: Verify kubectl connectivity ─────────────────────────────────────
# Export the kubeconfig for this shell session and confirm we can reach the
# cluster. If this fails, something went wrong with K3s, the port, or the IP.
info "Verifying kubectl connectivity to the K3s cluster..."
export KUBECONFIG="${KUBECONFIG_DEST}"

# Retry a few times — K3s may still be settling its API server.
MAX_RETRIES=6
RETRY_DELAY=10
for i in $(seq 1 ${MAX_RETRIES}); do
  if kubectl get nodes --no-headers 2>/dev/null | grep -q "Ready"; then
    info "  ✓ kubectl connected — cluster is Ready."
    kubectl get nodes -o wide
    break
  fi
  if [[ ${i} -eq ${MAX_RETRIES} ]]; then
    error "Cluster did not become Ready after $((MAX_RETRIES * RETRY_DELAY))s. Check: az vm run-command invoke --command-id RunShellScript --scripts 'sudo journalctl -u k3s -n 50'"
  fi
  warn "  Cluster not yet ready (attempt ${i}/${MAX_RETRIES}) — waiting ${RETRY_DELAY}s..."
  sleep ${RETRY_DELAY}
done

# ─── Step 9: Print summary and next steps ────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║       Demo VM + K3s cluster provisioned successfully!           ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Resource Group : ${RESOURCE_GROUP}"
echo "  VM Name        : ${VM_NAME}"
echo "  VM Public IP   : ${VM_IP}"
echo "  VM Size        : ${VM_SIZE} (Ubuntu 22.04 LTS)"
echo "  K3s kubeconfig : ${KUBECONFIG_DEST}"
echo ""
echo "  Open ports:"
echo "    22    — SSH"
echo "    6443  — K3s API server"
echo "    30080 — NodePort (demo app)"
echo ""
echo "  SSH into the VM:"
echo "    ssh ${VM_ADMIN}@${VM_IP}"
echo ""
echo "Next steps:"
echo ""
echo "  1. Export the kubeconfig in your shell:"
echo "       export KUBECONFIG=~/.kube/arc-demo-config"
echo ""
echo "  2. Run the Arc onboarding script:"
echo "       export RESOURCE_GROUP=\"${RESOURCE_GROUP}\""
echo "       export CLUSTER_NAME=\"arc-demo-cluster\""
echo "       export LOCATION=\"${LOCATION}\""
echo "       export REPO_URL=\"https://github.com/<your-org>/demo-v1\""
echo "       bash scripts/setup-arc.sh"
echo ""
echo "  To tear down everything (VM + Arc resources): bash scripts/teardown.sh"
echo "  Deleting resource group '${RESOURCE_GROUP}' also deletes this VM."
echo ""
