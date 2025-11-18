# cert-manager

cert-manager is a Kubernetes addon to automate the management and issuance of
TLS certificates from various issuing sources.

It will ensure certificates are valid and up to date periodically, and attempt
to renew certificates at an appropriate time before expiry.

## Prerequisites

- Kubernetes 1.22+

## Installing the Chart

Full installation instructions, including details on how to configure extra
functionality in cert-manager can be found in the [installation docs](https://cert-manager.io/docs/installation/kubernetes/).

Before installing the chart, you must first install the cert-manager CustomResourceDefinition resources.
This is performed in a separate step to allow you to easily uninstall and reinstall cert-manager without deleting your installed custom resources.

```bash
$ kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.18.2/cert-manager.crds.yaml
```

To install the chart with the release name `cert-manager`:

```console
# Add the Jetstack Helm repository
helm repo add jetstack https://charts.jetstack.io --force-update

# Install the cert-manager helm chart
helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.19.1 \
  --set crds.enabled=true
```

In order to begin issuing certificates, you will need to set up a ClusterIssuer
or Issuer resource (for example, by creating a 'letsencrypt-staging' issuer).

More information on the different types of issuers and how to configure them
can be found in [our documentation](https://cert-manager.io/docs/configuration/).

For information on how to configure cert-manager to automatically provision
Certificates for Ingress resources, take a look at the
[Securing Ingresses documentation](https://cert-manager.io/docs/usage/ingress/).

> **Tip**: List all releases using `helm list`

## Upgrading the Chart

Special considerations may be required when upgrading the Helm chart, and these
are documented in our full [upgrading guide](https://cert-manager.io/docs/installation/upgrading/).

**Please check here before performing upgrades!**

## Uninstalling the Chart

To uninstall/delete the `cert-manager` deployment:

```console
$ helm delete cert-manager --namespace cert-manager
```

The command removes all the Kubernetes components associated with the chart and deletes the release.

If you want to completely uninstall cert-manager from your cluster, you will also need to
delete the previously installed CustomResourceDefinition resources:

```console
$ kubectl delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.18.2/cert-manager.crds.yaml
```

## Create a Self Signed certificate 
## NOTE: If you own a domain and have DNS hosted zone access then simply use lets encrypt for getting and signing the certificate

```bash
# Step 1: Create Self-Signed CA Issuer
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: root-ra
  namespace: cert-manager
spec:
  isCA: true
  commonName: root-ra
  secretName: root-ra-secret
  privateKey:
    algorithm: ECDSA
    size: 256
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
    group: cert-manager.io
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: ca-issuer
spec:
  ca:
    secretName: root-ra-secret

# Step 2: Update any values.yaml for example let's take longhorn

ingress:
  enabled: true
  ingressClassName: nginx
  host: longhorn.local
  tls: true
  secureBackends: false
  tlsSecret: longhorn-tls
  path: /
  pathType: Prefix
  annotations:
    cert-manager.io/cluster-issuer: "ca-issuer"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"

# NOTE: If you apply this configuration you do not need to create a separate Ingress resource definition.

# Step 3: Upgrade Longhorn Helm Release
# Upgrade Longhorn with new ingress settings
helm upgrade longhorn longhorn/longhorn \
  --namespace longhorn-system \
  -f longhorn-values.yaml

# Step 4: Verify Certificate Creation
# List all certificates across namespaces
kubectl get certificate -A

# Check certificate status
kubectl get certificate longhorn-tls -n longhorn-system -o yaml

# View certificate details
kubectl describe certificate longhorn-tls -n longhorn-system

# Check the secret contents
kubectl get secret longhorn-tls -n longhorn-system -o yaml

# Test HTTPS connection
curl -v https://longhorn.local
curl -v https://jenkins.local

# Visual Flow

Step 1: selfsigned-issuer (ClusterIssuer)
   ↓
   Creates self-signed CA certificate
   ↓
Step 2: root-ra (Certificate) stored in root-ra-secret
   ↓
Step 3: ca-issuer (ClusterIssuer) references root-ra-secret
   ↓
Step 4: Service ingresses use ca-issuer annotation
   ↓
   All service certificates signed by the same trusted CA

# Troubleshooting: If certificates don't get issued:

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager -f

# Check certificate request
kubectl get certificaterequest -n longhorn-system
kubectl describe certificaterequest -n longhorn-system

# Check certificate order (if using ACME)
kubectl get order -n longhorn-system

# If you see "certificate not ready":
# Delete and recreate certificate
kubectl delete certificate longhorn-tls -n longhorn-system

# Trigger recreation by updating ingress
kubectl annotate ingress longhorn-ingress -n longhorn-system cert-manager.io/issue-temporary-certificate="true"
```