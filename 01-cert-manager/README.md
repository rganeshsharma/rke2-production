Yes. For your RKE2 platform, I would build this as a **private PKI + cert-manager + Traefik + Gateway API** stack.

Your current YAML is the correct *bootstrap idea*, but for production I would change the architecture slightly.

### Recommended architecture

```text
                    Private DNS
                  *.apps.killa.io
                         |
                         v
              Traefik / Gateway API
                  192.168.x.x VIP
                         |
              +----------+----------+
              |          |          |
           Argo CD     Harbor     Grafana
              |          |          |
              +----------+----------+
                         |
                    TLS Secrets
                         ^
                         |
                    cert-manager
                         |
                 ClusterIssuer
                         |
               Intermediate CA
                         |
                    Root CA
                         |
                 TRUSTED BY CLIENTS
```

For a POC, cert-manager can keep the Root CA and sign certificates directly. For production, I strongly recommend:

```text
Offline Root CA
      |
      | signs
      v
Intermediate CA
      |
      | cert-manager CA ClusterIssuer
      |
      +---- argocd.apps.killa.io
      +---- harbor.apps.killa.io
      +---- grafana.apps.killa.io
      +---- api.apps.killa.io
      +---- models.apps.killa.io
```

cert-manager itself warns that its `CA` issuer requires PKI planning around CA rotation, trust distribution and disaster recovery, and its CA private key lives in a Kubernetes Secret. ([cert-manager][1])

## 1. First: what does `killa.io` actually do?

The DNS domain and your CA are separate concepts.

Suppose your internal DNS contains:

```text
argocd.apps.killa.io     -> 192.168.64.50
harbor.apps.killa.io     -> 192.168.64.50
grafana.apps.killa.io    -> 192.168.64.50
api.apps.killa.io        -> 192.168.64.50
models.apps.killa.io     -> 192.168.64.50
```

`192.168.64.50` could be the VIP assigned to your Traefik `LoadBalancer` service using MetalLB.

Traefik receives:

```text
https://argocd.apps.killa.io
```

and routes it based on the hostname:

```text
argocd.apps.killa.io
        ↓
Gateway
        ↓
HTTPRoute
        ↓
argocd-server Service
```

cert-manager's role is simply to provide a certificate whose SAN contains:

```text
argocd.apps.killa.io
```

The DNS side must still resolve that name to your Traefik address.

One important point: **only use `killa.io` like this if you actually control the domain.** `.io` is a real public DNS namespace. For enterprise internal DNS, using a subdomain of a domain you own is cleaner:

```text
apps.killa.io
infra.killa.io
api.killa.io
models.killa.io
```

You can then use split-horizon DNS so these records exist only inside your network.

---

# 2. Your existing SelfSigned ClusterIssuer

This part is fine:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-bootstrap
spec:
  selfSigned: {}
```

But think of this only as:

```text
bootstrap tool
```

not:

```text
issuer applications should use
```

That is also the intended use documented by cert-manager: SelfSigned can bootstrap a CA, after which a `CA` issuer should perform normal certificate issuance. ([cert-manager][2])

---

# 3. Create your Root CA

For your POC, I would use something like this:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: killa-root-ca
  namespace: cert-manager
spec:
  isCA: true

  commonName: Killa Platform Root CA

  subject:
    organizations:
      - Killa
    organizationalUnits:
      - Platform Engineering

  secretName: killa-root-ca

  duration: 87600h       # 10 years
  renewBefore: 8760h     # 1 year

  privateKey:
    algorithm: ECDSA
    size: 384

  issuerRef:
    name: selfsigned-bootstrap
    kind: ClusterIssuer
    group: cert-manager.io
```

This gives you:

```text
Secret:
cert-manager/killa-root-ca
```

containing approximately:

```text
tls.crt
tls.key
ca.crt
```

cert-manager recommends specifying a proper subject DN when bootstrapping a SelfSigned CA because an empty issuer/subject DN can result in an invalid X.509 certificate under stricter validation. ([cert-manager][2])

---

# 4. Turn that Root CA into a real issuer

Now create:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: killa-ca
spec:
  ca:
    secretName: killa-root-ca
```

Because this is a `ClusterIssuer`, cert-manager looks for that Secret in its configured cluster-resource namespace, which defaults to:

```text
cert-manager
```

([cert-manager][3])

Now your architecture is:

```text
selfsigned-bootstrap
        |
        | creates
        v
Killa Root CA
        |
        | referenced by
        v
ClusterIssuer/killa-ca
        |
        | signs
        v
Application certificates
```

From this point onward **do not use `selfsigned-bootstrap` for applications.**

Applications use:

```yaml
issuerRef:
  name: killa-ca
  kind: ClusterIssuer
```

---

# 5. Issue a certificate for `argocd.apps.killa.io`

For example:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: argocd-tls
  namespace: argocd
spec:
  secretName: argocd-tls

  dnsNames:
    - argocd.apps.killa.io

  duration: 2160h
  renewBefore: 360h

  privateKey:
    algorithm: ECDSA
    size: 256
    rotationPolicy: Always

  usages:
    - digital signature
    - server auth

  issuerRef:
    name: killa-ca
    kind: ClusterIssuer
    group: cert-manager.io
```

cert-manager creates:

```text
argocd namespace

Secret:
argocd-tls
```

containing:

```text
tls.crt
tls.key
ca.crt
```

Now you have:

```text
Killa Root CA
    |
    +--- signs ---> argocd.apps.killa.io
```

---

# 6. Wildcard certificates are also possible

You could issue:

```yaml
dnsNames:
  - "*.apps.killa.io"
  - "apps.killa.io"
```

For example:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: platform-wildcard
  namespace: traefik
spec:
  secretName: platform-wildcard-tls

  dnsNames:
    - "*.apps.killa.io"
    - "apps.killa.io"

  privateKey:
    algorithm: ECDSA
    size: 256
    rotationPolicy: Always

  issuerRef:
    name: killa-ca
    kind: ClusterIssuer
```

Then:

```text
argocd.apps.killa.io       ✓
harbor.apps.killa.io       ✓
grafana.apps.killa.io      ✓
models.apps.killa.io       ✓
api.apps.killa.io          ✓
```

but:

```text
foo.dev.apps.killa.io      ✗
```

because a wildcard covers only one DNS level.

For production I normally prefer **individual certificates per application/Gateway** rather than one enormous wildcard secret. That reduces blast radius if one TLS private key is exposed.

---

# 7. The critical part: browsers still won't trust it automatically

This is where people often misunderstand private PKI.

cert-manager can issue:

```text
argocd.apps.killa.io
        |
       signed
        |
Killa Root CA
```

but your laptop initially knows nothing about:

```text
Killa Root CA
```

so Chrome will say:

```text
NET::ERR_CERT_AUTHORITY_INVALID
```

You need to install:

```text
Killa Root CA certificate
```

into the trust store of your organization.

For example:

```text
Windows machines
    ↓
Windows Trusted Root Certification Authorities

Linux servers
    ↓
OS CA trust store

macOS
    ↓
System Keychain

Java applications
    ↓
JVM truststore

Containers
    ↓
container CA bundle

Kubernetes workloads
    ↓
trust-manager
```

You distribute **only the public Root CA certificate**.

Never:

```text
root CA private key
```

---

# 8. This is where `trust-manager` becomes useful

cert-manager maintains the certificates.

`trust-manager` distributes trust.

The cert-manager project specifically recommends trust-manager for distributing private CA trust bundles across Kubernetes workloads. ([cert-manager][4])

Conceptually:

```text
                   cert-manager
                        |
                   Root CA cert
                        |
                        v
                  trust-manager
                        |
           +------------+-------------+
           |            |             |
           v            v             v
     namespace A   namespace B   namespace C

      ConfigMap      ConfigMap      ConfigMap
          |              |              |
          v              v              v
        Pods           Pods           Pods
```

For example:

```text
trust-bundle.pem
```

gets mounted into applications that need to trust your internal PKI.

This becomes especially useful for:

```text
ArgoCD -> GitLab
Application -> internal API
vLLM -> internal service
Prometheus -> HTTPS endpoint
Agent -> model endpoint
Harbor -> internal services
mTLS workloads
```

And cert-manager specifically cautions against simply mounting a serving certificate Secret's `ca.crt` everywhere as your trust mechanism because safe CA rotation requires overlapping old/new trust anchors. ([cert-manager][5])

---

# 9. Traefik is a good choice — but I would use Gateway API

Your understanding regarding ingress-nginx is current.

**Ingress NGINX was retired in March 2026.** There are no further bug fixes, releases or security patches, and Kubernetes explicitly recommends migration toward Gateway API or another maintained controller. ([Kubernetes][6])

So for this new cluster I would **not** design:

```text
Traefik
  +
Ingress
```

unless you have a compatibility requirement.

I'd design:

```text
Traefik
   +
Gateway API
```

Traefik's current Kubernetes Gateway provider supports the current Gateway API Standard implementation and native resources such as `Gateway`, `HTTPRoute`, `GRPCRoute`, `BackendTLSPolicy`, etc. ([Traefik Docs][7])

That lines up extremely well with the platform you're building.

---

# 10. Your production traffic architecture

For your cluster I'd build:

```text
                     Internal DNS
               *.apps.killa.io
                       |
                       |
               192.168.64.50
                 MetalLB VIP
                       |
                       v
              +----------------+
              |    TRAEFIK     |
              |  Gateway API   |
              +----------------+
                       |
          +------------+-------------+
          |            |             |
     HTTPRoute     HTTPRoute     HTTPRoute
          |            |             |
          v            v             v
       ArgoCD        Harbor        Grafana

      argocd.        harbor.       grafana.
     apps.killa.io  apps.killa.io apps.killa.io
```

Then separately:

```text
                   cert-manager
                        |
                ClusterIssuer
                  killa-ca
                        |
         +--------------+---------------+
         |              |               |
         v              v               v
  argocd-tls       harbor-tls      grafana-tls
```

And:

```text
Gateway
   |
certificateRefs:
   |
   +--- argocd-tls
```

---

# 11. Gateway API + cert-manager becomes very clean

You can even have cert-manager watch your Gateway.

For example:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: platform-gateway
  namespace: traefik
  annotations:
    cert-manager.io/cluster-issuer: killa-ca

spec:
  gatewayClassName: traefik

  listeners:

    - name: https-argocd
      hostname: argocd.apps.killa.io
      port: 443
      protocol: HTTPS

      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            name: argocd-tls

      allowedRoutes:
        namespaces:
          from: All
```

cert-manager sees:

```yaml
cert-manager.io/cluster-issuer: killa-ca
```

and:

```yaml
hostname: argocd.apps.killa.io
```

and can automatically create:

```text
Certificate/argocd-tls
        ↓
Secret/argocd-tls
```

cert-manager supports generating Certificates directly from annotated Gateway resources; the Gateway's listener hostname becomes the certificate DNS SAN and `certificateRefs` names the resulting Secret. ([cert-manager][8])

Traefik then reads that Secret from the Gateway listener for TLS termination. ([Traefik Docs][9])

That means you don't necessarily have to manually create every `Certificate` object.

---

# 12. Then HTTPRoute becomes application-owned

For ArgoCD:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: argocd
  namespace: argocd

spec:
  parentRefs:
    - name: platform-gateway
      namespace: traefik

  hostnames:
    - argocd.apps.killa.io

  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /

      backendRefs:
        - name: argocd-server
          port: 80
```

Now you get a very nice responsibility boundary:

```text
PLATFORM TEAM
----------------------------
GatewayClass
Gateway
Traefik
MetalLB
DNS
Root CA / Intermediate CA
cert-manager
trust-manager


APPLICATION TEAM
----------------------------
Service
Deployment
HTTPRoute
Certificate requirements
```

This is exactly one of the major architectural improvements Gateway API gives you over the old Ingress model.

---

# 13. But for PROD, introduce an Intermediate CA

Your current proposed architecture is:

```text
Root CA
   |
   +---- ArgoCD
   +---- Harbor
   +---- Grafana
   +---- vLLM
   +---- applications
```

I wouldn't do that for the final production environment.

Instead:

```text
              KILLA ROOT CA
             10-year validity
                     |
              OFFLINE / SECURED
                     |
                     | signs
                     v
          KILLA PLATFORM INTERMEDIATE
               2-5 year validity
                     |
             cert-manager Secret
                     |
             ClusterIssuer
                     |
       +-------------+-------------+
       |             |             |
       v             v             v
    ArgoCD         Harbor        Grafana
     90d            90d           90d
```

The key distinction is:

```text
ROOT PRIVATE KEY
       ✗ Kubernetes

INTERMEDIATE PRIVATE KEY
       ✓ Kubernetes
```

If cert-manager or the cluster is compromised, you revoke/replace the intermediate.

You don't need to rebuild your entire organizational trust anchor.

---

## The final design I would use for your platform

```text
DNS
================================================

apps.killa.io
    |
    +-- argocd.apps.killa.io
    +-- harbor.apps.killa.io
    +-- grafana.apps.killa.io
    +-- prometheus.apps.killa.io
    +-- models.apps.killa.io
    +-- api.apps.killa.io


NETWORK
================================================

Internal DNS
     |
     v
MetalLB VIP
     |
     v
Traefik


ROUTING
================================================

Traefik
   |
GatewayClass
   |
Gateway
   |
HTTPRoute / GRPCRoute / TLSRoute


PKI
================================================

Offline Root CA
      |
Intermediate Platform CA
      |
cert-manager ClusterIssuer
      |
Certificate
      |
Kubernetes TLS Secret
      |
Traefik Gateway


TRUST
================================================

Root CA
   |
trust-manager
   |
Kubernetes workloads

Root CA
   |
Enterprise trust distribution
   |
Laptops / Servers / Browsers
```

### So yes: your overall direction is solid

The one architectural change I'd make is **don't treat SelfSigned as your everyday issuer and don't use the Root CA directly for leaf signing in production**.

Your progression should be:

```text
POC

SelfSigned
    ↓
Root CA
    ↓
CA ClusterIssuer
    ↓
Certificates
```

Then your final production PKI:

```text
PROD

Offline Root CA
       ↓
Intermediate Platform CA
       ↓
cert-manager CA ClusterIssuer
       ↓
90-day leaf certificates
       ↓
Traefik Gateway API
       ↓
*.apps.killa.io
```

For the platform you're building, **Traefik + Gateway API + cert-manager + trust-manager + MetalLB + internal DNS** is the combination I'd choose rather than designing a new deployment around ingress-nginx. ([Kubernetes][6])

And this same CA architecture later gives you a clean foundation for **internal HTTPS, backend TLS and mTLS between AI platform components**, not merely browser certificates.

[1]: https://cert-manager.io/docs/configuration/ca/?utm_source=chatgpt.com "CA - cert-manager Documentation"
[2]: https://controller.cert-manager.io/docs/configuration/selfsigned/?utm_source=chatgpt.com "SelfSigned - cert-manager Documentation"
[3]: https://cert-manager.io/docs/configuration/?utm_source=chatgpt.com "Issuer Configuration - cert-manager Documentation"
[4]: https://cert-manager.io/docs/trust/trust-manager/?utm_source=chatgpt.com "trust-manager - cert-manager Documentation"
[5]: https://cert-manager.io/docs/faq/?utm_source=chatgpt.com "Frequently Asked Questions (FAQ) - cert-manager Documentation"
[6]: https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/?utm_source=chatgpt.com "Ingress NGINX Retirement: What You Need to Know | Kubernetes"
[7]: https://doc.traefik.io/traefik/providers/kubernetes-gateway/?utm_source=chatgpt.com "Traefik Kubernetes Gateway API Documentation - Traefik"
[8]: https://cert-manager.io/docs/usage/gateway/?utm_source=chatgpt.com "Annotated Gateway resource - cert-manager Documentation"
[9]: https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/gateway-api/?utm_source=chatgpt.com "Traefik Kubernetes Gateway - Traefik"
