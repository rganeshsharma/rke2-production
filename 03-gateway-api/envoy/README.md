# Envoy Architecture:
```
                    Internal DNS
                 *.dai.dev.mindsparks.io
                       |
                       v
              MetalLB VIP / LB IP
                       |
                       v
              Envoy Proxy Data Plane
                 :80       :443
                    \       /
                     Gateway
                        |
              +---------+---------+
              |                   |
          HTTPRoute           GRPCRoute
              |                   |
          Services         vLLM / APIs
              |
             Pods


Control plane:
Gateway API CRDs
       |
Envoy Gateway Controller
       |
creates/manages Envoy Proxy
```

## Prerequisites: 
https://gateway-api.sigs.k8s.io/guides/getting-started/introduction/?utm_source=chatgpt.com 
https://gateway.envoyproxy.io/v1.8/install/install-helm/ 


## Install Gateway API CRDs separately

This is an important production practice.
Don't let application teams, Envoy upgrades, or arbitrary Helm releases implicitly control fundamental cluster-wide CRDs.

```
Cluster lifecycle
     |
     +--- Gateway API CRDs
     +--- cert-manager CRDs
     +--- MetalLB CRDs
     |
Platform lifecycle
     |
     +--- Envoy Gateway
     +--- cert-manager controller
     +--- MetalLB controller
```

NOTE: Envoy Gateway v1.8 uses Gateway API v1.5.1, so pin that version.
Verify : https://gateway.envoyproxy.io/news/releases/matrix/ 

```bash
kubectl apply --server-side \
  -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml

# Standard Install of gateway API s provides following CRDs:
GatewayClass
Gateway
HTTPRoute
GRPCRoute
ReferenceGrant  

## Verify CRDs: 
kubectl get crd | grep gateway.networking.k8s.io

## Verify Bundle:
kubectl get crd gateways.gateway.networking.k8s.io \
  -o go-template='version={{ index .metadata.annotations "gateway.networking.k8s.io/bundle-version" }} channel={{ index .metadata.annotations "gateway.networking.k8s.io/channel" }}{{ "\n" }}'

## Expected output:
version=v1.5.1 channel=standard  
```
## Now Install Envoy Gateway API CRDs separately
```bash
helm template envoygateway-crds \
  oci://docker.io/envoyproxy/gateway-crds-helm \
  --version v1.8.3 \
  --set 'crds.gatewayAPI.enabled=false' \
  --set 'crds.envoyGateway.enabled=true' \
  | grep -v '^Pulled:' \
  | grep -v '^Digest:' \
  | kubectl apply --server-side -f -

# Verify:

kubectl get crd | grep gateway.envoyproxy.io

```
## Create the Envoy Gateway namespace

```bash
kubectl create namespace envoy-gateway-system

kubectl label namespace envoy-gateway-system \
  app.kubernetes.io/part-of=envoy-gateway

kubectl get ns envoy-gateway-system --show-labels
```

## Create production-style Envoy Gateway values

```bash
vi envoy-gateway-values.yaml
```
```yaml
deployment:
  replicas: 2

  envoyGateway:
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 1000m
        memory: 512Mi

podDisruptionBudget:
  minAvailable: 1

config:
  envoyGateway:
    logging:
      level:
        default: info

kubernetesClusterDomain: cluster.local

## NOTE: The controller is not the packet-forwarding data plane, so it doesn't need enormous resources.
```
## Architecture: 
          Envoy Gateway Controller
                  replicas=2
                       |
             watches Gateway API
                       |
                creates/configures
                       |
              Envoy Proxy Pods
                       |
                  actual traffic



## Install Envoy Gateway

```bash
helm upgrade --install eg \
  oci://docker.io/envoyproxy/gateway-helm \
  --version v1.8.3 \
  --namespace envoy-gateway-system \
  --set crds.enabled=false \
  -f envoy-gateway-values.yaml

# Verify:
kubectl get pods -n envoy-gateway-system -o wide


# Logs:
kubectl logs \
  -n envoy-gateway-system \
  deployment/envoy-gateway \
  --tail=100

```

## Create a new GatewayClass:

```bash
vi gatewayclass.yaml
```
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: envoy
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
```
```bash
kubectl apply -f gatewayclass.yaml
kubectl get gatewayclass
```
