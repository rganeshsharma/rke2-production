Mount something like`/mnt/longhorn` on the **three worker nodes**, this is a clean setup for Longhorn.

As of August 24, 2026, the current Longhorn documentation is for **v1.12.1**, and Helm installation is officially supported. Longhorn 1.12.1 requires Kubernetes **v1.25+**, so your current RKE2 generation is fine. ([Longhorn][1])

### 1. Verify each worker

Run this on **all three workers**:

```bash
findmnt /mnt/longhorn
df -hT /mnt/longhorn
mountpoint /mnt/longhorn
```

You want something like:

```text
/dev/sdb1  /mnt/longhorn  xfs  rw,...
```

Having the host disk formatted **XFS is perfectly fine**. Longhorn stores replica files inside `/mnt/longhorn`; the filesystem presented to Kubernetes PVCs can still be `ext4`.

Also make sure the mount is persistent:

```bash
grep /mnt/longhorn /etc/fstab
```

---

### 2. Install prerequisites on all workers

On Ubuntu:

```bash
sudo apt update

sudo apt install -y \
  open-iscsi \
  nfs-common \
  cryptsetup

sudo systemctl enable --now iscsid

sudo modprobe iscsi_tcp
```

Verify:

```bash
systemctl is-active iscsid

lsmod | grep iscsi_tcp

which iscsiadm
```

Longhorn requires iSCSI support for its standard volume attachment path. ([Longhorn][2])

`nfs-common` is useful because Longhorn uses NFS-based share-manager functionality for **RWX** volumes.

---

### 3. Identify your worker node names

From your management/master node:

```bash
kubectl get nodes -o wide
```

Suppose they are:

```text
rke2worker1
rke2worker2 
rke2worker3
```

Label **only these three**:

```bash
kubectl label node rke2worker1 node.longhorn.io/create-default-disk=true

kubectl label node rke2worker2 node.longhorn.io/create-default-disk=true

kubectl label node rke2worker3 node.longhorn.io/create-default-disk=true
```

Verify:

```bash
kubectl get nodes --show-labels | grep longhorn
```

This is important because we're going to tell Longhorn:

```yaml
createDefaultDiskLabeledNodes: true
```

That means it won't accidentally create `/mnt/longhorn` on your control-plane/root disk. This behavior is documented by Longhorn. ([GitHub][3])

---

## 4. Create the Longhorn values

For your 3-worker POC, I'd use:

```bash
cat > longhorn-values.yaml <<'EOF'
defaultSettings:

  # Only nodes carrying:
  # node.longhorn.io/create-default-disk=true
  # will automatically receive a Longhorn disk.
  createDefaultDiskLabeledNodes: true

  # Physical storage mounted on each worker
  defaultDataPath: /mnt/longhorn

persistence:

  # Create the "longhorn" StorageClass
  createStorageClass: true

  # Make Longhorn the default Kubernetes StorageClass
  defaultClass: true

  # Filesystem created inside Longhorn volumes
  defaultFsType: ext4

  # One replica on each of the 3 workers
  defaultClassReplicaCount: 3

  # Safer for our platform build:
  # deleting a PVC doesn't immediately delete underlying storage
  reclaimPolicy: Retain

  # Let replicas spread across nodes
  defaultDataLocality: disabled

  # Use stable V1 Longhorn data engine
  dataEngine: v1

service:
  ui:
    type: ClusterIP
EOF
```

Longhorn's StorageClass default replica count is `3`, and it attempts to distribute replicas across different nodes/disks. ([Longhorn][4])

### Architecture

With a 10 Gi PVC:

```text
                   Kubernetes PVC
                       10 Gi
                         │
                    StorageClass
                     "longhorn"
                         │
                  Longhorn Volume
                         │
          ┌──────────────┼──────────────┐
          │              │              │
          ▼              ▼              ▼
    Worker-01        Worker-02       Worker-03
 /mnt/longhorn    /mnt/longhorn   /mnt/longhorn
    Replica           Replica          Replica
     10 Gi             10 Gi            10 Gi
```

So remember:

> **10 Gi Kubernetes volume ≈ 30 Gi raw replicated storage**

with `numberOfReplicas: 3`.

For this 3-worker platform, that's exactly the HA behavior we want.

---

## 5. Install Longhorn

```bash
helm repo add longhorn https://charts.longhorn.io
helm repo update
```

Check version:

```bash
helm search repo longhorn/longhorn
```

Then:

```bash
helm upgrade --install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace \
  --version 1.12.1 \
  -f longhorn-values.yaml \
  --wait
```

This follows the current Longhorn Helm installation path. ([Longhorn][1])

---

## 6. Verify pods

```bash
kubectl get pods -n longhorn-system -o wide
```

You should eventually see things such as:

```text
longhorn-manager
longhorn-ui
longhorn-driver-deployer
longhorn-csi-plugin
csi-attacher
csi-provisioner
csi-resizer
csi-snapshotter
instance-manager
```

Everything should become:

```text
Running
```

Also:

```bash
kubectl get ds -n longhorn-system
kubectl get deploy -n longhorn-system
```

---

## 7. Verify the StorageClass

This is the part you're installing Longhorn for:

```bash
kubectl get storageclass
```

Expected:

```text
NAME                 PROVISIONER          RECLAIMPOLICY   VOLUMEBINDINGMODE
longhorn (default)   driver.longhorn.io   Retain          Immediate
```

Get full configuration:

```bash
kubectl get sc longhorn -o yaml
```

You should see:

```yaml
provisioner: driver.longhorn.io

parameters:
  numberOfReplicas: "3"
  fsType: ext4
```

Longhorn documents `numberOfReplicas` as the StorageClass parameter that determines replica redundancy. ([Longhorn][4])

---

## 8. Check for another default StorageClass

Run:

```bash
kubectl get sc
```

If you somehow have:

```text
local-path (default)
longhorn   (default)
```

don't leave two defaults.

Remove default status from the old SC:

```bash
kubectl patch storageclass local-path \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
```

Then:

```bash
kubectl get sc
```

Only:

```text
longhorn (default)
```

should remain default.

---

# 9. Test dynamic provisioning

Create a PVC:

```bash
cat > longhorn-test.yaml <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: longhorn-test
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 5Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: longhorn-test
spec:
  containers:
    - name: test
      image: busybox:1.36
      command:
        - sh
        - -c
        - |
          echo "Longhorn storage working" > /data/test.txt
          sleep 36000
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: longhorn-test
EOF

kubectl apply -f longhorn-test.yaml
```

Check:

```bash
kubectl get pvc
kubectl get pv
kubectl get pod -o wide
```

Expected:

```text
NAME            STATUS   VOLUME       CAPACITY   ACCESS MODES   STORAGECLASS
longhorn-test   Bound    pvc-xxxxx    5Gi        RWO            longhorn
```

Then:

```bash
kubectl exec longhorn-test -- cat /data/test.txt
```

Expected:

```text
Longhorn storage working
```

At that point the chain is working:

```text
Application
    │
    ▼
PVC
    │
    ▼
StorageClass: longhorn
    │
    ▼
Longhorn CSI Provisioner
    │
    ▼
Longhorn Volume
    │
    ├── Replica → Worker 1 → /mnt/longhorn
    ├── Replica → Worker 2 → /mnt/longhorn
    └── Replica → Worker 3 → /mnt/longhorn
```

### One thing I would **not** do yet

Don't expose the Longhorn UI through Gateway API yet. First get:

```bash
kubectl get pods -n longhorn-system
kubectl get sc
kubectl get pvc
```

completely healthy.

Then we can expose:

```text
https://longhorn.killa.io
        ↓
Gateway API
        ↓
HTTPRoute
        ↓
longhorn-frontend
```

using your **Envoy Gateway + cert-manager CA** setup. That will also give us a nice real workload to validate the Gateway API/TLS stack you just built.

[1]: https://longhorn.io/docs/1.12.1/deploy/install/install-with-helm/?utm_source=chatgpt.com "Longhorn | Documentation"
[2]: https://longhorn.io/docs/1.12.1/advanced-resources/os-distro-specific/csi-on-k3s/?utm_source=chatgpt.com "Longhorn | Documentation"
[3]: https://github.com/longhorn/longhorn/blob/master/chart/values.yaml?utm_source=chatgpt.com "longhorn/chart/values.yaml at master · longhorn/longhorn · GitHub"
[4]: https://longhorn.io/docs/1.12.1/references/storage-class-parameters/?utm_source=chatgpt.com "Longhorn | Documentation"
