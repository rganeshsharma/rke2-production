# Re-install ingress nginx once again to configure its service as type Load Balancer 

## By default rke2 installation comes with ClusterIp service type after we have deployed metallb with IPAddressPool and L2Advertisement now lets us reinstall ingress nginx once again 

```bash
# Step 1: Disable RKE2's Built-in NGINX
# On the master node, edit RKE2 config
sudo nano /etc/rancher/rke2/config.yaml

# Add this line 
disable:
  - rke2-ingress-nginx

# Simply Delete using Helm 
helm delete rke2-ingress-nginx -n kube-system

#Restart rke2 server
sudo systemctl restart rke2-server

# Wait for restart
kubectl get nodes
```

## Install new Ingress nginx now 

```bash
# Add NGINX Ingress repo
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Install with LoadBalancer service
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.service.externalTrafficPolicy=Local \
  --set controller.service.annotations."metallb\.universe\.tf/address-pool"=default-pool

# Should show LoadBalancer with EXTERNAL-IP
kubectl get svc -n ingress-nginx

```

## Comparison of Options

| Option | Pros | Cons | Recomemndation |
|------|----------|-----------|---------|
| Option 1 ✅ Simple<br>✅ No restart needed<br>✅ Keep existing config | ⚠️ Two services for same pods<br>⚠️ Slightly redundant | ✅ Best for quick setup ||
| Option 2 (HelmChartConfig) |✅ Clean<br>✅ RKE2 native<br>✅ Persistent across updates| ⚠️ RKE2 specific syntax<br>⚠️ May take time to reconcile| ✅ Best for RKE2 environments||
| Option 3 (Fresh install) | ✅ Full control<br>✅ Standard Helm chart<br>✅ Latest version| ❌ Requires restart<br>❌ Loses RKE2 integration<br>❌ More complex| ✅ What we followed in the guide ||