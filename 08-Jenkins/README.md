# Setup Jenkins On Kubernetes:https://www.jenkins.io/doc/book/installing/kubernetes/ 

## 1st method : Single step installation 
## NOTE: Make sure you midify the required values for storage, service, resource and limits

```bash
# git clone and install directly
git clone https://github.com/scriptcamp/kubernetes-jenkins 

# Install using kubectl
kubectl apply -f kubernetes-jenkins/
```

## 2nd method : Manual installation 

```bash
# Step 1: Create a Namespace for Jenkins. It is good to categorize all the DevOps tools as a separate namespace from other applications.

kubectl create namespace devops-tools

# Step 2: Create a 'jenkins-01-serviceAccount.yaml' file and copy the following admin service account manifest.

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: jenkins-admin
rules:
  - apiGroups: [""]
    resources: ["*"]
    verbs: ["*"]
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: jenkins-admin
  namespace: devops-tools
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: jenkins-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: jenkins-admin
subjects:
- kind: ServiceAccount
  name: jenkins-admin
  namespace: devops-tools

kubectl apply -f jenkins-01-serviceAccount.yaml


# Step 3: Create 'jenkins-02-volume.yaml' and copy the following persistent volume manifest if you dont have a storage class avialable 

kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: local-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: jenkins-pv-volume
  labels:
    type: local
spec:
  storageClassName: local-storage
  claimRef:
    name: jenkins-pv-claim
    namespace: devops-tools
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  local:
    path: /mnt
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - worker-node01
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: jenkins-pv-claim
  namespace: devops-tools
spec:
  storageClassName: local-storage
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 3Gi

# Important Note: Replace 'worker-node01' with any one of your cluster worker nodes hostname.

# You can get the worker node hostname using the kubectl.

kubectl get nodes


# In our case since we already have the Longhorn storage class available we can simply define pvc:

apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: jenkins-pv-claim
  namespace: devops-tools
spec:
  storageClassName: longhorn
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi

# When you apply this PVC, Longhorn will automatically:

# Create the PersistentVolume
# Provision the storage across your cluster nodes
# Bind the PV to this PVC

# You can verify the automatic PV creation after applying:







```
