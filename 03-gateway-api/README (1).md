# Kubernetes Gateway API — RKE2 Production Platform

> Repository path: `rke-prod/gateway-api/`
>
> Scope: Shared Gateway API CRDs, multiple Gateway controller implementations, GatewayClasses, Gateway resources, TLS integration, and HTTPRoute usage.
>
> Current platform baseline:
> - RKE2
> - MetalLB for `LoadBalancer` addresses
> - cert-manager for TLS certificate lifecycle
> - Internal development DNS zone: `*.dev.killa.io`
> - Envoy Gateway as the first Gateway API implementation
> - Traefik planned as an additional Gateway API implementation
> - Gateway API Standard Channel pinned to `v1.5.1` while Envoy Gateway `v1.8.x` is in use

---

## 1. Introduction

Kubernetes Gateway API is the successor to the Kubernetes Ingress API for modern north-south and, increasingly, east-west traffic management.

Gateway API separates infrastructure ownership from application routing by introducing independent resources for:

- the controller implementation (`GatewayClass`),
- the traffic entry point (`Gateway`), and
- application routing (`HTTPRoute`, `GRPCRoute`, `TLSRoute`, and others).

This separation allows multiple Gateway implementations to coexist in the same Kubernetes cluster without forcing application teams to use controller-specific Ingress annotations.

For this platform, the intended model is:

```text
                       Corporate / Internal Network
                                  |
                                  v
                           Internal DNS
                  *.dev.killa.io -> Gateway VIP
                                  |
                                  v
                              MetalLB
                                  |
                                  v
                     LoadBalancer Service / VIP
                                  |
                                  v
                         Gateway Data Plane
                   Envoy Proxy or Traefik Proxy
                                  |
                                  v
                             Gateway
                                  |
                     +------------+------------+
                     |            |            |
                     v            v            v
                 HTTPRoute    HTTPRoute    HTTPRoute
                  Argo CD       Harbor       Grafana
                     |            |            |
                     v            v            v
                 ClusterIP    ClusterIP    ClusterIP
                  Service      Service      Service
                     |            |            |
                     v            v            v
                    Pods         Pods         Pods
```

The Gateway controller is the **control plane**. The proxy/load balancer created or managed by that controller is the **data plane** that carries user traffic.

---

## 2. Why move from Ingress to Gateway API?

Kubernetes Ingress remains a stable API, but its feature set is frozen. New Kubernetes networking capabilities are being developed through Gateway API.

Ingress works well for basic HTTP/HTTPS exposure, but advanced behavior usually depends on implementation-specific annotations.

Typical Ingress example:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  rules:
    - host: api.dev.killa.io
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: api
                port:
                  number: 8080
```

The problem is that the behavior represented by annotations is not portable. Moving from NGINX to Traefik or Envoy may require rewriting those annotations and may expose implementation differences.

Gateway API moves many common networking behaviors into structured Kubernetes API fields.

### Ingress vs Gateway API

| Capability | Ingress | Gateway API |
|---|---|---|
| API status | Stable but frozen | Actively developed |
| Primary HTTP resource | `Ingress` | `HTTPRoute` |
| Infrastructure entry point | Mostly implicit/controller-owned | Explicit `Gateway` |
| Controller selection | `IngressClass` | `GatewayClass` |
| Multi-team ownership | Limited | First-class role-oriented model |
| Shared load balancer | Controller-specific behavior | Explicit Gateway model |
| Host routing | Yes | Yes |
| Path routing | Yes | Yes |
| Header matching | Usually annotations/CRDs | Native HTTPRoute field |
| Query parameter matching | Usually controller-specific | Native HTTPRoute field |
| HTTP method matching | Usually controller-specific | Native HTTPRoute field |
| Weighted traffic splitting | Usually annotations/CRDs | Native backend weights |
| Request header modification | Usually annotations | Native filter |
| Response header modification | Usually annotations | Standard/extended filter |
| Redirects | Usually annotations | Native filter |
| URL rewrites | Usually annotations | Standard/extended filter |
| Request mirroring | Usually controller-specific | Standard/extended filter |
| CORS | Usually annotations/middleware | Standard/extended filter |
| Request/backend timeouts | Usually annotations | HTTPRoute timeout fields |
| Cross-namespace routing | Awkward/controller-specific | Explicit `allowedRoutes` and `ReferenceGrant` |
| TLS termination | Ingress TLS block | Gateway listener |
| Multiple implementations in one cluster | Possible | Explicitly modeled with multiple GatewayClasses |
| Protocol expansion | Primarily HTTP/HTTPS | HTTP, gRPC, TLS and additional L4/L7 route types |
| Extension model | Heavy annotation usage | Structured fields, policies and extension references |

### Migration principle

The architectural shift is:

```text
Ingress model
=============

IngressClass
     |
     v
Ingress
(TLS + hostname + path + backend + annotations)
     |
     v
Service


Gateway API model
=================

GatewayClass
     |
     v
Gateway
(listener + port + TLS + allowed route ownership)
     |
     v
HTTPRoute
(hostname + match + filter + backend)
     |
     v
Service
```

The biggest improvement is ownership separation:

```text
Platform Team
-------------
Gateway API CRDs
Gateway controller
GatewayClass
Gateway
TLS listener
MetalLB integration
cert-manager integration
Gateway policies

Application Team
----------------
Deployment
Service
HTTPRoute
Application-specific routing rules
```

---

## 3. Core Architecture Components

### 3.1 Gateway API CRDs

Gateway API is delivered as Kubernetes CRDs. The CRDs are **cluster-wide** and shared by every Gateway API controller.

Do **not** install one Gateway API CRD bundle for Envoy and another for Traefik.

The repository owns one pinned Gateway API CRD version.

For the current Envoy Gateway `v1.8.x` deployment, use Gateway API `v1.5.1` Standard Channel.

The Standard bundle includes the stable/standard Gateway API resources applicable to the selected version, including resources such as:

```text
GatewayClass
Gateway
HTTPRoute
GRPCRoute
TLSRoute
ReferenceGrant
BackendTLSPolicy
ListenerSet
```

This README focuses on `HTTPRoute` for now.

### 3.2 GatewayClass

`GatewayClass` is cluster-scoped and identifies the controller responsible for Gateways created from that class.

Examples:

```text
GatewayClass/envoy
     -> Envoy Gateway controller

GatewayClass/traefik
     -> Traefik controller
```

A cluster can have multiple GatewayClasses simultaneously.

### 3.3 Gateway

A `Gateway` is the actual traffic entry-point configuration.

It defines:

- which `GatewayClass` implements it,
- requested addresses,
- listeners,
- listener ports,
- protocols,
- listener hostnames,
- TLS termination,
- which namespaces/routes may attach.

Creating a Gateway commonly causes the implementation to provision or configure data-plane infrastructure.

For Envoy Gateway on this on-prem platform, that means an Envoy Proxy data plane and a Kubernetes `LoadBalancer` Service that receives a MetalLB VIP.

### 3.4 HTTPRoute

`HTTPRoute` defines how HTTP requests arriving through a Gateway are matched, processed, and sent to Kubernetes backends.

It supports:

- hostname matching,
- path matching,
- HTTP header matching,
- query parameter matching,
- HTTP method matching,
- redirects,
- URL rewrites,
- request/response header manipulation,
- weighted traffic splitting,
- request mirroring,
- CORS,
- request/backend timeouts,
- implementation-specific extension filters.

### 3.5 MetalLB

MetalLB provides `LoadBalancer` IP addresses in the on-prem environment.

Example allocation strategy:

```text
192.168.10.200 -> Envoy shared Gateway
192.168.10.201 -> Traefik shared Gateway
192.168.10.202 -> Reserved
192.168.10.203 -> Reserved
192.168.10.204 -> Reserved
192.168.10.205 -> Reserved
```

Do not configure Envoy and Traefik to independently claim the same VIP.

### 3.6 cert-manager

cert-manager owns certificate issuance and renewal.

For HTTPS termination:

```text
ClusterIssuer/killa-ca-issuer
        |
        v
Certificate / generated certificate request
        |
        v
Secret/dev-killa-wildcard-tls
        |
        v
Gateway HTTPS listener
        |
        v
TLS terminates at Gateway data plane
```

`HTTPRoute` normally does not contain TLS certificates.

### 3.7 Backend Services

Applications normally remain:

```yaml
spec:
  type: ClusterIP
```

The shared Gateway data plane is the external entry point. Individual application Services normally do **not** need `LoadBalancer` or `NodePort`.

---

## 4. Repository Structure

Recommended repository layout:

```text
rke-prod/
└── gateway-api/
    ├── README.md
    │
    ├── crds/
    │   └── v1.5.1/
    │       └── standard-install.yaml
    │
    ├── envoy/
    │   ├── README.md
    │   ├── values.yaml
    │   ├── gatewayclass.yaml
    │   ├── gateway.yaml
    │   ├── certificate.yaml
    │   └── policies/
    │
    └── traefik/
        ├── README.md
        ├── values.yaml
        ├── gatewayclass.yaml
        ├── gateway.yaml
        ├── certificate.yaml
        └── policies/
```

Use `envoy/`, not `rnvoy/`.

Application HTTPRoutes should normally live with the applications themselves rather than inside this platform directory:

```text
rke-prod/
├── gateway-api/
│   ├── envoy/
│   └── traefik/
│
├── argocd/
│   └── httproute.yaml
│
├── harbor/
│   └── httproute.yaml
│
├── longhorn/
│   └── httproute.yaml
│
└── monitoring/
    └── grafana-httproute.yaml
```

This preserves the ownership model:

```text
gateway-api/  -> platform-owned shared networking infrastructure
app/          -> app-owned Service + HTTPRoute
```

---

## 5. Version Strategy

Gateway API CRDs are shared by all implementations, so the CRD version must be compatible with every installed controller.

Current baseline:

```text
Gateway API:     v1.5.1 Standard Channel
Envoy Gateway:   v1.8.x (built against Gateway API v1.5.1)
Traefik:         add later as second implementation
```

Traefik releases available in August 2026 support newer Gateway API releases, including v1.6.1. That is **not** a reason to upgrade the shared cluster CRDs while Envoy Gateway v1.8.x remains pinned to v1.5.1. The shared CRD version should follow the compatibility intersection of all active controllers.

The latest Gateway API release may be newer than the version supported by a controller already running in the cluster.

Therefore:

1. Pin the Gateway API CRDs.
2. Check every installed Gateway controller's compatibility/conformance before upgrading the CRDs.
3. Upgrade controllers first when required.
4. Upgrade the shared Gateway API CRDs only after compatibility is established.
5. Prefer the Standard Channel for production.
6. Do not enable Experimental Channel merely to access features that are not currently required.

---

## 6. Gateway API CRD Installation

### 6.1 Vendor the CRDs into Git

Store the official Gateway API `v1.5.1` Standard bundle as:

```text
rke-prod/gateway-api/crds/v1.5.1/standard-install.yaml
```

Then install it from the repository:

```bash
cd rke-prod/gateway-api

kubectl apply --server-side \
  -f crds/v1.5.1/standard-install.yaml
```

Using a vendored, pinned manifest is preferred over installing an unpinned remote `latest` manifest.

### 6.2 Verify the CRDs

```bash
kubectl get crd | grep gateway.networking.k8s.io
```

Verify the bundle version:

```bash
kubectl get crd gateways.gateway.networking.k8s.io \
  -o go-template='version={{ index .metadata.annotations "gateway.networking.k8s.io/bundle-version" }} channel={{ index .metadata.annotations "gateway.networking.k8s.io/channel" }}{{ "\n" }}'
```

Expected baseline:

```text
version=v1.5.1 channel=standard
```

### 6.3 CRD lifecycle rule

Controller Helm charts must not independently take ownership of the shared Gateway API CRDs.

Conceptually:

```text
crds/v1.5.1/
     |
     +---- Gateway API CRDs installed ONCE
     |
     +---- Envoy controller watches them
     |
     +---- Traefik controller watches them
```

For controller-specific CRDs, such as Envoy Gateway's `gateway.envoyproxy.io` resources, keep those under the controller's own lifecycle.

---

## 7. Multiple GatewayClasses

### 7.1 Envoy GatewayClass

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: envoy
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
```

### 7.2 Traefik GatewayClass

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: traefik
spec:
  controllerName: traefik.io/gateway-controller
```

### 7.3 Verify both classes

```bash
kubectl get gatewayclass
```

Expected conceptual output:

```text
NAME      CONTROLLER
--------  ---------------------------------------------
envoy     gateway.envoyproxy.io/gatewayclass-controller
traefik   traefik.io/gateway-controller
```

Each controller should only reconcile GatewayClasses whose `controllerName` it owns.

---


### Traefik Helm ownership note

When Traefik is added, enable its Gateway API provider but avoid letting the Helm chart create platform-owned `GatewayClass` and `Gateway` objects if those objects are managed in this repository. A controller-specific values file should follow the intent below (verify exact chart keys against the pinned chart version):

```yaml
providers:
  kubernetesGateway:
    enabled: true

gatewayClass:
  enabled: false

gateway:
  enabled: false
```

Then manage `GatewayClass/traefik` and `Gateway/traefik-shared-gateway` explicitly from Git. This avoids Helm ownership conflicts and makes the Envoy/Traefik topology symmetrical.

## 8. How an HTTPRoute Chooses Envoy or Traefik

An `HTTPRoute` does **not** reference a `GatewayClass` directly.

The relationship is:

```text
HTTPRoute
    |
    | parentRefs
    v
Gateway
    |
    | spec.gatewayClassName
    v
GatewayClass
    |
    | spec.controllerName
    v
Controller
```

Example using Envoy:

```text
HTTPRoute/api
     |
     v
Gateway/envoy-shared-gateway
     |
     v
GatewayClass/envoy
     |
     v
Envoy Gateway
```

Example using Traefik:

```text
HTTPRoute/api
     |
     v
Gateway/traefik-shared-gateway
     |
     v
GatewayClass/traefik
     |
     v
Traefik
```

A Route may technically contain multiple `parentRefs` and attach to multiple Gateways, which can be useful for migration/testing. Use that deliberately; the normal production pattern is one intended shared Gateway per environment/traffic domain.

---

## 9. Recommended Development Gateway

For the development environment:

```text
DNS zone:        *.dev.killa.io
Envoy VIP:       192.168.10.200
TLS Secret:      dev-killa-wildcard-tls
ClusterIssuer:   killa-ca-issuer
```

Example:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: envoy-shared-gateway
  namespace: gateway-system
spec:
  gatewayClassName: envoy

  addresses:
    - type: IPAddress
      value: 192.168.10.200

  listeners:
    - name: http
      protocol: HTTP
      port: 80
      hostname: "*.dev.killa.io"
      allowedRoutes:
        namespaces:
          from: Selector
          selector:
            matchLabels:
              gateway-access: enabled

    - name: https
      protocol: HTTPS
      port: 443
      hostname: "*.dev.killa.io"
      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            name: dev-killa-wildcard-tls
      allowedRoutes:
        namespaces:
          from: Selector
          selector:
            matchLabels:
              gateway-access: enabled
```

Label namespaces that are allowed to expose Routes:

```bash
kubectl label namespace argocd gateway-access=enabled
kubectl label namespace harbor gateway-access=enabled
kubectl label namespace longhorn-system gateway-access=enabled
kubectl label namespace monitoring gateway-access=enabled
```

For a lab/POC, this can be relaxed to:

```yaml
allowedRoutes:
  namespaces:
    from: All
```

For production, prefer `Selector`.

---

## 10. TLS Model

With:

```yaml
tls:
  mode: Terminate
```

TLS terminates at the Gateway data plane.

```text
Client
   |
   | HTTPS
   v
Gateway / Envoy Proxy
   |
   | TLS terminated here
   |
   | HTTP or separately configured backend TLS
   v
ClusterIP Service
   |
   v
Pod
```

`HTTPRoute` normally carries no certificate.

The Gateway listener references the certificate Secret:

```yaml
tls:
  mode: Terminate
  certificateRefs:
    - kind: Secret
      name: dev-killa-wildcard-tls
```

There are two valid cert-manager ownership models. Choose **one**, not both:

### Option A — annotation-driven certificate generation

Add the issuer annotation to the Gateway and let cert-manager derive the Certificate from the HTTPS listener:

```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: killa-ca-issuer
```

When using this mode, do not separately create a conflicting Certificate with the same Secret ownership.

### Option B — explicit Certificate resource (recommended for GitOps)

Keep certificate intent explicit in Git and let the Gateway only reference the resulting Secret:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: dev-killa-wildcard-tls
  namespace: gateway-system
spec:
  secretName: dev-killa-wildcard-tls
  dnsNames:
    - "dev.killa.io"
    - "*.dev.killa.io"
  issuerRef:
    name: killa-ca-issuer
    kind: ClusterIssuer
    group: cert-manager.io
```

Keep the Gateway and its TLS Secret in the same namespace unless cross-namespace certificate references are intentionally required.

---

# 11. HTTPRoute — Complete Practical Configuration Guide

The high-level structure is:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: example
  namespace: application
spec:
  parentRefs: []
  hostnames: []
  rules:
    - name: optional-rule-name
      matches: []
      filters: []
      backendRefs: []
      timeouts: {}
```

For Gateway API `v1.5.1` Standard Channel, the primary configurable HTTPRoute areas are:

```text
spec.parentRefs
spec.hostnames
spec.rules[].name
spec.rules[].matches
spec.rules[].filters
spec.rules[].backendRefs
spec.rules[].timeouts
```

Some additional fields such as retry, session persistence, and native external-auth configuration are Experimental in this API generation and should not be treated as part of the production Standard-channel baseline.

---

## 11.1 `parentRefs`

`parentRefs` determines where the Route attaches.

Typical cross-namespace Gateway attachment:

```yaml
parentRefs:
  - name: envoy-shared-gateway
    namespace: gateway-system
    sectionName: https
```

Full practical shape:

```yaml
parentRefs:
  - group: gateway.networking.k8s.io
    kind: Gateway
    name: envoy-shared-gateway
    namespace: gateway-system
    sectionName: https
```

Fields:

| Field | Purpose |
|---|---|
| `group` | API group of the parent; normally omitted for a Gateway |
| `kind` | Parent kind; normally `Gateway` |
| `name` | Gateway name |
| `namespace` | Gateway namespace; defaults to Route namespace when omitted |
| `sectionName` | Gateway listener name, e.g. `https` |
| `port` | Select listener(s) by port where supported; generally prefer `sectionName` |

Recommended:

```yaml
sectionName: https
```

This is clearer than coupling the Route directly to a numeric listener port.

### Attach to more than one Gateway

Useful during migration/testing:

```yaml
parentRefs:
  - name: envoy-shared-gateway
    namespace: gateway-system
    sectionName: https

  - name: traefik-shared-gateway
    namespace: gateway-system
    sectionName: https
```

Use this intentionally because both controllers may then serve the Route.

---

## 11.2 `hostnames`

Hostnames match the HTTP `Host` header / HTTP2 `:authority` semantics exposed through Gateway API.

Single hostname:

```yaml
hostnames:
  - api.dev.killa.io
```

Multiple hostnames:

```yaml
hostnames:
  - api.dev.killa.io
  - api-v2.dev.killa.io
```

Wildcard hostname:

```yaml
hostnames:
  - "*.dev.killa.io"
```

The Route hostname must intersect with the Gateway listener hostname.

Example:

```text
Gateway listener: *.dev.killa.io
HTTPRoute:        grafana.dev.killa.io
Result:           valid hostname intersection
```

---

## 11.3 `rules[].name`

A rule can have a unique name:

```yaml
rules:
  - name: api-v1
    backendRefs:
      - name: api-v1
        port: 8080
```

Named rules improve readability and can be useful when policies or operational tooling need to identify a specific rule.

---

# 12. HTTPRoute Matching

A rule can match by:

```text
Path
Headers
Query parameters
HTTP method
```

Multiple properties **inside one match are ANDed**.

Multiple entries under `matches` are **ORed**.

Example:

```yaml
matches:
  - path:
      type: PathPrefix
      value: /api
    headers:
      - name: x-version
        value: v2

  - path:
      type: PathPrefix
      value: /v2/api
```

This means:

```text
(path starts /api AND x-version=v2)
OR
(path starts /v2/api)
```

---

## 12.1 Path matching

### PathPrefix

```yaml
matches:
  - path:
      type: PathPrefix
      value: /api
```

Matches:

```text
/api
/api/
/api/users
/api/orders/10
```

### Exact

```yaml
matches:
  - path:
      type: Exact
      value: /health
```

Matches only the exact path.

### RegularExpression

```yaml
matches:
  - path:
      type: RegularExpression
      value: '^/api/v[0-9]+/'
```

`RegularExpression` is implementation-specific. Regex syntax and support can differ between Envoy, Traefik, or other implementations. Avoid it when a portable `Exact` or `PathPrefix` rule is sufficient.

---

## 12.2 Header matching

Exact header match:

```yaml
matches:
  - headers:
      - type: Exact
        name: x-environment
        value: canary
```

Multiple headers in the same match are ANDed:

```yaml
matches:
  - headers:
      - name: x-environment
        value: canary
      - name: x-api-version
        value: v2
```

Regular-expression header matching exists as implementation-specific behavior:

```yaml
matches:
  - headers:
      - type: RegularExpression
        name: x-version
        value: '^v[0-9]+$'
```

Prefer exact matches for portability.

---

## 12.3 Query parameter matching

```yaml
matches:
  - queryParams:
      - name: version
        value: v2
```

Example request:

```text
GET /api?version=v2
```

Multiple query parameters in one match are ANDed.

Exact query matching is the portable baseline. Regex query matching is implementation-specific.

---

## 12.4 HTTP method matching

```yaml
matches:
  - method: POST
    path:
      type: PathPrefix
      value: /v1/chat/completions
```

Supported method values include:

```text
GET
HEAD
POST
PUT
DELETE
CONNECT
OPTIONS
TRACE
PATCH
```

Useful for routing API read/write operations differently when required.

---

# 13. HTTPRoute Filters

Filters process a matched request or response.

Gateway API `v1.5.1` Standard-channel HTTPRoute filter types include:

```text
RequestHeaderModifier
ResponseHeaderModifier
RequestRedirect
URLRewrite
RequestMirror
CORS
ExtensionRef
```

Support levels differ. Core features should be portable; Extended and implementation-specific features must be checked against the selected Gateway controller's conformance/support matrix.

`RequestRedirect` and `URLRewrite` are mutually exclusive within the same rule.

---

## 13.1 RequestHeaderModifier

### Add headers

```yaml
filters:
  - type: RequestHeaderModifier
    requestHeaderModifier:
      add:
        - name: x-platform
          value: rke-prod
```

### Set/overwrite headers

```yaml
filters:
  - type: RequestHeaderModifier
    requestHeaderModifier:
      set:
        - name: x-forwarded-platform
          value: gateway-api
```

### Remove headers

```yaml
filters:
  - type: RequestHeaderModifier
    requestHeaderModifier:
      remove:
        - x-internal-debug
```

### Combined example

```yaml
filters:
  - type: RequestHeaderModifier
    requestHeaderModifier:
      add:
        - name: x-platform
          value: rke-prod
      set:
        - name: x-environment
          value: dev
      remove:
        - x-unsafe-header
```

---

## 13.2 ResponseHeaderModifier

```yaml
filters:
  - type: ResponseHeaderModifier
    responseHeaderModifier:
      add:
        - name: x-served-by
          value: gateway-api
      set:
        - name: x-environment
          value: dev
      remove:
        - server
```

Potential use cases:

- add security/diagnostic headers,
- remove backend-identifying headers,
- mark canary responses,
- normalize application response headers.

---

## 13.3 RequestRedirect

Redirect the client rather than forwarding the original request upstream.

### HTTP to HTTPS

```yaml
filters:
  - type: RequestRedirect
    requestRedirect:
      scheme: https
      statusCode: 301
```

### Redirect to another hostname

```yaml
filters:
  - type: RequestRedirect
    requestRedirect:
      scheme: https
      hostname: new-api.dev.killa.io
      statusCode: 302
```

### Redirect path

```yaml
filters:
  - type: RequestRedirect
    requestRedirect:
      path:
        type: ReplaceFullPath
        replaceFullPath: /new-path
      statusCode: 301
```

### Redirect prefix

```yaml
matches:
  - path:
      type: PathPrefix
      value: /old
filters:
  - type: RequestRedirect
    requestRedirect:
      path:
        type: ReplacePrefixMatch
        replacePrefixMatch: /new
      statusCode: 301
```

Redirect configuration can control:

```text
scheme
hostname
path
port
statusCode
```

Common supported redirect codes:

```text
301
302
303
307
308
```

---

## 13.4 URLRewrite

A rewrite is different from a redirect:

```text
Redirect
Client receives 3xx and makes a new request.

Rewrite
Client URL remains unchanged; Gateway modifies the upstream request.
```

### Replace path prefix

```yaml
matches:
  - path:
      type: PathPrefix
      value: /api
filters:
  - type: URLRewrite
    urlRewrite:
      path:
        type: ReplacePrefixMatch
        replacePrefixMatch: /
backendRefs:
  - name: api
    port: 8080
```

Request:

```text
/api/users
```

Backend receives:

```text
/users
```

### Replace full path

```yaml
filters:
  - type: URLRewrite
    urlRewrite:
      path:
        type: ReplaceFullPath
        replaceFullPath: /internal/health
```

### Rewrite hostname

```yaml
filters:
  - type: URLRewrite
    urlRewrite:
      hostname: internal-api.default.svc.cluster.local
```

Use hostname rewrites only when the backend actually requires a particular host authority.

---

## 13.5 RequestMirror

Mirror requests to another backend while ignoring the mirrored backend's response.

```yaml
filters:
  - type: RequestMirror
    requestMirror:
      backendRef:
        name: api-v2
        port: 8080
backendRefs:
  - name: api-v1
    port: 8080
```

Flow:

```text
Request
   |
   +------> api-v1 ----> response returned to client
   |
   +------> api-v2 ----> response discarded
```

Useful for:

- shadow testing,
- pre-production validation,
- model-serving comparisons,
- validating a new API implementation with real traffic.

Percentage/fraction-based mirroring is available where supported by the implementation and selected Gateway API version.

---

## 13.6 CORS

Gateway API `v1.5` promoted the HTTPRoute CORS filter into the Standard Channel, but CORS remains an Extended support feature and must be validated against the chosen implementation.

Example:

```yaml
filters:
  - type: CORS
    cors:
      allowOrigins:
        - "https://portal.dev.killa.io"
      allowCredentials: true
      allowMethods:
        - GET
        - POST
        - OPTIONS
      allowHeaders:
        - Authorization
        - Content-Type
      exposeHeaders:
        - x-request-id
      maxAge: 600
```

Available CORS configuration includes:

```text
allowOrigins
allowCredentials
allowMethods
allowHeaders
exposeHeaders
maxAge
```

Avoid broad wildcard CORS policies for authenticated applications unless they are explicitly required and security-reviewed.

---

## 13.7 ExtensionRef

Vendor-specific or implementation-specific functionality can be referenced through an extension resource.

Conceptual example:

```yaml
filters:
  - type: ExtensionRef
    extensionRef:
      group: example.io
      kind: CustomHTTPFilter
      name: my-filter
```

The actual `group`, `kind`, and behavior are implementation-specific.

Use `ExtensionRef` only when Gateway API's portable fields cannot represent the required functionality.

Do not rebuild the old Ingress annotation problem by making every Route depend heavily on controller-specific extension objects.

---

# 14. `backendRefs`

The normal backend is a Kubernetes Service.

```yaml
backendRefs:
  - name: api
    port: 8080
```

Full practical form:

```yaml
backendRefs:
  - group: ""
    kind: Service
    name: api
    namespace: application
    port: 8080
    weight: 100
```

Fields:

| Field | Purpose |
|---|---|
| `group` | API group; empty for core Kubernetes Service |
| `kind` | Usually `Service` |
| `name` | Backend object name |
| `namespace` | Defaults to HTTPRoute namespace |
| `port` | **Service port**, not container `targetPort` |
| `weight` | Relative traffic weight |
| `filters` | Backend-specific filters; implementation support varies |

### Important: Service port vs targetPort

Service:

```yaml
ports:
  - port: 80
    targetPort: 8080
```

HTTPRoute must reference:

```yaml
backendRefs:
  - name: api
    port: 80
```

Not `8080`.

---

# 15. Weighted Traffic Splitting / Canary

```yaml
rules:
  - backendRefs:
      - name: api-v1
        port: 8080
        weight: 90

      - name: api-v2
        port: 8080
        weight: 10
```

The weights are relative; they do not have to total exactly 100.

Examples:

```text
90 / 10 -> approximately 90% / 10%
9 / 1   -> approximately 90% / 10%
1 / 1   -> approximately 50% / 50%
```

Useful for:

- canary releases,
- blue/green transitions,
- model-version rollout,
- gradual platform migrations.

---

# 16. Header-Based Canary

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: api
  namespace: application
spec:
  parentRefs:
    - name: envoy-shared-gateway
      namespace: gateway-system
      sectionName: https

  hostnames:
    - api.dev.killa.io

  rules:
    - matches:
        - headers:
            - name: x-canary
              value: "true"
      backendRefs:
        - name: api-v2
          port: 8080

    - backendRefs:
        - name: api-v1
          port: 8080
```

Requests with:

```text
x-canary: true
```

go to `api-v2`; other requests go to `api-v1`.

---

# 17. Path-Based Microservice Routing

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: platform-api
  namespace: application
spec:
  parentRefs:
    - name: envoy-shared-gateway
      namespace: gateway-system
      sectionName: https

  hostnames:
    - api.dev.killa.io

  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /users
      backendRefs:
        - name: users-service
          port: 8080

    - matches:
        - path:
            type: PathPrefix
            value: /orders
      backendRefs:
        - name: orders-service
          port: 8080

    - matches:
        - path:
            type: PathPrefix
            value: /payments
      backendRefs:
        - name: payments-service
          port: 8080
```

---

# 18. HTTPRoute Timeouts

Timeouts are configured per rule.

```yaml
rules:
  - timeouts:
      request: 60s
      backendRequest: 30s
    backendRefs:
      - name: api
        port: 8080
```

### `request`

Maximum duration for the overall client request/response transaction as implemented by the Gateway.

### `backendRequest`

Maximum duration for an individual Gateway-to-backend request.

The backend request timeout must not exceed the overall request timeout.

Example for an LLM API where generation may take longer:

```yaml
timeouts:
  request: 10m
  backendRequest: 10m
```

Do not blindly apply normal web API timeouts to long-running inference requests.

A zero duration such as `0s` represents disabling the corresponding timeout where supported according to Gateway API semantics.

---

# 19. Cross-Namespace Backend References

Preferred model:

```text
HTTPRoute namespace == Service namespace
```

Example:

```text
namespace: argocd
HTTPRoute/argocd
Service/argocd-server
```

No extra permission object is required for the backend reference.

If an HTTPRoute in one namespace needs to reference a Service in another namespace, use `ReferenceGrant` in the **backend namespace**.

HTTPRoute:

```yaml
backendRefs:
  - name: shared-api
    namespace: backend
    port: 8080
```

ReferenceGrant in namespace `backend`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: ReferenceGrant
metadata:
  name: allow-frontend-route
  namespace: backend
spec:
  from:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      namespace: frontend

  to:
    - group: ""
      kind: Service
      name: shared-api
```

Use cross-namespace backend references only when the architecture truly requires them.

---

# 20. HTTP to HTTPS Redirect Pattern

Use a Route attached to the HTTP listener that redirects traffic to HTTPS.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: http-to-https
  namespace: gateway-system
spec:
  parentRefs:
    - name: envoy-shared-gateway
      sectionName: http

  hostnames:
    - "*.dev.killa.io"

  rules:
    - filters:
        - type: RequestRedirect
          requestRedirect:
            scheme: https
            statusCode: 301
```

Application Routes then attach to the `https` listener.

---

# 21. Basic Application HTTPRoute Template

Use this as the default template for applications:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: <APP-NAME>
  namespace: <APP-NAMESPACE>
spec:
  parentRefs:
    - name: envoy-shared-gateway
      namespace: gateway-system
      sectionName: https

  hostnames:
    - "<APP>.dev.killa.io"

  rules:
    - backendRefs:
        - name: <SERVICE-NAME>
          port: <SERVICE-PORT>
```

Example for Grafana:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: grafana
  namespace: monitoring
spec:
  parentRefs:
    - name: envoy-shared-gateway
      namespace: gateway-system
      sectionName: https

  hostnames:
    - grafana.dev.killa.io

  rules:
    - backendRefs:
        - name: grafana
          port: 80
```

DNS:

```text
grafana.dev.killa.io -> 192.168.10.200
```

Flow:

```text
Client
  |
  v
DNS
  |
  v
192.168.10.200
  |
  v
MetalLB
  |
  v
Envoy Proxy LoadBalancer Service
  |
  v
Gateway HTTPS Listener
  |
  v
HTTPRoute/grafana
  |
  v
Service/grafana :80
  |
  v
Grafana Pods
```

---

# 22. Experimental HTTPRoute Features

Gateway API contains newer HTTPRoute capabilities that may be Experimental depending on the selected Gateway API release/channel.

Examples in the `v1.5` API generation include:

```text
retry
sessionPersistence
ExternalAuth filter
```

Conceptual retry shape:

```yaml
retry:
  attempts: 3
  codes:
    - 500
    - 502
    - 503
    - 504
  backoff: 100ms
```

Do **not** add this to the production Standard-channel baseline unless:

1. the field exists in the installed CRDs,
2. the selected implementation explicitly supports it,
3. its stability level is acceptable,
4. the behavior has been tested.

Use implementation-specific policies where necessary rather than silently assuming every controller supports the same experimental feature.

---

# 23. Route Matching Precedence

When multiple Routes/rules can match a request, Gateway API defines precedence rules rather than leaving all conflict behavior to individual controller implementations.

In general, more specific matches win.

Conceptually:

```text
Exact path
   >
Longer PathPrefix
   >
less-specific PathPrefix
```

Additional method/header/query specificity is considered according to Gateway API matching rules.

Avoid intentionally overlapping Routes unless the precedence is clearly understood and documented.

---

# 24. Route Status and Troubleshooting

Gateway API resources expose status conditions. Always inspect them before debugging the application itself.

### GatewayClasses

```bash
kubectl get gatewayclass
kubectl describe gatewayclass envoy
kubectl describe gatewayclass traefik
```

Important condition:

```text
Accepted=True
```

### Gateways

```bash
kubectl get gateway -A
kubectl describe gateway envoy-shared-gateway -n gateway-system
```

Important conditions include:

```text
Accepted=True
Programmed=True
```

Check addresses:

```bash
kubectl get gateway envoy-shared-gateway -n gateway-system -o wide
```

### HTTPRoutes

```bash
kubectl get httproute -A
kubectl describe httproute <ROUTE> -n <NAMESPACE>
```

Important Route conditions:

```text
Accepted=True
ResolvedRefs=True
```

Common problems:

```text
Accepted=False
    -> wrong parentRef
    -> listener does not allow namespace
    -> hostname does not intersect listener hostname
    -> unsupported filter
    -> invalid rule

ResolvedRefs=False
    -> Service does not exist
    -> wrong Service port
    -> cross-namespace backend without ReferenceGrant
    -> referenced extension does not exist
```

### Backend validation

```bash
kubectl get svc -n <NAMESPACE>
kubectl get endpoints -n <NAMESPACE>
kubectl get endpointslice -n <NAMESPACE>
```

### DNS validation

```bash
nslookup api.dev.killa.io
```

Expected:

```text
api.dev.killa.io -> 192.168.10.200
```

### TLS validation

```bash
kubectl get certificate -A
kubectl get secret dev-killa-wildcard-tls -n gateway-system
kubectl describe certificate dev-killa-wildcard-tls -n gateway-system
```

---

# 25. Production Best Practices

## CRDs

- Install Gateway API CRDs once per cluster.
- Pin the Gateway API version.
- Prefer Standard Channel.
- Keep shared CRDs separate from controller Helm releases.
- Validate every controller before upgrading shared CRDs.

## GatewayClasses

- Create one clearly named class per implementation/profile.
- Use explicit names such as `envoy` and `traefik`.
- Do not rely on ambiguous default classes in production.

## Gateways

- Keep shared Gateways in a dedicated namespace such as `gateway-system`.
- Use explicit MetalLB VIP assignments where operationally appropriate.
- Use different VIPs for separate simultaneously active Gateway data planes.
- Terminate TLS at the shared Gateway unless end-to-end TLS is explicitly required.
- Prefer namespace selectors in `allowedRoutes` over `from: All`.

## HTTPRoutes

- Keep an application's HTTPRoute with the application's manifests.
- Keep the application's Service as `ClusterIP` unless there is a specific exception.
- Attach Routes to listener names using `sectionName`.
- Prefer exact and prefix matches over regex.
- Prefer portable Gateway API filters before implementation-specific extensions.
- Use weighted backends for controlled canary releases.
- Set explicit timeouts for APIs where implementation defaults are unsuitable.
- Treat long-running AI inference APIs differently from normal web APIs.

## TLS

- Let cert-manager own certificate renewal.
- Use the development wildcard certificate for `*.dev.killa.io` where appropriate.
- Include `dev.killa.io` separately if the apex development hostname is required.
- Keep the TLS Secret in the Gateway namespace unless there is a reason to use cross-namespace references.

## DNS

For Envoy development Gateway:

```text
argocd.dev.killa.io  -> 192.168.10.200
harbor.dev.killa.io  -> 192.168.10.200
grafana.dev.killa.io -> 192.168.10.200
api.dev.killa.io     -> 192.168.10.200
vllm.dev.killa.io    -> 192.168.10.200
```

The same VIP can serve many HTTPRoutes because Envoy routes by HTTP hostname/path after traffic reaches the Gateway.

---

# 26. Envoy and Traefik Coexistence Strategy

Recommended topology:

```text
                         Gateway API CRDs
                             v1.5.1
                                |
                +---------------+---------------+
                |                               |
                v                               v
      GatewayClass/envoy              GatewayClass/traefik
                |                               |
                v                               v
      Envoy Gateway controller          Traefik controller
                |                               |
                v                               v
      envoy-shared-gateway            traefik-shared-gateway
                |                               |
                v                               v
        192.168.10.200                    192.168.10.201
                |                               |
                +---------------+---------------+
                                |
                      ClusterIP Applications
```

This makes controller evaluation/migration straightforward.

Example migration:

```text
Phase 1
api.dev.killa.io -> 192.168.10.200 -> Envoy

Phase 2
Program/test equivalent Route on Traefik at 192.168.10.201

Phase 3
Switch DNS:
api.dev.killa.io -> 192.168.10.201

Phase 4
Observe and validate

Phase 5
Rollback DNS to 192.168.10.200 if required
```

This is cleaner than trying to make both controllers compete for one MetalLB VIP.

---

# 27. Ingress Migration Strategy

Do not migrate every Ingress blindly in one step.

Recommended process:

```text
1. Inventory existing Ingress objects
           |
           v
2. Inventory annotations/controller-specific behavior
           |
           v
3. Map portable functionality to Gateway API
           |
           v
4. Identify remaining implementation-specific features
           |
           v
5. Create Gateway + HTTPRoute equivalents
           |
           v
6. Validate on separate Gateway VIP
           |
           v
7. Switch DNS / traffic
           |
           v
8. Observe
           |
           v
9. Remove old Ingress after validation
```

Common mapping:

| Ingress | Gateway API |
|---|---|
| `IngressClass` | `GatewayClass` |
| Controller LoadBalancer | `Gateway` data plane |
| Ingress TLS | Gateway listener TLS |
| `rules.host` | `HTTPRoute.hostnames` |
| `paths` | `HTTPRoute.rules.matches.path` |
| Service backend | `HTTPRoute.rules.backendRefs` |
| rewrite annotations | `URLRewrite` |
| redirect annotations | `RequestRedirect` |
| header annotations | Header modifier filters |
| canary annotations | weighted backends / header matching |
| cross-namespace hacks | `allowedRoutes` / `ReferenceGrant` |

---

# 28. GitOps Ordering

When managed through Argo CD, use a dependency/order model equivalent to:

```text
1. Gateway API CRDs
        |
        v
2. Controller-specific CRDs
        |
        v
3. Gateway controllers
        |
        v
4. GatewayClasses
        |
        v
5. Gateways + Certificates
        |
        v
6. Application Services
        |
        v
7. HTTPRoutes
        |
        v
8. Controller-specific policies
```

CRDs must exist before controllers or GitOps applications attempt to create the corresponding custom resources.

---

# 29. Current Platform Decision

For this RKE2 platform:

```text
Gateway API version     = v1.5.1 Standard
Primary implementation = Envoy Gateway
Secondary evaluation   = Traefik
LoadBalancer provider   = MetalLB
TLS provider            = cert-manager
Development DNS         = *.dev.killa.io
Primary Envoy VIP       = 192.168.10.200
Application Services    = ClusterIP
```

The desired application exposure pattern is:

```text
Application Deployment
        |
        v
ClusterIP Service
        |
        v
HTTPRoute
        |
        v
Shared Gateway
        |
        v
Envoy / Traefik data plane
        |
        v
MetalLB VIP
        |
        v
Client
```

---

# 30. Future Additions

The next iterations of this repository should document:

- `GRPCRoute`
- `TLSRoute`
- `BackendTLSPolicy`
- end-to-end TLS to backend Services
- Envoy `BackendTrafficPolicy`
- Envoy `ClientTrafficPolicy`
- Envoy `SecurityPolicy`
- rate limiting
- authentication/authorization
- circuit breaking
- retries
- health checking
- observability and metrics
- access logging
- OpenTelemetry
- WAF/API security integration
- vLLM/SGLang inference routing
- AI Gateway patterns
- Traefik-specific policies/middleware mapping
- Gateway API conformance testing
- Ingress-to-Gateway migration automation

---

## Operational Summary

```text
Gateway API CRDs
    -> shared cluster API contract

GatewayClass
    -> selects implementation

Gateway
    -> creates/configures traffic entry point

HTTPRoute
    -> application routing configuration

MetalLB
    -> supplies on-prem LoadBalancer VIP

cert-manager
    -> supplies/renews TLS Secret

ClusterIP Service
    -> application backend
```

The central rule for this platform is:

> **Install Gateway API once, run multiple Gateway implementations when required, keep shared infrastructure in `gateway-api/`, and keep each application's HTTPRoute with that application.**
