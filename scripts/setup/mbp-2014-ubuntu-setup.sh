#!/usr/bin/env bash
# =============================================================================
# mbp-2014-ubuntu-setup.sh
# Ubuntu 22.04 LTS setup script for a 2014 MacBook Pro (Intel)
#
# This script documents the exact steps used to configure a 10-year-old
# MacBook Pro as a K3s worker node — an upcycling project that turns
# end-of-life Apple hardware into a productive Kubernetes cluster member.
#
# Usage:
#   chmod +x mbp-2014-ubuntu-setup.sh
#   sudo ./mbp-2014-ubuntu-setup.sh
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

# --------------------------------------------------------------------------- #
# 1. System update
# --------------------------------------------------------------------------- #
info "Updating package lists and upgrading existing packages..."
apt-get update -y
apt-get upgrade -y
ok "System up to date."

# --------------------------------------------------------------------------- #
# 2. Install essential packages
# --------------------------------------------------------------------------- #
info "Installing essential packages..."
apt-get install -y \
    curl \
    wget \
    git \
    vim \
    htop \
    net-tools \
    openssh-server \
    ca-certificates \
    gnupg \
    lsb-release \
    apt-transport-https \
    software-properties-common
ok "Essential packages installed."

# --------------------------------------------------------------------------- #
# 3. MacBook Pro 2014 — Kernel 6.8 via HWE (required for BCM4360 Wi-Fi)
#    The default Ubuntu 22.04 kernel (5.15) fails to activate the Broadcom
#    BCM4360 Wi-Fi driver even after installation. Upgrading to kernel 6.8
#    via the HWE stack resolves this. A reboot into the new kernel is
#    required before the Broadcom driver will load successfully.
# --------------------------------------------------------------------------- #
CURRENT_KERNEL_MAJOR=$(uname -r | cut -d. -f1)
CURRENT_KERNEL_MINOR=$(uname -r | cut -d. -f2)

if (( CURRENT_KERNEL_MAJOR < 6 || (CURRENT_KERNEL_MAJOR == 6 && CURRENT_KERNEL_MINOR < 8) )); then
    info "Current kernel: $(uname -r). Installing kernel 6.8 via HWE stack..."
    apt-get install -y linux-generic-hwe-22.04
    ok "Kernel 6.8 (HWE) installed."
    warn "A reboot is required to boot into the new kernel before the Wi-Fi driver will work."
    warn "After rebooting, re-run this script to continue setup, or install the Wi-Fi driver manually:"
    warn "  sudo apt install -y bcmwl-kernel-source && sudo modprobe wl"
    warn "Rebooting in 10 seconds — press Ctrl+C to cancel."
    sleep 10
    reboot
else
    ok "Kernel $(uname -r) meets the 6.8+ requirement. Proceeding with Wi-Fi driver installation."
fi

# --------------------------------------------------------------------------- #
# 4. MacBook Pro 2014 — Broadcom Wi-Fi driver (BCM4360)
#    The 2014 MBP uses a Broadcom BCM4360 chip, which requires the
#    proprietary 'wl' driver. Kernel 6.8+ is required (see step 3 above).
# --------------------------------------------------------------------------- #
info "Installing Broadcom Wi-Fi driver for MacBook Pro 2014 (BCM4360)..."
apt-get install -y bcmwl-kernel-source
modprobe wl 2>/dev/null || warn "modprobe wl failed — may require a reboot."
ok "Broadcom Wi-Fi driver installed. A reboot may be required to activate it."

# --------------------------------------------------------------------------- #
# 5. MacBook Pro — Keyboard and function-key fix
#    On MBP, F-keys default to media keys. This sets them to standard F-keys.
# --------------------------------------------------------------------------- #
info "Configuring Apple keyboard function keys..."
echo "options hid_apple fnmode=2" > /etc/modprobe.d/hid_apple.conf
update-initramfs -u -k all
ok "Function key mode set to standard F-keys (fnmode=2)."

# --------------------------------------------------------------------------- #
# 6. Enable SSH service
# --------------------------------------------------------------------------- #
info "Enabling and starting SSH..."
systemctl enable ssh
systemctl start ssh
ok "SSH is running."

# --------------------------------------------------------------------------- #
# 7. Configure static IP (edit values below to match your network)
# --------------------------------------------------------------------------- #
NETPLAN_FILE="/etc/netplan/01-keun-cluster.yaml"
INTERFACE="eth0"       # Change to your actual interface (check with: ip a)
STATIC_IP="192.168.1.20/24"
GATEWAY="192.168.1.1"
DNS="8.8.8.8,8.8.4.4"

info "Writing static IP configuration to ${NETPLAN_FILE}..."
cat > "${NETPLAN_FILE}" <<EOF
network:
  version: 2
  ethernets:
    ${INTERFACE}:
      dhcp4: false
      addresses:
        - ${STATIC_IP}
      routes:
        - to: default
          via: ${GATEWAY}
      nameservers:
        addresses: [${DNS}]
EOF
chmod 600 "${NETPLAN_FILE}"
netplan apply
ok "Static IP configured: ${STATIC_IP} via ${INTERFACE}."

# --------------------------------------------------------------------------- #
# 8. Disable swap (required for Kubernetes / K3s)
# --------------------------------------------------------------------------- #
info "Disabling swap..."
swapoff -a
sed -i '/\sswap\s/d' /etc/fstab
ok "Swap disabled."

# --------------------------------------------------------------------------- #
# 9. Set kernel parameters for K3s
# --------------------------------------------------------------------------- #
info "Setting kernel parameters for K3s networking..."
cat > /etc/sysctl.d/99-k3s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system
ok "Kernel parameters applied."

# --------------------------------------------------------------------------- #
# 10. Install K3s agent
#    Replace <MASTER_IP> and <NODE_TOKEN> before running!
# --------------------------------------------------------------------------- #
MASTER_IP="${MASTER_IP:-<MASTER_IP>}"
NODE_TOKEN="${NODE_TOKEN:-<NODE_TOKEN>}"

if [[ "${MASTER_IP}" == "<MASTER_IP>" || "${NODE_TOKEN}" == "<NODE_TOKEN>" ]]; then
    warn "MASTER_IP or NODE_TOKEN not set. Skipping K3s agent installation."
    warn "To install the K3s agent, run:"
    warn "  export MASTER_IP=<your-master-ip>"
    warn "  export NODE_TOKEN=<your-node-token>  # found at /var/lib/rancher/k3s/server/node-token on master"
    warn "  curl -sfL https://get.k3s.io | K3S_URL=https://\${MASTER_IP}:6443 K3S_TOKEN=\${NODE_TOKEN} sh -"

else
    info "Installing K3s agent and joining cluster at https://${MASTER_IP}:6443 ..."
    curl -sfL https://get.k3s.io | \
        K3S_URL="https://${MASTER_IP}:6443" \
        K3S_TOKEN="${NODE_TOKEN}" \
        sh -
    ok "K3s agent installed and joined the cluster."
fi

# --------------------------------------------------------------------------- #
# 11. Done
# --------------------------------------------------------------------------- #
echo ""
ok "======================================================"
ok " MacBook Pro 2014 setup complete!"
ok " Next steps:"
ok "   1. Reboot to activate Wi-Fi driver: sudo reboot"
ok "   2. Verify node on master: kubectl get nodes"
ok "======================================================"
