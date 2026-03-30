#!/usr/bin/env bash
# =============================================================================
# macbook-air-remote-setup.sh
# Sets up a MacBook Air as a remote management workstation for the
# Hybrid K3s Cluster.
#
# What this script does:
#   1. Installs Homebrew (if missing)
#   2. Installs required CLI tools: kubectl, tailscale, helm (optional)
#   3. Generates an SSH key pair (if none exists) and prints the public key
#   4. Writes a convenient ~/.ssh/config entry for each server
#   5. Fetches the K3s kubeconfig from the master node and patches the
#      server address to use the Tailscale IP
#
# Usage:
#   chmod +x macbook-air-remote-setup.sh
#   ./macbook-air-remote-setup.sh
#
# Environment variables (optional — the script will prompt if not set):
#   MASTER_TAILSCALE_IP   Tailscale IP of the N100 master node
#   MASTER_USER           SSH username on the master node
# =============================================================================

set -euo pipefail

# --------------------------------------------------------------------------- #
# 0. Helpers
# --------------------------------------------------------------------------- #
info()  { echo -e "\033[0;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[0;32m[OK]\033[0m    $*"; }
warn()  { echo -e "\033[0;33m[WARN]\033[0m  $*"; }
die()   { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "This script must be run on macOS."

# --------------------------------------------------------------------------- #
# 1. Homebrew
# --------------------------------------------------------------------------- #
info "Checking for Homebrew..."
if ! command -v brew >/dev/null 2>&1; then
    info "Installing Homebrew..."
    # NOTE: The official Homebrew install script is fetched from GitHub and
    # piped directly to bash. This is Homebrew's documented installation method.
    # To review the script before running it:
    #   curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o /tmp/homebrew-install.sh
    #   less /tmp/homebrew-install.sh
    #   bash /tmp/homebrew-install.sh
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Add Homebrew to PATH for Apple Silicon Macs
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
fi
ok "Homebrew $(brew --version | head -1) is available."

# --------------------------------------------------------------------------- #
# 2. Install CLI tools
# --------------------------------------------------------------------------- #
info "Installing kubectl..."
if ! command -v kubectl >/dev/null 2>&1; then
    brew install kubectl
fi
ok "kubectl $(kubectl version --client --short 2>/dev/null | head -1) installed."

info "Installing Tailscale..."
if ! command -v tailscale >/dev/null 2>&1; then
    brew install tailscale
fi
ok "Tailscale installed."

info "Installing helm (optional, for chart management)..."
if ! command -v helm >/dev/null 2>&1; then
    brew install helm
fi
ok "helm $(helm version --short 2>/dev/null) installed."

# --------------------------------------------------------------------------- #
# 3. Tailscale: join the network
# --------------------------------------------------------------------------- #
info "Starting Tailscale on this MacBook Air..."
# tailscale on macOS needs the app; open it if the CLI is not connected.
if ! tailscale status >/dev/null 2>&1; then
    warn "Tailscale is not running or not authenticated."
    warn "Please open the Tailscale app and sign in, then re-run this script."
    warn "  brew install --cask tailscale   # GUI app (recommended for macOS)"
    warn "  open /Applications/Tailscale.app"
else
    ok "Tailscale is running. This machine's Tailscale IP:"
    tailscale ip -4 2>/dev/null || true
fi

# --------------------------------------------------------------------------- #
# 4. SSH key generation
# --------------------------------------------------------------------------- #
SSH_KEY="${HOME}/.ssh/id_ed25519_k3s_cluster"
if [[ ! -f "${SSH_KEY}" ]]; then
    info "Generating SSH key pair for cluster access..."
    # NOTE: The key is generated without a passphrase for convenience.
    # For better security, remove -N "" so ssh-keygen prompts you to set a
    # passphrase. A passphrase-protected key requires entry on each use
    # (or use ssh-agent to cache it).
    ssh-keygen -t ed25519 -C "macbook-air-remote-mgmt" -f "${SSH_KEY}" -N ""
    ok "SSH key created: ${SSH_KEY}"
else
    ok "SSH key already exists: ${SSH_KEY}"
fi

echo
info ">>> Public key to copy to each server (ssh-copy-id or authorized_keys):"
echo "--------------------------------------------------------------------"
cat "${SSH_KEY}.pub"
echo "--------------------------------------------------------------------"
echo
info "To copy the key to a server:"
info "  ssh-copy-id -i ${SSH_KEY}.pub <user>@<tailscale-ip>"
echo

# --------------------------------------------------------------------------- #
# 5. Collect master node details
# --------------------------------------------------------------------------- #
if [[ -z "${MASTER_TAILSCALE_IP:-}" ]]; then
    read -r -p "Enter the Tailscale IP of the N100 master node: " MASTER_TAILSCALE_IP
fi
if [[ -z "${MASTER_USER:-}" ]]; then
    read -r -p "Enter your SSH username on the master node: " MASTER_USER
fi

[[ -n "${MASTER_TAILSCALE_IP}" ]] || die "MASTER_TAILSCALE_IP must not be empty."
[[ -n "${MASTER_USER}" ]]         || die "MASTER_USER must not be empty."

# --------------------------------------------------------------------------- #
# 6. SSH config entry
# --------------------------------------------------------------------------- #
SSH_CONFIG="${HOME}/.ssh/config"
touch "${SSH_CONFIG}"
chmod 600 "${SSH_CONFIG}"

HOST_BLOCK="Host n100-master
    HostName ${MASTER_TAILSCALE_IP}
    User ${MASTER_USER}
    IdentityFile ${SSH_KEY}
    ServerAliveInterval 60
    ServerAliveCountMax 3"

if ! grep -q "Host n100-master" "${SSH_CONFIG}" 2>/dev/null; then
    info "Adding n100-master entry to ${SSH_CONFIG}..."
    {
        echo ""
        echo "${HOST_BLOCK}"
    } >> "${SSH_CONFIG}"
    ok "SSH config updated."
else
    warn "n100-master entry already exists in ${SSH_CONFIG}. Skipping."
fi

# --------------------------------------------------------------------------- #
# 7. Fetch kubeconfig from master and patch the server address
# --------------------------------------------------------------------------- #
KUBECONFIG_DIR="${HOME}/.kube"
KUBECONFIG_FILE="${KUBECONFIG_DIR}/config"
mkdir -p "${KUBECONFIG_DIR}"
chmod 700 "${KUBECONFIG_DIR}"

info "Fetching kubeconfig from ${MASTER_USER}@${MASTER_TAILSCALE_IP}..."
info "(You may be prompted for the SSH key passphrase or server password.)"

# Fetch the raw kubeconfig.
# NOTE: StrictHostKeyChecking=accept-new trusts new host keys automatically
# but will reject changed keys (protecting against most MITM scenarios).
# For maximum security, omit this option and verify the host fingerprint
# interactively on the first connection.
REMOTE_KUBECONFIG=$(ssh \
    -i "${SSH_KEY}" \
    -o StrictHostKeyChecking=accept-new \
    "${MASTER_USER}@${MASTER_TAILSCALE_IP}" \
    "sudo cat /etc/rancher/k3s/k3s.yaml" 2>/dev/null) || {
    warn "Could not fetch kubeconfig automatically."
    warn "Run manually after this script:"
    warn "  ssh ${MASTER_USER}@${MASTER_TAILSCALE_IP} 'sudo cat /etc/rancher/k3s/k3s.yaml' > ${KUBECONFIG_FILE}"
    warn "  sed -i '' 's|https://127.0.0.1:6443|https://${MASTER_TAILSCALE_IP}:6443|g' ${KUBECONFIG_FILE}"
    warn "  chmod 600 ${KUBECONFIG_FILE}"
    REMOTE_KUBECONFIG=""
}

if [[ -n "${REMOTE_KUBECONFIG}" ]]; then
    # Replace the loopback address with the Tailscale IP of the master
    PATCHED=$(echo "${REMOTE_KUBECONFIG}" \
        | sed "s|https://127.0.0.1:6443|https://${MASTER_TAILSCALE_IP}:6443|g" \
        | sed "s|https://localhost:6443|https://${MASTER_TAILSCALE_IP}:6443|g")

    if [[ -f "${KUBECONFIG_FILE}" ]]; then
        warn "~/.kube/config already exists. Backing up to ~/.kube/config.bak..."
        cp "${KUBECONFIG_FILE}" "${KUBECONFIG_FILE}.bak"
    fi

    echo "${PATCHED}" > "${KUBECONFIG_FILE}"
    chmod 600 "${KUBECONFIG_FILE}"
    ok "kubeconfig saved to ${KUBECONFIG_FILE} (server: https://${MASTER_TAILSCALE_IP}:6443)"
fi

# --------------------------------------------------------------------------- #
# 8. Verify kubectl access
# --------------------------------------------------------------------------- #
if [[ -f "${KUBECONFIG_FILE}" ]]; then
    info "Testing kubectl connectivity..."
    if kubectl get nodes --request-timeout=10s 2>/dev/null; then
        ok "kubectl is working! Cluster nodes listed above."
    else
        warn "kubectl could not reach the cluster yet."
        warn "Make sure Tailscale is connected and the master node is running."
    fi
fi

# --------------------------------------------------------------------------- #
# 9. Done
# --------------------------------------------------------------------------- #
echo
ok "======================================================"
ok " MacBook Air remote management setup complete!"
echo
ok " Quick reference:"
ok "   SSH to master:   ssh n100-master"
ok "   List nodes:      kubectl get nodes"
ok "   All namespaces:  kubectl get pods -A"
ok "   Cluster info:    kubectl cluster-info"
echo
ok " To add worker node SSH access, append entries to ~/.ssh/config:"
ok "   Host mbp-2014-worker"
ok "       HostName <mbp2014-tailscale-ip>"
ok "       User <username>"
ok "       IdentityFile ${SSH_KEY}"
ok "======================================================"
