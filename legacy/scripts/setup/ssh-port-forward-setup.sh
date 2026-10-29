#!/usr/bin/env bash
# =============================================================================
# ssh-port-forward-setup.sh
# Hardens the SSH server on an Ubuntu node for remote management via
# static IP + router port forwarding (no VPN required).
#
# Run this on every server node that should be reachable from outside
# the home network (e.g., N100 master, MacBook Pro 2014 worker).
#
# Prerequisites (done once on your router):
#   - Assign each server a static LAN IP (DHCP reservation or netplan).
#   - Add a port-forwarding rule per server:
#       External port 2210  →  192.168.x.10:22   (N100 master)
#       External port 2220  →  192.168.x.20:22   (MBP 2014 worker)
#
# Usage:
#   chmod +x ssh-port-forward-setup.sh
#   sudo ./ssh-port-forward-setup.sh
# =============================================================================

set -euo pipefail

# --------------------------------------------------------------------------- #
# 0. Helpers
# --------------------------------------------------------------------------- #
info()  { echo -e "\033[0;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[0;32m[OK]\033[0m    $*"; }
warn()  { echo -e "\033[0;33m[WARN]\033[0m  $*"; }
die()   { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || die "Run this script as root (sudo)."
[[ "$(uname -s)" == "Linux" ]] || die "This script is for Linux only."

# --------------------------------------------------------------------------- #
# 1. Ensure OpenSSH server is installed and running
# --------------------------------------------------------------------------- #
info "Installing OpenSSH server..."
apt-get update -y -qq
apt-get install -y openssh-server
systemctl enable ssh
systemctl start ssh
ok "SSH server is running."

# --------------------------------------------------------------------------- #
# 2. Harden sshd_config
#    - Disable password authentication (key-only)
#    - Disable root login
#    - Restrict to IPv4 (optional — remove AddressFamily line if IPv6 needed)
# --------------------------------------------------------------------------- #
SSHD_CONFIG="/etc/ssh/sshd_config"
info "Hardening SSH configuration in ${SSHD_CONFIG}..."

# Back up original config (only on first run)
if [[ ! -f "${SSHD_CONFIG}.bak" ]]; then
    cp "${SSHD_CONFIG}" "${SSHD_CONFIG}.bak"
    ok "Backed up original sshd_config to ${SSHD_CONFIG}.bak"
else
    info "Backup already exists at ${SSHD_CONFIG}.bak — skipping."
fi

# Apply settings idempotently using sed + append-if-missing pattern
_sshd_set() {
    local key="$1" value="$2"
    if grep -qE "^#?${key}" "${SSHD_CONFIG}"; then
        sed -i "s|^#\?${key}.*|${key} ${value}|" "${SSHD_CONFIG}"
    else
        echo "${key} ${value}" >> "${SSHD_CONFIG}"
    fi
}

_sshd_set "PasswordAuthentication"    "no"
_sshd_set "PermitRootLogin"           "no"
_sshd_set "PubkeyAuthentication"      "yes"
_sshd_set "AuthorizedKeysFile"        ".ssh/authorized_keys"
_sshd_set "X11Forwarding"             "no"
_sshd_set "PrintMotd"                 "no"
_sshd_set "AddressFamily"             "inet"

# Validate config before restarting
sshd -t || die "sshd config validation failed. Check ${SSHD_CONFIG}."
systemctl restart ssh
ok "SSH hardened: key-only auth, root login disabled."

# --------------------------------------------------------------------------- #
# 3. Configure UFW to allow SSH
# --------------------------------------------------------------------------- #
if command -v ufw >/dev/null 2>&1; then
    info "Configuring UFW to allow SSH (port 22)..."
    ufw allow OpenSSH
    ufw --force enable
    ok "UFW updated: SSH allowed."
else
    warn "ufw not found — skipping firewall configuration."
fi

# --------------------------------------------------------------------------- #
# 4. Install btop for system resource monitoring
# --------------------------------------------------------------------------- #
info "Installing btop..."
apt-get install -y btop
ok "btop installed: $(btop --version 2>/dev/null | head -1 || echo 'installed')"

# --------------------------------------------------------------------------- #
# 5. Print current static IP and next steps
# --------------------------------------------------------------------------- #
PRIMARY_IP=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' || true)
if [[ -z "${PRIMARY_IP}" ]]; then
    PRIMARY_IP=$(ip -4 addr show scope global 2>/dev/null | awk '/inet /{gsub(/\/.*/, "", $2); print $2; exit}' || echo "<unknown>")
fi

echo
ok "======================================================"
ok " SSH remote access setup complete!"
echo
ok " This server's LAN IP: ${PRIMARY_IP}"
echo
ok " Router port-forwarding required (do this on your router):"
ok "   Add a rule:  <external-port>  →  ${PRIMARY_IP}:22"
ok "   Example for N100 master:   external 2210 → ${PRIMARY_IP}:22"
ok "   Example for MBP worker:    external 2220 → ${PRIMARY_IP}:22"
echo
ok " From outside your home network, connect with:"
ok "   ssh -p <external-port> <user>@<your-public-ip>"
echo
ok " Next steps:"
ok "   1. Copy your public SSH key to this server:"
ok "      ssh-copy-id -i ~/.ssh/id_ed25519_k3s_cluster.pub <user>@${PRIMARY_IP}"
ok "   2. On your MacBook Air, run the remote setup script:"
ok "      ./scripts/setup/macbook-air-remote-setup.sh"
ok "   3. Copy the K3s kubeconfig to your MacBook Air:"
ok "      ssh <user>@<your-public-ip> -p <external-port> 'sudo cat /etc/rancher/k3s/k3s.yaml' \\"
ok "        | sed 's|https://127.0.0.1:6443|https://<your-public-ip>:6443|g' \\"
ok "        > ~/.kube/config"
ok "      chmod 600 ~/.kube/config"
ok "======================================================"
