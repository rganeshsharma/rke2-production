#!/usr/bin/env bash

set -euo pipefail

NODE_NAME="${1:-}"

echo "Preparing node: $NODE_NAME"

echo "Install prerequisites..."
apt-get update

apt-get install -y \
  curl \
  ca-certificates \
  jq \
  apparmor \
  apparmor-utils

echo "Set hostname..."
hostnamectl set-hostname "$NODE_NAME"

echo "Disable swap..."
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

echo "Load kernel modules..."
modprobe overlay
modprobe br_netfilter

cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF

echo "Configure kernel networking..."

cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

sysctl --system

echo "Disable UFW..."
systemctl disable --now ufw || true

echo "Install kubectl..."

ARCH=$(uname -m)

if [ "$ARCH" = "aarch64" ]; then
  ARCH="arm64"
else
  ARCH="amd64"
fi

KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)

curl -LO \
  "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl"

install -m 0755 kubectl /usr/local/bin/kubectl
rm -f kubectl

kubectl version --client

echo "Install Helm..."

curl -fsSL \
  https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 \
  | bash

helm version

echo "Node preparation complete."