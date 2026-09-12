# Automate RKE2 Installation

## Prepare Node:

```bash
# Make the script executable:
chmod +x prepare-node.sh

# Become root:
sudo su -

# Run the prepare-node.sh script along with the Hostname:
./prepare-node.sh <hostname>

# If all prerequisites are installed :

helm version

echo "Node preparation complete."
```

## Install RKE2 Server and Agent roles:

```bash

# Continue being root:
chmod +x install-rke2.sh
./install-rke2.sh server

# Verify if Control plane is up:
systemctl status rke2-server --no-pager

# ADD PATHS:
export PATH="/var/lib/rancher/rke2/bin:$PATH"
export KUBECONFIG="/etc/rancher/rke2/rke2.yaml"

# Verify if Node is Ready?
kubectl get nodes -o wide
kubectl get pods -A

# Save the Cluster Join Token:
cat /var/lib/rancher/rke2/server/node-token

# Navigate and run on all Worker Nodes:
export RKE2_SERVER_IP="<server-ip>"
export RKE2_TOKEN="<token>"
./install-rke2.sh agent

# Verify if Worker Nodes are ready 
systemctl status rke2-server --no-pager
journalctl -u rke2-server -n 100 --no-pager
```