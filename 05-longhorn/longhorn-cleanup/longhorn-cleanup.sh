#!/bin/bash
# Longhorn Complete Cleanup Script
# Save as: cleanup-longhorn.sh

set -e

echo "🧹 Starting Longhorn cleanup..."

# 1. Delete failed uninstall job
echo "1. Deleting failed uninstall job..."
kubectl delete job longhorn-uninstall -n longhorn --force --grace-period=0 2>/dev/null || echo "No uninstall job found"

# 2. Delete all pods in longhorn namespace
echo "2. Deleting all Longhorn pods..."
kubectl delete pods --all -n longhorn --force --grace-period=0 2>/dev/null || echo "No pods found"

# 3. Delete PVCs using Longhorn
echo "3. Deleting Longhorn PVCs..."
kubectl get pvc --all-namespaces -o json | jq -r '.items[] | select(.spec.storageClassName=="longhorn") | "\(.metadata.namespace) \(.metadata.name)"' | while read namespace name; do
  kubectl delete pvc $name -n $namespace --force --grace-period=0 2>/dev/null || true
done

# 4. Delete PVs using Longhorn
echo "4. Deleting Longhorn PVs..."
kubectl get pv -o json | jq -r '.items[] | select(.spec.storageClassName=="longhorn") | .metadata.name' | while read pv; do
  kubectl delete pv $pv --force --grace-period=0 2>/dev/null || true
done

# 5. Delete Longhorn CRDs
echo "5. Deleting Longhorn CRDs..."
kubectl get crd | grep longhorn | awk '{print $1}' | while read crd; do
  kubectl delete crd $crd --force --grace-period=0 2>/dev/null || true
done

# 6. Delete all resources in longhorn namespace
echo "6. Deleting all Longhorn resources..."
kubectl delete all --all -n longhorn --force --grace-period=0 2>/dev/null || echo "No resources found"

# 7. Delete namespace
echo "7. Deleting Longhorn namespace..."
kubectl delete namespace longhorn --force --grace-period=0 2>/dev/null || echo "Namespace already deleted"

# 8. Remove finalizers if namespace is stuck
echo "8. Removing finalizers from stuck namespace..."
kubectl patch namespace longhorn -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "Namespace not found or already clean"

# 9. Verify cleanup
echo "9. Verifying cleanup..."
echo "Remaining Longhorn resources:"
kubectl get all -n longhorn 2>/dev/null || echo "✅ Longhorn namespace is clean"
kubectl get pv | grep longhorn || echo "✅ No Longhorn PVs remaining"
kubectl get crd | grep longhorn || echo "✅ No Longhorn CRDs remaining"

echo "🎉 Longhorn cleanup completed!"