
#!/usr/bin/env bash

set -euo pipefail

ROLE="${1:-server}"
NODE_NAME=$(hostname)

mkdir -p /etc/rancher/rke2


if [ "$ROLE" = "server" ]; then

  echo "Installing RKE2 server on $NODE_NAME..."

  curl -sfL https://get.rke2.io | sh -

  cat > /etc/rancher/rke2/config.yaml <<EOF
node-name: ${NODE_NAME}
write-kubeconfig-mode: "0644"
EOF

  systemctl enable --now rke2-server

  export PATH="/var/lib/rancher/rke2/bin:$PATH"
  export KUBECONFIG="/etc/rancher/rke2/rke2.yaml"

  echo "Verify cluster..."
  kubectl get nodes -o wide

  echo "RKE2 join token:"
  cat /var/lib/rancher/rke2/server/node-token


elif [ "$ROLE" = "agent" ]; then

  echo "Installing RKE2 agent on $NODE_NAME..."

  curl -sfL https://get.rke2.io \
    | INSTALL_RKE2_TYPE=agent sh -

  cat > /etc/rancher/rke2/config.yaml <<EOF
server: https://${RKE2_SERVER_IP}:9345
token: ${RKE2_TOKEN}
node-name: ${NODE_NAME}
EOF

  systemctl enable --now rke2-agent

  echo "RKE2 agent started."


else

  echo "Usage:"
  echo "  ./install-rke2.sh server"
  echo "  ./install-rke2.sh agent"

  exit 1

fi

