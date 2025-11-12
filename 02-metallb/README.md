<!--- app-name: MetalLB -->
# MetalLB Deep Dive: Architecture and Best Practices

## 1. MetalLB Architecture and Concepts

### 1.1 What MetalLB Solves

**Problem**: Kubernetes LoadBalancer service type only works in cloud environments (AWS ELB, GCP Cloud Load Balancer, Azure Load Balancer). On bare metal, LoadBalancer services stay in "Pending" state forever.

**Solution**: MetalLB provides a network load balancer implementation for bare metal Kubernetes clusters.

### 1.2 MetalLB Architecture Components

```
┌─────────────────────────────────────────────────────────────┐
│                     MetalLB Architecture                    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │    Node 1   │    │    Node 2   │    │    Node 3   │     │
│  │             │    │             │    │             │     │
│  │ ┌─────────┐ │    │ ┌─────────┐ │    │ ┌─────────┐ │     │
│  │ │ Speaker │ │    │ │ Speaker │ │    │ │ Speaker │ │     │
│  │ │(DaemonSet)│    │ │(DaemonSet)│    │ │(DaemonSet)│     │
│  │ └─────────┘ │    │ └─────────┘ │    │ └─────────┘ │     │
│  └─────────────┘    └─────────────┘    └─────────────┘     │
│         │                   │                   │          │
│         └───────────────────┼───────────────────┘          │
│                             │                              │
│              ┌─────────────────────────┐                   │
│              │     Controller          │                   │
│              │   (Deployment)          │                   │
│              │                         │                   │
│              │ • IP Address Management │                   │
│              │ • Service Assignment    │                   │
│              │ • Config Validation     │                   │
│              └─────────────────────────┘                   │
└─────────────────────────────────────────────────────────────┘
```

### 1.3 Core Components Deep Dive

#### **Controller (Brain)**
- **Single replica** deployment (leader election for HA)
- **Responsibilities**:
  - Watches for LoadBalancer services
  - Assigns IP addresses from configured pools
  - Validates configurations
  - Updates service status with external IP
  - Manages IP address lifecycle

#### **Speaker (Network Interface)**
- **DaemonSet** (runs on every node)
- **Responsibilities**:
  - Announces assigned IPs to the network
  - Handles traffic routing to correct nodes
  - Implements the chosen protocol (L2 or BGP)
  - Monitors service health

### 1.4 MetalLB Operating Modes

#### **Layer 2 Mode (Default - Recommended for Your Setup)**

```
Network Flow in L2 Mode:
┌─────────────────────────────────────────────────────────────┐
│                        Router                                │
└─────────────────────┬───────────────────────────────────────┘
                      │
    ┌─────────────────┼─────────────────┐
    │                 │                 │
┌───▼────┐       ┌───▼────┐       ┌───▼────┐
│ Node 1 │       │ Node 2 │       │ Node 3 │
│        │       │ Leader │       │        │
│Speaker │       │Speaker │       │Speaker │
└────────┘       └────────┘       └────────┘
                      │
                 ┌───▼────┐
                 │ Pod    │
                 │Service │
                 └────────┘
```

**How L2 Mode Works:**
1. **IP Assignment**: Controller assigns IP from pool
2. **Leader Election**: One node becomes "leader" for that IP
3. **ARP Announcement**: Leader responds to ARP requests for the IP
4. **Traffic Flow**: All traffic for that IP goes to leader node
5. **Failover**: If leader fails, another node takes over

**L2 Mode Characteristics:**
- ✅ **Simple**: No network infrastructure changes needed
- ✅ **Works everywhere**: Any standard network
- ❌ **Single point ingress**: All traffic through one node
- ❌ **Limited bandwidth**: One node handles all traffic per service

#### **BGP Mode (Advanced)**

```
BGP Mode Architecture:
┌─────────────────────────────────────────────────────────────┐
│                    BGP Router                                │
│              (Learns routes from nodes)                     │
└─────────┬───────────────┬───────────────┬───────────────────┘
          │               │               │
      ┌───▼────┐     ┌───▼────┐     ┌───▼────┐
      │ Node 1 │     │ Node 2 │     │ Node 3 │
      │ BGP    │     │ BGP    │     │ BGP    │
      │Speaker │     │Speaker │     │Speaker │
      └────────┘     └────────┘     └────────┘
```

**BGP Mode Benefits:**
- ✅ **True load balancing**: Traffic distributed across nodes
- ✅ **High bandwidth**: Multiple nodes handle traffic
- ✅ **Router integration**: Works with enterprise networks
- ❌ **Complex setup**: Requires BGP-capable network equipment

### 1.5 Official Metallb Helm chart Deployment

```bash
# Add official MetalLB repo
helm repo add metallb https://metallb.github.io/metallb
helm repo update

# Install MetalLB
helm install metallb metallb/metallb \
  --namespace metallb-system \
  --create-namespace

# Wait for MetalLB pods to be ready
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=metallb \
  --timeout=90s

# Create IPAddressPool and L2Advertisement
cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.64.200-192.168.64.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
spec:
  ipAddressPools:
  - default-pool
EOF
```

OR

### 1.6 Bitnami MetalLB Deployment

```bash
# Add Bitnami repository
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Create namespace
kubectl create namespace metallb-system

# Install MetalLB with Bitnami chart
helm install metallb bitnami/metallb \
  --namespace metallb-system \
  --set configInline.address-pools[0].name=default \
  --set configInline.address-pools[0].protocol=layer2 \
  --set configInline.address-pools[0].addresses[0]=192.168.1.200-192.168.1.250

# Or use values file for complex configuration
cat > metallb-values.yaml <<EOF
# MetalLB Configuration
configInline:
  address-pools:
  - name: default
    protocol: layer2
    addresses:
    - 192.168.1.200-192.168.1.250
  - name: critical-services
    protocol: layer2
    addresses:
    - 192.168.1.100-192.168.1.110
    
speaker:
  tolerations:
  - key: node-role.kubernetes.io/master
    effect: NoSchedule
    operator: Exists

controller:
  resources:
    limits:
      cpu: 200m
      memory: 256Mi
    requests:
      cpu: 100m
      memory: 128Mi
EOF

helm install metallb bitnami/metallb \
  --namespace metallb-system \
  --values metallb-values.yaml
```

### Verify and Test MetalLB Installation

```bash
# Check MetalLB pods
kubectl get pods -n metallb-system

# Check IPAddressPool (if using official chart)
kubectl get ipaddresspool -n metallb-system

# Check L2Advertisement (if using official chart)
kubectl get l2advertisement -n metallb-system

# Create a test LoadBalancer service
kubectl create deployment nginx-lb-test --image=nginx
kubectl expose deployment nginx-lb-test --type=LoadBalancer --port=80

# Wait for EXTERNAL-IP to be assigned
kubectl get svc nginx-lb-test -w

# Should show an IP like 192.168.64.200
```