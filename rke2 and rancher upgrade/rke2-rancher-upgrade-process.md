# SOP-INFRA-RKE2-RANCHER-UPGRADE
## Standard Operating Procedure: RKE2 and Rancher Upgrade

| Field | Details |
|---|---|
| **Document ID** | SOP-INFRA-RKE2-RANCHER-UPGRADE-001 |
| **Version** | v1.0 |
| **Prepared By** | Ganesh Sharma |
| **Environment** | NA |
| **Applies To** | RKE2 Kubernetes clusters managed by Rancher |
| **Last Updated** | 2026-04-07 |

---

## Table of Contents

1. [Purpose and Scope](#1-purpose-and-scope)
2. [Prerequisites and Assumptions](#2-prerequisites-and-assumptions)
3. [Compatibility and Version Planning](#3-compatibility-and-version-planning)
4. [Pre-Upgrade Backup](#4-pre-upgrade-backup)
5. [RKE2 Upgrade Procedure](#5-rke2-upgrade-procedure)
6. [Rancher Upgrade Procedure](#6-rancher-upgrade-procedure)
7. [Post-Upgrade Validation](#7-post-upgrade-validation)
8. [Rollback Procedures](#8-rollback-procedures)
9. [Air-Gap / Harbor Considerations](#9-air-gap--harbor-considerations)
10. [Known Issues and Gotchas](#10-known-issues-and-gotchas)
11. [Appendix: Command Reference](#11-appendix-command-reference)

---

## 1. Purpose and Scope

This SOP defines the step-by-step procedure for upgrading:

- **RKE2** Kubernetes distribution (one minor version at a time)
- **Rancher** multi-cluster management platform (via Helm)

---

## 2. Prerequisites and Assumptions

### Access Requirements

- SSH access to all RKE2 control plane and worker nodes
- `kubectl` access via `/etc/rancher/rke2/rke2.yaml` on the master node
- Helm 3 installed and configured
- `velero` CLI available
- Access to Harbor (only for air-gapped image pulls)
- Access to GitLab 

### Environment Variables (set before running commands)

```bash
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
export HARBOR_REGISTRY=<harbor-registry>
export RANCHER_NAMESPACE=cattle-system
```

### Maintenance Window

Upgrades must be performed during an approved maintenance window. Notify all stakeholders **well in advance**.

---

## 3. Compatibility and Version Planning

### Rule: One Minor Version at a Time

Never skip minor versions. Example of correct upgrade path:

```
v1.31.x → v1.32.x → v1.33.x    (NOT v1.31.x → v1.33.x)
Rancher 2.11.x → 2.12.x → 2.13.x  (NOT 2.11.x → 2.13.x)
```

### Check the Support Matrix

Before planning any upgrade, verify compatibility at:  
**https://www.suse.com/suse-rancher/support-matrix/**

Key compatibility constraints:
- Each Rancher version supports specific RKE2 version ranges
- Upgrade Rancher Management Server **before** upgrading RKE2 
- Upgrading Rancher ensures the management plane supports newer Kubernetes versions, preventing compatibility issues. 
- System charts (monitoring, logging) have their own compatibility requirements

### Determine Target Versions

```bash
# Check current RKE2 version on all nodes
kubectl get nodes -o wide

# Check current Rancher version
kubectl get deployment cattle-cluster-agent -n cattle-system \
  -o jsonpath='{.spec.template.spec.containers[0].image}'

# List available Rancher Helm chart versions
helm repo update
helm search repo rancher-stable/rancher --versions | head -20
```

---

## 4. Pre-Upgrade Backup

**This section is mandatory. Do not proceed without completing all backup steps.**

### 4.1 Velero Backup of Critical Namespaces

```bash
# Backup cattle-system, fleet namespaces, and any critical app namespaces
velero backup create rancher-pre-upgrade-$(date +%Y%m%d) \
  --include-namespaces cattle-system,fleet-system,fleet-default,cattle-fleet-system \
  --wait

# Verify backup completed successfully
velero backup describe rancher-pre-upgrade-$(date +%Y%m%d)
velero backup logs rancher-pre-upgrade-$(date +%Y%m%d)
```

Expected output: `Phase: Completed`

### 4.2 Save Current Helm Values

```bash
# Save Rancher Helm values before upgrade
helm get values rancher -n cattle-system > /root/rancher-values-backup-$(date +%Y%m%d).yaml
cat /root/rancher-values-backup-$(date +%Y%m%d).yaml
```

Store this file in GitLab or a safe location outside the cluster.

### 4.3 Capture Cluster State Snapshot

```bash
# Save current node state
kubectl get nodes -o wide > /root/pre-upgrade-nodes-$(date +%Y%m%d).txt

# Save all pods in cattle-system
kubectl get pods -n cattle-system -o wide > /root/pre-upgrade-pods-$(date +%Y%m%d).txt

# Save all deployed Helm releases
helm list -A > /root/pre-upgrade-helm-releases-$(date +%Y%m%d).txt
```

### 4.4 etcd Snapshot (RKE2)

RKE2 can take etcd snapshots directly:

```bash
# On the control plane node (as root)
rke2 etcd-snapshot save --name pre-upgrade-$(date +%Y%m%d)

# List snapshots to confirm
rke2 etcd-snapshot list
```

Snapshots are stored in `/var/lib/rancher/rke2/server/db/snapshots/` by default.

---

## 5. Rancher Upgrade Procedure

> **Order of operations:** Rancher (the management platform) must always be upgraded **before** upgrading the underlying RKE2 nodes. Rancher must be compatible with the target RKE2/Kubernetes version before that version is introduced to the cluster.

### 5.1 Update Helm Repositories

```bash
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
# or for latest channel:
# helm repo add rancher-latest https://releases.rancher.com/server-charts/latest

helm repo update
```

### 5.2 Verify Current Helm Release

```bash
helm list -n cattle-system
helm get values rancher -n cattle-system
```

### 5.3 Run Helm Upgrade

```bash
TARGET_RANCHER_VERSION=2.X.X   # Replace with target version

helm upgrade rancher rancher-stable/rancher \
  --namespace cattle-system \
  --version $TARGET_RANCHER_VERSION \
  --reuse-values
```

> **Important:** Always use `--reuse-values` to carry forward existing configuration (hostname, replica count, TLS settings, ingress class, etc.). If you need to override a value, append `--set key=value`.

### 5.4 Monitor Rollout

```bash
kubectl -n cattle-system rollout status deploy/rancher

# Watch pods rolling
kubectl get pods -n cattle-system -w
```

Expected behavior: pods terminate one at a time and new pods come up before the next one is terminated (RollingUpdate strategy).

### 5.5 Verify Rancher Webhook

After upgrade, verify the rancher-webhook pod is healthy:

```bash
kubectl get pods -n cattle-system | grep webhook
kubectl describe pod -n cattle-system -l app=rancher-webhook
```

> ⚠️ **Critical:** `rancher-webhook` is **not** a standalone Helm chart. Do **not** run `helm upgrade rancher-webhook`. It is managed entirely by Rancher. If the webhook pod is stuck on an old version post-upgrade, restart it:

```bash
kubectl rollout restart deployment/rancher-webhook -n cattle-system
```

If the webhook is blocking UI logins (emergency only):

```bash
# EMERGENCY BYPASS ONLY — re-enable after Rancher is healthy
kubectl delete validatingwebhookconfiguration rancher.cattle.io
```

---

## 6. Rancher Upgrade Procedure

### 6.1 Update Helm Repositories

```bash
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
# or for latest channel:
# helm repo add rancher-latest https://releases.rancher.com/server-charts/latest

helm repo update
```

### 6.2 Verify Current Helm Release

```bash
helm list -n cattle-system
helm get values rancher -n cattle-system
```

### 6.3 Run Helm Upgrade

```bash
TARGET_RANCHER_VERSION=2.X.X   # Replace with target version

helm upgrade rancher rancher-stable/rancher \
  --namespace cattle-system \
  --version $TARGET_RANCHER_VERSION \
  --reuse-values
```

> **Important:** Always use `--reuse-values` to carry forward existing configuration (hostname, replica count, TLS settings, ingress class, etc.). If you need to override a value, append `--set key=value`.

For air-gapped environments using a Harbor-mirrored chart:

```bash
helm upgrade rancher rancher-stable/rancher \
  --namespace cattle-system \
  --version $TARGET_RANCHER_VERSION \
  --reuse-values \
  --set rancherImage=<harbor-repo>/<harbor-registry>/rancher \
  --set rancherImageTag=v$TARGET_RANCHER_VERSION
```

### 6.4 Monitor Rollout

```bash
kubectl -n cattle-system rollout status deploy/rancher

# Watch pods rolling
kubectl get pods -n cattle-system -w
```

Expected behavior: pods terminate one at a time and new pods come up before the next one is terminated (RollingUpdate strategy).

### 6.5 Verify Rancher Webhook

After upgrade, verify the rancher-webhook pod is healthy:

```bash
kubectl get pods -n cattle-system | grep webhook
kubectl describe pod -n cattle-system -l app=rancher-webhook
```

> ⚠️ **Critical:** `rancher-webhook` is **not** a standalone Helm chart. Do **not** run `helm upgrade rancher-webhook`. It is managed entirely by Rancher. If the webhook pod is stuck on an old version post-upgrade, restart it:

```bash
kubectl rollout restart deployment/rancher-webhook -n cattle-system
```

If the webhook is blocking UI logins (emergency only):

```bash
# EMERGENCY BYPASS ONLY — re-enable after Rancher is healthy
kubectl delete validatingwebhookconfiguration rancher.cattle.io
```

---

## 7. Post-Upgrade Validation

### 7.1 Verify Node Health

```bash
kubectl get nodes -o wide
# All nodes: STATUS=Ready, correct VERSION
```

### 7.2 Verify System Pods

```bash
kubectl get pods -n cattle-system
kubectl get pods -n cattle-fleet-system
kubectl get pods -n fleet-default
kubectl get pods -n kube-system | grep -v Running | grep -v Completed
```

All pods should be in `Running` or `Completed` state. Investigate any pods in `CrashLoopBackOff`, `Error`, or `Pending`.

### 7.3 Verify Rancher UI

1. Log into the Rancher UI
2. Confirm new version shown in the bottom-left corner
3. Navigate to **Cluster Management** → all clusters should show **Active**
4. Navigate to **Apps** → confirm system apps (monitoring, logging) are healthy

### 7.4 Verify Downstream Cluster Agents

On each downstream cluster:

```bash
kubectl get pods -n cattle-system
# cattle-cluster-agent and cattle-node-agent should be Running
```

If agents are not reconnecting, restart them:

```bash
kubectl rollout restart deployment/cattle-cluster-agent -n cattle-system
```

### 7.5 Verify Rook-Ceph Storage

```bash
kubectl get pods -n rook-ceph
kubectl exec -n rook-ceph deploy/rook-ceph-tools -- ceph status
kubectl exec -n rook-ceph deploy/rook-ceph-tools -- ceph osd status
```

Expected: `HEALTH_OK`, all OSDs `up` and `in`.

### 7.6 Verify GitLab Runner Connectivity

Confirm CI/CD pipelines can still reach the cluster:

```bash
# Check runner pods (if running inside cluster)
kubectl get pods -n gitlab-runner

# Trigger a test pipeline in GitLab to verify runner registration
```

### 7.7 Post-Upgrade Checklist Sign-off

| Check | Result | Notes |
|---|---|---|
| All nodes Ready | ☐ | |
| Rancher UI accessible | ☐ | |
| Rancher version confirmed | ☐ | |
| All downstream clusters Active | ☐ | |
| Velero backup jobs running | ☐ | |
| Rook-Ceph health OK | ☐ | |
| Monitoring (Prometheus/Grafana) up | ☐ | |
| Logging (Loki) up | ☐ | |
| GitLab runner healthy | ☐ | |
| Kong Ingress pods healthy | ☐ | |
| Keycloak pods healthy | ☐ | |

---

## 8. Rollback Procedures

### 8.1 Rollback Rancher (Helm)

```bash
# View Helm history
helm history rancher -n cattle-system

# Rollback to the previous revision
helm rollback rancher <REVISION_NUMBER> -n cattle-system

# Monitor rollback
kubectl -n cattle-system rollout status deploy/rancher
```

### 8.2 Full Cluster Restore from Velero Backup

If the control plane is unreachable and etcd restore is not possible, restore from Velero:

```bash
# List available backups
velero backup get

# Restore the pre-upgrade backup
velero restore create --from-backup rancher-pre-upgrade-<DATE> \
  --include-namespaces cattle-system,fleet-system,fleet-default \
  --wait

velero restore describe <restore-name>
```

### 8.3 Restore etcd from RKE2 Snapshot

```bash
# On the control plane node — STOPS the cluster temporarily
rke2 server \
  --cluster-reset \
  --cluster-reset-restore-path=/var/lib/rancher/rke2/server/db/snapshots/pre-upgrade-<DATE>.zip
```

> ⚠️ This is destructive. Only use as a last resort. All nodes must be stopped before running this command.

---

## 9. Air-Gap / Harbor Considerations

### 9.1 Mirror RKE2 Images to Harbor

Before upgrading in the air-gapped environment, ensure the required RKE2 images are available in Harbor.

```bash
# On an internet-connected machine, pull and tag:
docker pull rancher/rke2-runtime:v1.XX.X-rke2r1
docker tag rancher/rke2-runtime:v1.XX.X-rke2r1 \
  <harbor-repo>/<harbor-registry>/rke2-runtime:v1.XX.X-rke2r1
docker push <harbor-repo>/<harbor-registry>/rke2-runtime:v1.XX.X-rke2r1
```

### 9.2 Offline RKE2 Install

Download the offline tarball from GitHub Releases and transfer via the Harbor artifact proxy or SCP:

```bash
# On the node
tar xzf rke2.linux-amd64.tar.gz -C /usr/local
systemctl restart rke2-server
```

### 9.3 Mirror Rancher Image to Harbor

```bash
docker pull rancher/rancher:v2.X.X
docker tag rancher/rancher:v2.X.X \
  <harbor-repo>/<harbor-registry>/rancher:v2.X.X
docker push <harbor-repo>/<harbor-registry>/rancher:v2.X.X
```

### 9.4 Proxy Configuration

Ensure `no_proxy` includes internal endpoints on all nodes:

```bash
# /etc/environment or systemd drop-in for rke2-server
NO_PROXY=localhost,127.0.0.1,172.24.0.0/16,172.28.0.0/16,your-harbor-endpoint.com,your-harbor-endpoint.com,.svc,.cluster.local
HTTP_PROXY=http://PROXY:3128
HTTPS_PROXY=http://PROXY:3128
```
---

## 11. Appendix: Command Reference

### Quick Health Checks

```bash
# Full cluster health summary
kubectl get nodes -o wide
kubectl get pods -A | grep -v Running | grep -v Completed

# Rancher version
kubectl get deployment cattle-cluster-agent  -n cattle-system \
  -o jsonpath='{.spec.template.spec.containers[0].image}'

# Helm releases
helm list -A

# Velero backup status
velero backup get

# Ceph cluster health
kubectl exec -n rook-ceph deploy/rook-ceph-tools -- ceph status
```

### Useful Diagnostic Commands

```bash
# Check RKE2 service logs on a node
journalctl -u rke2-server -f --since "10 minutes ago"

# Describe stuck pod
kubectl describe pod <pod-name> -n <namespace>

# Check events in a namespace
kubectl get events -n cattle-system --sort-by='.lastTimestamp'

# Check Helm upgrade history
helm history rancher -n cattle-system

# List available Velero backups
velero backup get

# Check DataDownload status (for Velero CSI restore issues)
kubectl get datadownload -n velero -o yaml
```

---

*End of SOP-INFRA-RKE2-RANCHER-UPGRADE-001 v1.0*
