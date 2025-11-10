# RKE2 Cluster Installation SOP
## Ubuntu 24.04 VM Setup with Static IPs and RKE2

**Document Version:** 1.0  
**Last Updated:** November 10, 2025  
**Target Environment:** MacBook M3 with UTM/Parallels/VMware Fusion

---

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Phase 1: Ubuntu 24.04 Installation](#phase-1-ubuntu-2404-installation)
3. [Phase 2: Network Configuration with Netplan](#phase-2-network-configuration-with-netplan)
4. [Phase 3: System Preparation](#phase-3-system-preparation)
5. [Phase 4: RKE2 Master Installation](#phase-4-rke2-master-installation)
6. [Phase 5: RKE2 Worker Installation](#phase-5-rke2-worker-installation)
7. [Phase 6: Cluster Verification](#phase-6-cluster-verification)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Information
Before starting, document the following:

| Node | Hostname | Static IP | Role |
|------|----------|-----------|------|
| Node 1 | master | 192.168.64.10 | Master |
| Node 2 | worker1 | 192.168.64.11 | Worker |
| Node 3 | worker2 | 192.168.64.12 | Worker |

**Network Details:**
- **Gateway:** 192.168.64.1 (adjust based on your VM network)
- **DNS Servers:** 8.8.8.8, 8.8.4.4
- **Subnet:** 192.168.64.0/24

### Downloads Required
- Ubuntu 24.04 LTS Server ARM64 ISO
- Download from: https://ubuntu.com/download/server/arm

### VM Specifications
- **Master:** 6 vCPU, 16GB RAM, 50GB Disk
- **Worker1:** 6 vCPU, 32GB RAM, 100GB Disk
- **Worker2:** 6 vCPU, 32GB RAM, 100GB Disk

---

## Phase 1: Ubuntu 24.04 Installation

### Step 1.1: Create VM in Hypervisor

**For UTM:**
```
1. Open UTM
2. Click "Create a New Virtual Machine"
3. Select "Virtualize"
4. Choose "Linux"
5. Configure:
   - Boot ISO: Ubuntu 24.04 ARM64 ISO
   - CPU Cores: 6
   - Memory: 16GB (master) or 32GB (workers)
   - Storage: 50GB (master) or 100GB (workers)
6. Click "Save"
```

**For Parallels/VMware:** Follow similar steps in respective UI.

### Step 1.2: Initial Ubuntu Installation

Boot the VM and proceed with installation:

```
1. Select: "Install Ubuntu Server"
2. Language: English
3. Keyboard: Your layout (usually English US)
4. Network: Skip configuration (we'll do it later with netplan)
5. Proxy: Leave blank
6. Mirror: Use default
7. Storage: Use entire disk (default)
8. Profile Setup:
   - Your name: admin
   - Server name: master (or worker1/worker2)
   - Username: admin
   - Password: [Choose a strong password]
9. SSH Setup: Install OpenSSH server ✓
10. Featured Server Snaps: Skip all
11. Wait for installation to complete
12. Reboot
```

### Step 1.3: First Boot and Login

```bash
# Login with credentials created during installation
Username: admin
Password: [your password]
```

### Step 1.4: Update System

```bash
# Update package lists and upgrade
sudo apt update && sudo apt upgrade -y

# Install essential tools
sudo apt install -y net-tools curl wget vim git
```

---

## Phase 2: Network Configuration with Netplan

### Step 2.1: Identify Network Interface

```bash
# List network interfaces
ip addr show

# Common interface names:
# - enp0s1 (for UTM/virtualization)
# - eth0
# - ens33
```

**Note the interface name** (e.g., `enp0s1`) - you'll need it for netplan configuration.

### Step 2.2: Backup Existing Netplan Configuration

```bash
# Navigate to netplan directory
cd /etc/netplan/

# List existing files
ls -la

# Backup existing configuration
sudo cp 50-cloud-init.yaml 50-cloud-init.yaml.backup
```

### Step 2.3: Configure Static IP with Netplan

#### For Master Node (192.168.64.10)

```bash
# Create/edit netplan configuration
sudo nano /etc/netplan/01-netcfg.yaml
```

**Add the following content** (adjust interface name and IPs for your environment):

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enp0s1:  # Replace with your interface name
      dhcp4: no
      addresses:
        - 192.168.64.10/24
      routes:
        - to: default
          via: 192.168.64.1
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
```

#### For Worker1 Node (192.168.64.11)

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enp0s1:  # Replace with your interface name
      dhcp4: no
      addresses:
        - 192.168.64.11/24
      routes:
        - to: default
          via: 192.168.64.1
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
```

#### For Worker2 Node (192.168.64.12)

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enp0s1:  # Replace with your interface name
      dhcp4: no
      addresses:
        - 192.168.64.12/24
      routes:
        - to: default
          via: 192.168.64.1
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
```

### Step 2.4: Apply Netplan Configuration

```bash
# Test the configuration (shows what would be applied)
sudo netplan try

# If no errors, press ENTER to accept
# OR wait 120 seconds for auto-rollback if something is wrong

# Apply the configuration permanently
sudo netplan apply

# Verify the new IP
ip addr show

# Test connectivity
ping -c 4 8.8.8.8
ping -c 4 192.168.64.1
```

### Step 2.5: Disable Cloud-Init Network Management

```bash
# Create cloud-init config to prevent it from managing network
sudo mkdir -p /etc/cloud/cloud.cfg.d/

sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg > /dev/null <<EOF
network: {config: disabled}
EOF

# Reboot to ensure settings persist
sudo reboot
```

**After reboot, verify:**
```bash
ip addr show
ping -c 4 8.8.8.8
```

---

## Phase 3: System Preparation

### Step 3.1: Set Hostname (on each node)

#### On Master Node:
```bash
sudo hostnamectl set-hostname master
```

#### On Worker1 Node:
```bash
sudo hostnamectl set-hostname worker1
```

#### On Worker2 Node:
```bash
sudo hostnamectl set-hostname worker2
```

**Verify:**
```bash
hostnamectl
hostname
```

### Step 3.2: Configure /etc/hosts (on ALL nodes)

```bash
# Edit hosts file
sudo nano /etc/hosts
```

**Add the following lines to ALL nodes:**
```
127.0.0.1 localhost

# RKE2 Cluster Nodes
192.168.64.10 master master.local
192.168.64.11 worker1 worker1.local
192.168.64.12 worker2 worker2.local
```

**Save and exit** (Ctrl+X, Y, Enter)

**Verify connectivity:**
```bash
ping -c 2 master
ping -c 2 worker1
ping -c 2 worker2
```

### Step 3.3: Configure SSH Key-Based Authentication (Optional but Recommended)

#### On Master Node:
```bash
# Generate SSH key
ssh-keygen -t ed25519 -C "master-node"
# Press Enter for all prompts (default location, no passphrase)

# Copy key to worker nodes
ssh-copy-id admin@worker1
ssh-copy-id admin@worker2

# Test passwordless SSH
ssh admin@worker1
exit
ssh admin@worker2
exit
```

### Step 3.4: Disable Swap (Required for Kubernetes)

```bash
# Disable swap immediately
sudo swapoff -a

# Disable swap permanently
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Verify swap is off
free -h
# Swap line should show 0
```

### Step 3.5: Load Required Kernel Modules

```bash
# Load modules
sudo modprobe overlay
sudo modprobe br_netfilter

# Make modules load on boot
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
```

### Step 3.6: Configure Kernel Parameters

```bash
# Set sysctl parameters
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Apply sysctl parameters
sudo sysctl --system

# Verify
sudo sysctl net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward
```

### Step 3.7: Configure Firewall (Optional - or disable for testing)

#### Option A: Disable Firewall (for testing environments)
```bash
sudo systemctl stop ufw
sudo systemctl disable ufw
```

#### Option B: Configure Firewall Rules (for production)

**On Master Node:**
```bash
# Allow RKE2 required ports
sudo ufw allow 22/tcp     # SSH
sudo ufw allow 6443/tcp   # Kubernetes API
sudo ufw allow 9345/tcp   # RKE2 supervisor API
sudo ufw allow 10250/tcp  # Kubelet
sudo ufw allow 2379/tcp   # etcd client
sudo ufw allow 2380/tcp   # etcd peer
sudo ufw allow 8472/udp   # Canal/Flannel VXLAN
sudo ufw allow 4789/udp   # Flannel VXLAN (alternative)
sudo ufw allow 80/tcp     # NGINX Ingress
sudo ufw allow 443/tcp    # NGINX Ingress HTTPS

sudo ufw enable
sudo ufw status
```

**On Worker Nodes:**
```bash
sudo ufw allow 22/tcp     # SSH
sudo ufw allow 10250/tcp  # Kubelet
sudo ufw allow 8472/udp   # Canal/Flannel VXLAN
sudo ufw allow 4789/udp   # Flannel VXLAN (alternative)
sudo ufw allow 80/tcp     # NGINX Ingress
sudo ufw allow 443/tcp    # NGINX Ingress HTTPS

sudo ufw enable
sudo ufw status
```

---

## Phase 4: RKE2 Master Installation

### Step 4.1: Install RKE2 Server on Master Node

```bash
# Download and install RKE2 server
curl -sfL https://get.rke2.io | sudo sh -
```

### Step 4.2: Create RKE2 Configuration (Optional)

```bash
# Create config directory
sudo mkdir -p /etc/rancher/rke2

# Create config file for custom settings (optional)
sudo tee /etc/rancher/rke2/config.yaml > /dev/null <<EOF
# RKE2 Server Configuration
write-kubeconfig-mode: "0644"
tls-san:
  - "master"
  - "master.local"
  - "192.168.64.10"
# Uncomment below to customize CNI
# cni:
#   - canal
EOF
```

### Step 4.3: Start RKE2 Server

```bash
# Enable RKE2 server service
sudo systemctl enable rke2-server.service

# Start RKE2 server
sudo systemctl start rke2-server.service

# This will take 1-3 minutes on first start
# Monitor the startup
sudo journalctl -u rke2-server -f
# Press Ctrl+C when you see "Node master is ready"
```

### Step 4.4: Verify RKE2 Server is Running

```bash
# Check service status
sudo systemctl status rke2-server.service

# Should show "active (running)"
```

### Step 4.5: Configure kubectl Access

```bash
# Create .kube directory
mkdir -p ~/.kube

# Copy kubeconfig
sudo cp /etc/rancher/rke2/rke2.yaml ~/.kube/config

# Set ownership
sudo chown $USER:$USER ~/.kube/config

# Set permissions
chmod 600 ~/.kube/config

# Add RKE2 binaries to PATH
echo 'export PATH=$PATH:/var/lib/rancher/rke2/bin' >> ~/.bashrc
echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc
source ~/.bashrc

# Verify kubectl works
kubectl get nodes
```

**Expected output:**
```
NAME     STATUS   ROLES                       AGE   VERSION
master   Ready    control-plane,etcd,master   2m    v1.28.x+rke2r1
```

### Step 4.6: Retrieve Node Token

```bash
# Get the node token (needed for worker nodes)
sudo cat /var/lib/rancher/rke2/server/node-token

# Example output:
# K10abcdef1234567890::server:1234567890abcdef
```

**⚠️ IMPORTANT:** Save this token - you'll need it for joining worker nodes!

### Step 4.7: Verify Master Node is Healthy

```bash
# Check all system pods are running
kubectl get pods -A

# Wait until all pods show "Running" or "Completed"
# This may take 2-5 minutes
```

---

## Phase 5: RKE2 Worker Installation

Perform these steps on **BOTH worker1 and worker2 nodes**.

### Step 5.1: Create RKE2 Agent Configuration

```bash
# Create config directory
sudo mkdir -p /etc/rancher/rke2/

# Create config file
sudo nano /etc/rancher/rke2/config.yaml
```

**Add the following content:**
```yaml
server: https://192.168.64.10:9345
token: K10abcdef1234567890::server:1234567890abcdef
```

**Replace the token with the actual token from Step 4.6!**

**Save and exit** (Ctrl+X, Y, Enter)

### Step 5.2: Install RKE2 Agent

```bash
# Download and install RKE2 agent
curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="agent" sudo sh -
```

### Step 5.3: Start RKE2 Agent

```bash
# Enable RKE2 agent service
sudo systemctl enable rke2-agent.service

# Start RKE2 agent
sudo systemctl start rke2-agent.service

# Monitor the startup (wait for successful join message)
sudo journalctl -u rke2-agent -f
# Press Ctrl+C after seeing connection success messages
```

### Step 5.4: Verify Agent is Running

```bash
# Check service status
sudo systemctl status rke2-agent.service

# Should show "active (running)"
```

### Step 5.5: Configure kubectl on Worker Nodes (Optional)

If you want to run kubectl commands from worker nodes:

```bash
# Create .kube directory
mkdir -p ~/.kube

# Copy kubeconfig from master
scp admin@master:~/.kube/config ~/.kube/config

# Add RKE2 binaries to PATH
echo 'export PATH=$PATH:/var/lib/rancher/rke2/bin' >> ~/.bashrc
echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc
source ~/.bashrc
```

---

## Phase 6: Cluster Verification

### Step 6.1: Verify All Nodes Joined (from Master)

```bash
# Check all nodes
kubectl get nodes

# Expected output:
NAME      STATUS   ROLES                       AGE     VERSION
master    Ready    control-plane,etcd,master   10m     v1.28.x+rke2r1
worker1   Ready    <none>                      3m      v1.28.x+rke2r1
worker2   Ready    <none>                      2m      v1.28.x+rke2r1
```

**All nodes should show STATUS: Ready**

### Step 6.2: Verify All System Pods are Running

```bash
# Check all pods in all namespaces
kubectl get pods -A

# All pods should be in "Running" or "Completed" state
# Pay special attention to:
# - rke2-canal-* (3 pods, one per node)
# - rke2-ingress-nginx-controller-* (3 pods, one per node)
# - rke2-coredns-* (2 pods)
```

### Step 6.3: Verify Cluster Info

```bash
# Get cluster info
kubectl cluster-info

# Get node details
kubectl get nodes -o wide

# Check component status
kubectl get cs
```

### Step 6.4: Test Pod Creation and Communication

```bash
# Create a test deployment
kubectl create deployment nginx-test --image=nginx --replicas=3

# Wait for pods to be ready
kubectl get pods -w
# Press Ctrl+C when all 3 pods are Running

# Check pod distribution across nodes
kubectl get pods -o wide

# Expose the deployment
kubectl expose deployment nginx-test --port=80 --type=NodePort

# Get the NodePort
kubectl get svc nginx-test

# Test access from master
curl http://localhost:<NodePort>

# Should return nginx welcome page
```

### Step 6.5: Clean Up Test Resources

```bash
# Delete test deployment and service
kubectl delete deployment nginx-test
kubectl delete service nginx-test
```

---

## Troubleshooting

### Issue 1: Node Not Joining Cluster

**Symptoms:** Worker node shows in NotReady state or doesn't appear in `kubectl get nodes`

**Solutions:**
```bash
# On worker node, check agent logs
sudo journalctl -u rke2-agent -n 100

# Common issues:
# 1. Wrong token - verify token in /etc/rancher/rke2/config.yaml
# 2. Network connectivity - ping master from worker
ping -c 4 192.168.64.10

# 3. Firewall blocking ports
sudo ufw status

# 4. Restart agent service
sudo systemctl restart rke2-agent
```

### Issue 2: Static IP Not Persisting After Reboot

**Solutions:**
```bash
# Check netplan configuration
cat /etc/netplan/01-netcfg.yaml

# Verify cloud-init is disabled for network
cat /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg

# Reapply netplan
sudo netplan apply

# Check for conflicting netplan files
ls -la /etc/netplan/
# Remove or rename old files if necessary
```

### Issue 3: Pods Stuck in Pending or ContainerCreating

**Solutions:**
```bash
# Describe the pod to see events
kubectl describe pod <pod-name> -n <namespace>

# Check node resources
kubectl top nodes

# Check CNI pods are running
kubectl get pods -n kube-system | grep canal

# Restart problematic node
# On the node:
sudo systemctl restart rke2-server  # on master
sudo systemctl restart rke2-agent   # on worker
```

### Issue 4: Cannot Access Cluster from Master

**Solutions:**
```bash
# Verify KUBECONFIG is set
echo $KUBECONFIG

# Check kubeconfig file exists and has correct permissions
ls -la ~/.kube/config

# Verify API server is running
sudo systemctl status rke2-server

# Check if you can reach API server
curl -k https://127.0.0.1:6443/version
```

### Issue 5: Networking Issues Between Pods

**Solutions:**
```bash
# Check Canal CNI pods
kubectl get pods -n kube-system -l k8s-app=canal

# Check IP forwarding is enabled
sudo sysctl net.ipv4.ip_forward
# Should return: net.ipv4.ip_forward = 1

# Check iptables rules
sudo iptables -L -n -v | grep -i canal

# Restart Canal pods
kubectl delete pod -n kube-system -l k8s-app=canal
```

---

## Post-Installation Tasks

### 1. Label Worker Nodes (Optional)

```bash
# Add role labels to worker nodes
kubectl label node worker1 node-role.kubernetes.io/worker=worker
kubectl label node worker2 node-role.kubernetes.io/worker=worker

# Verify
kubectl get nodes
```

### 2. Install Helm (Optional)

```bash
# On master node
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify installation
helm version
```

### 3. Configure Persistent Storage (Optional)

```bash
# Install local-path-provisioner (already included in RKE2)
kubectl get storageclass

# Should see "local-path" as default
```

### 4. Setup Monitoring (Optional)

```bash
# RKE2 includes metrics-server by default
kubectl top nodes
kubectl top pods -A
```

---

## Quick Reference Commands

### Cluster Management
```bash
# View all nodes
kubectl get nodes -o wide

# View all pods in all namespaces
kubectl get pods -A

# View cluster info
kubectl cluster-info

# View cluster events
kubectl get events -A --sort-by='.lastTimestamp'
```

### RKE2 Service Management
```bash
# Master Node
sudo systemctl status rke2-server
sudo systemctl start rke2-server
sudo systemctl stop rke2-server
sudo systemctl restart rke2-server
sudo journalctl -u rke2-server -f

# Worker Nodes
sudo systemctl status rke2-agent
sudo systemctl start rke2-agent
sudo systemctl stop rke2-agent
sudo systemctl restart rke2-agent
sudo journalctl -u rke2-agent -f
```

### Network Debugging
```bash
# Test connectivity between nodes
ping master
ping worker1
ping worker2

# Check listening ports
sudo netstat -tulpn | grep -E '(6443|9345|10250)'

# Test API server
curl -k https://192.168.64.10:6443/version
```

---

## Maintenance Tasks

### Backup RKE2 Configuration

```bash
# On master node
sudo tar -czf rke2-backup-$(date +%Y%m%d).tar.gz \
  /etc/rancher/rke2 \
  /var/lib/rancher/rke2/server \
  ~/.kube/config

# Copy backup to safe location
```

### Update RKE2

```bash
# On master first
curl -sfL https://get.rke2.io | sudo sh -
sudo systemctl restart rke2-server

# Wait for master to be healthy
kubectl get nodes

# Then on each worker
curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="agent" sudo sh -
sudo systemctl restart rke2-agent
```

---

## Security Hardening Checklist

- [ ] Change default passwords
- [ ] Configure SSH key-based authentication
- [ ] Disable root SSH login
- [ ] Configure firewall rules (UFW)
- [ ] Enable automatic security updates
- [ ] Regularly update RKE2 and Ubuntu packages
- [ ] Use RBAC for cluster access control
- [ ] Enable audit logging
- [ ] Use network policies to restrict pod communication

---

## Appendix A: Network IP Planning Template

| Node | Hostname | Static IP | Gateway | DNS | MAC Address |
|------|----------|-----------|---------|-----|-------------|
| Master | master | 192.168.64.10 | 192.168.64.1 | 8.8.8.8 | |
| Worker1 | worker1 | 192.168.64.11 | 192.168.64.1 | 8.8.8.8 | |
| Worker2 | worker2 | 192.168.64.12 | 192.168.64.1 | 8.8.8.8 | |

---

## Appendix B: Port Reference

| Port | Protocol | Purpose | Required On |
|------|----------|---------|-------------|
| 22 | TCP | SSH | All nodes |
| 6443 | TCP | Kubernetes API | Master |
| 9345 | TCP | RKE2 Supervisor API | Master |
| 10250 | TCP | Kubelet API | All nodes |
| 2379-2380 | TCP | etcd | Master |
| 8472 | UDP | Flannel VXLAN | All nodes |
| 80 | TCP | HTTP Ingress | All nodes |
| 443 | TCP | HTTPS Ingress | All nodes |

---

## Document History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2025-11-10 | Initial SOP creation | Admin |

---

**End of Document**