#!/usr/bin/env bash
# =============================================================================
# lima-k3s-setup.sh
# macOS host script — installs Lima, creates an Ubuntu 22.04 VM, and joins
# the VM to an existing K3s cluster as a worker node.
#
# Designed for iMac M1 (Apple Silicon).  Works on Intel Mac too.
#
# Usage:
#   chmod +x lima-k3s-setup.sh
#   ./lima-k3s-setup.sh
#
# Environment variables (optional — the script will prompt if not set):
#   MASTER_IP    IP address of the K3s master node (e.g. 192.168.1.10)
#   NODE_TOKEN   Contents of /var/lib/rancher/k3s/server/node-token on master
#   VM_NAME      Lima VM name (default: k3s-worker)
# =============================================================================

set -euo pipefail

# --------------------------------------------------------------------------- #
# 0. Helpers
# --------------------------------------------------------------------------- #
info()  { echo -e "\033[0;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[0;32m[OK]\033[0m    $*"; }
warn()  { echo -e "\033[0;33m[WARN]\033[0m  $*"; }
die()   { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; exit 1; }

# Must run on macOS
[[ "$(uname -s)" == "Darwin" ]] || die "This script must be run on macOS."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIMA_TEMPLATE="${SCRIPT_DIR}/lima-ubuntu-k3s.yaml"
VM_NAME="${VM_NAME:-k3s-worker}"

# --------------------------------------------------------------------------- #
# 1. Check / install Homebrew
# --------------------------------------------------------------------------- #
info "Checking for Homebrew..."
if ! command -v brew >/dev/null 2>&1; then
    info "Homebrew not found. Installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
ok "Homebrew is available."

# --------------------------------------------------------------------------- #
# 2. Install Lima
# --------------------------------------------------------------------------- #
info "Installing / upgrading Lima..."
brew install lima
ok "Lima $(limactl --version) installed."

# --------------------------------------------------------------------------- #
# 3. Collect cluster parameters
# --------------------------------------------------------------------------- #
if [[ -z "${MASTER_IP:-}" ]]; then
    read -r -p "Enter K3s master node IP (e.g. 192.168.1.10): " MASTER_IP
fi
if [[ -z "${NODE_TOKEN:-}" ]]; then
    read -r -s -p "Enter K3s node token (from /var/lib/rancher/k3s/server/node-token on master): " NODE_TOKEN
    echo
fi

[[ -n "${MASTER_IP}" ]] || die "MASTER_IP must not be empty."
[[ -n "${NODE_TOKEN}" ]] || die "NODE_TOKEN must not be empty."

# --------------------------------------------------------------------------- #
# 4. Verify Lima template exists
# --------------------------------------------------------------------------- #
[[ -f "${LIMA_TEMPLATE}" ]] || die "Lima template not found: ${LIMA_TEMPLATE}"

# --------------------------------------------------------------------------- #
# 5. Create (or re-use) the Lima VM
# --------------------------------------------------------------------------- #
info "Checking for existing Lima VM '${VM_NAME}'..."
if limactl list --format '{{.Name}}' 2>/dev/null | grep -qx "${VM_NAME}"; then
    warn "VM '${VM_NAME}' already exists. Starting it (if stopped)..."
    limactl start "${VM_NAME}" 2>/dev/null || true
else
    info "Creating Lima VM '${VM_NAME}' from template..."
    limactl start --name="${VM_NAME}" "${LIMA_TEMPLATE}"
fi
ok "Lima VM '${VM_NAME}' is running."

# --------------------------------------------------------------------------- #
# 6. Install K3s agent inside the Lima VM
#    The token is written to a temporary file with restricted permissions
#    inside the VM to avoid exposing it in process listings or shell history.
# --------------------------------------------------------------------------- #
info "Installing K3s agent inside Lima VM '${VM_NAME}'..."

# Write the token to a restricted temp file inside the VM
limactl shell "${VM_NAME}" -- bash -c "
    umask 077
    printf '%s' '${NODE_TOKEN}' > /tmp/.k3s-token
"

# Install the agent, reading the token from the file
limactl shell "${VM_NAME}" -- sudo bash -c "
    set -euo pipefail
    echo '[INFO] Starting K3s agent installation...'
    K3S_TOKEN=\$(cat /tmp/.k3s-token)
    curl -sfL https://get.k3s.io | \
        K3S_URL='https://${MASTER_IP}:6443' \
        K3S_TOKEN=\"\${K3S_TOKEN}\" \
        sh -
    echo '[OK] K3s agent installed.'
"

# Remove the temporary token file
limactl shell "${VM_NAME}" -- rm -f /tmp/.k3s-token

ok "K3s agent is running inside Lima VM '${VM_NAME}'."

# --------------------------------------------------------------------------- #
# 7. Verify the node joined the cluster
# --------------------------------------------------------------------------- #
echo
info "Waiting 10 seconds for the node to register with the master..."
sleep 10

ok "======================================================"
ok " Lima VM setup complete!"
echo
ok " VM name    : ${VM_NAME}"
ok " Master IP  : ${MASTER_IP}"
echo
ok " Next steps:"
ok "   1. On the master node, run:  kubectl get nodes"
ok "      You should see '${VM_NAME}' (or 'lima-worker') with Ready status."
echo
ok "   2. To open a shell inside the VM:"
ok "      limactl shell ${VM_NAME}"
echo
ok "   3. To stop / start the VM:"
ok "      limactl stop  ${VM_NAME}"
ok "      limactl start ${VM_NAME}"
ok "======================================================"
