#!/usr/bin/env bash
# =============================================================================
# tailscale-server-setup.sh
# Installs and configures Tailscale on a Linux server (Ubuntu 22.04).
#
# Run this on every server node that should be reachable from outside
# the home network (e.g., N100 master, MacBook Pro 2014 worker).
#
# Usage:
#   chmod +x tailscale-server-setup.sh
#   sudo ./tailscale-server-setup.sh
#
# After running, authenticate by opening the URL printed on screen.
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
# 1. Install Tailscale
# --------------------------------------------------------------------------- #
info "Installing Tailscale..."
# NOTE: The official Tailscale install script is fetched from tailscale.com and
# piped directly to sh. This is Tailscale's documented installation method.
# If you prefer to review the script before running it, download it first:
#   curl -fsSL https://tailscale.com/install.sh -o /tmp/tailscale-install.sh
#   less /tmp/tailscale-install.sh
#   sudo sh /tmp/tailscale-install.sh
curl -fsSL https://tailscale.com/install.sh | sh
ok "Tailscale installed: $(tailscale --version | head -1)"

# --------------------------------------------------------------------------- #
# 2. Enable and start the tailscaled daemon
# --------------------------------------------------------------------------- #
info "Enabling tailscaled service..."
systemctl enable --now tailscaled
ok "tailscaled is running."

# --------------------------------------------------------------------------- #
# 3. Bring up Tailscale and authenticate
#    --ssh enables Tailscale SSH so you can connect without managing SSH keys
#    separately on each server.
# --------------------------------------------------------------------------- #
info "Bringing up Tailscale (SSH enabled)..."
tailscale up --ssh

ok "======================================================"
ok " Tailscale setup complete!"
echo
ok " This node is now part of your Tailscale network."
ok " Its Tailscale IP is:"
tailscale ip -4 2>/dev/null || warn "Could not retrieve Tailscale IP yet."
echo
ok " Next steps:"
ok "   1. On your MacBook Air, run the remote setup script:"
ok "      ./scripts/setup/macbook-air-remote-setup.sh"
ok "   2. Verify connectivity from MacBook Air:"
ok "      ssh <user>@<tailscale-ip-of-this-server>"
ok "   3. Copy the K3s kubeconfig to your MacBook Air:"
ok "      scp <user>@<n100-tailscale-ip>:/etc/rancher/k3s/k3s.yaml ~/.kube/config"
ok "      Then update 'server:' in ~/.kube/config to use the Tailscale IP."
ok "======================================================"
