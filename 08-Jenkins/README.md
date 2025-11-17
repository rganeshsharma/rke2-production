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
---

kubectl apply -f jenkins-01-serviceAccount.yaml


# Step 3: Create 'jenkins-02-volume.yaml' and copy the following persistent volume manifest if you dont have a storage class avialable 
---
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
---
# Important Note: Replace 'worker-node01' with any one of your cluster worker nodes hostname.

# You can get the worker node hostname using the kubectl.

kubectl get nodes


# In our case since we already have the Longhorn storage class available we can simply define pvc: jenkins-pvc.yaml
---
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
---
kubectl apply -f jenkins-pvc.yaml
# When you apply this PVC, Longhorn will automatically:
# Create the PersistentVolume
# Provision the storage across your cluster nodes
# Bind the PV to this PVC

# You can verify the automatic PV creation after applying:
Kubectl get pv,pvc -n devops-tools

# Step 4: Create a Deployment file named 'jenkins-03-deployment.yaml' and copy the following deployment manifest.
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jenkins
  namespace: devops-tools
spec:
  replicas: 1
  selector:
    matchLabels:
      app: jenkins-server
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: jenkins-server
    spec:
      securityContext:
            # Note: fsGroup may be customized for a bit of better
            # filesystem security on the shared host
            fsGroup: 1000
            runAsUser: 1000
            ### runAsGroup: 1000
      serviceAccountName: jenkins-admin
      containers:
        - name: jenkins
          image: jenkins/jenkins:lts
          # OPTIONAL: check for new floating-tag LTS releases whenever the pod is restarted:
          imagePullPolicy: Always
          resources:
            limits:
              memory: "2Gi"
              cpu: "1000m"
            requests:
              memory: "500Mi"
              cpu: "500m"
          ports:
            - name: httpport
              containerPort: 8080
            - name: jnlpport
              containerPort: 50000
          livenessProbe:
            httpGet:
              path: "/login"
              port: 8080
            initialDelaySeconds: 90
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 5
          readinessProbe:
            httpGet:
              path: "/login"
              port: 8080
            initialDelaySeconds: 60
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 3
          volumeMounts:
            - name: jenkins-data
              mountPath: /var/jenkins_home
      volumes:
        - name: jenkins-data
          persistentVolumeClaim:
              claimName: jenkins-pv-claim
---
# Create the deployment using kubectl.
kubectl apply -f jenkins-03-deployment.yaml

# Check the deployment status.
kubectl get deployments -n devops-tools

# Now, you can get the deployment details using the following command.
kubectl describe deployments --namespace=devops-tools

# Step 5: Create 'jenkins-04-service.yaml' and copy the following service manifest:
---
apiVersion: v1
kind: Service
metadata:
  name: jenkins-service
  namespace: devops-tools
  annotations:
      prometheus.io/scrape: 'true'
      prometheus.io/path:   /
      prometheus.io/port:   '8080'
spec:
  selector:
    app: jenkins-server
  type: ClusterIP
  ports:
    - port: 8080
      targetPort: 8080
      name: http
---

kubectl apply -f jenkins-04-service.yaml

# Step 6 : Create an Ingress resource to expose the service now 
# NOTE : Since we don't have a domain we are not using cert-manager to create certs and SSL re-direct here 

---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: jenkins-ingress
  namespace: devops-tools
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  ingressClassName: nginx
  rules:
  - host: jenkins.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: jenkins-service
            port:
              number: 8080

kubectl apply -f jenkins-ingress.yaml
```

## **To access Jenkins:**
## Add to your Mac's `/etc/hosts`:
## <your metallb external ip>  jenkins.local

## Unlock Jenkins 

```bash
cat /var/jenkins_home/secrets/initialAdminPassword
```
