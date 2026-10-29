#!/usr/bin/env bash
# =============================================================================
# n5095-ubuntu-setup.sh
# Ubuntu 22.04 LTS setup script for an Intel N5095 mini PC
#
# Configures an N5095 mini PC as a K3s worker node and joins it to the cluster.
#
# Usage:
#   chmod +x n5095-ubuntu-setup.sh
#   export MASTER_IP=<your-master-ip>
#   export NODE_TOKEN=<your-node-token>   # /var/lib/rancher/k3s/server/node-token on master
#   sudo -E ./n5095-ubuntu-setup.sh
# =============================================================================

set -euo pipefail

# --------------------------------------------------------------------------- #
# 0. Helpers
# --------------------------------------------------------------------------- #
info()  { echo -e "\033[0;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[0;32m[OK]\033[0m    $*"; }
warn()  { echo -e "\033[0;33m[WARN]\033[0m  $*"; }
die()   { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || die "Run this script as root (sudo -E)."

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
    btop \
    net-tools \
    openssh-server \
    ca-certificates \
    gnupg \
    lsb-release \
    apt-transport-https \
    software-properties-common
ok "Essential packages installed."

# --------------------------------------------------------------------------- #
# 3. Enable SSH service
# --------------------------------------------------------------------------- #
info "Enabling and starting SSH..."
systemctl enable ssh
systemctl start ssh
ok "SSH is running."

# --------------------------------------------------------------------------- #
# 4. Configure static IP (edit values below to match your network)
# --------------------------------------------------------------------------- #
NETPLAN_FILE="/etc/netplan/01-keun-cluster.yaml"
INTERFACE="${INTERFACE:-enp2s0}"   # Change to your actual interface (check with: ip a)
STATIC_IP="${STATIC_IP:-192.168.1.40/24}"
GATEWAY="${GATEWAY:-192.168.1.1}"
DNS="${DNS:-8.8.8.8,8.8.4.4}"

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
# 5. Disable swap (required for Kubernetes / K3s)
# --------------------------------------------------------------------------- #
info "Disabling swap..."
swapoff -a
sed -i '/\sswap\s/d' /etc/fstab
ok "Swap disabled."

# --------------------------------------------------------------------------- #
# 6. Set kernel parameters for K3s
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
# 7. Configure UFW firewall
# --------------------------------------------------------------------------- #
info "Configuring UFW firewall rules..."
ufw allow OpenSSH
ufw allow 8472/udp   # Flannel VXLAN
ufw allow 10250/tcp  # Kubelet metrics
ufw --force enable
ok "Firewall configured."

# --------------------------------------------------------------------------- #
# 8. Install K3s agent
#    Pass MASTER_IP and NODE_TOKEN as environment variables, e.g.:
#      export MASTER_IP=192.168.1.10
#      export NODE_TOKEN=$(ssh user@master sudo cat /var/lib/rancher/k3s/server/node-token)
#      sudo -E ./n5095-ubuntu-setup.sh
# --------------------------------------------------------------------------- #
MASTER_IP="${MASTER_IP:-<MASTER_IP>}"
NODE_TOKEN="${NODE_TOKEN:-<NODE_TOKEN>}"

if [[ "${MASTER_IP}" == "<MASTER_IP>" || "${NODE_TOKEN}" == "<NODE_TOKEN>" ]]; then
    warn "MASTER_IP or NODE_TOKEN not set. Skipping K3s agent installation."
    warn "To install the K3s agent manually, run:"
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
# 9. Done
# --------------------------------------------------------------------------- #
echo ""
ok "======================================================"
ok " N5095 setup complete!"
ok " Next steps:"
ok "   1. Verify node on master: kubectl get nodes"
ok "   2. Check agent status:    sudo systemctl status k3s-agent"
ok "======================================================"
