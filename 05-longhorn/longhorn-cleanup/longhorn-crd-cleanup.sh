# Get all Longhorn CRDs and delete them with finalizer removal
kubectl get crd | grep longhorn | awk '{print $1}' | while read crd; do
  echo "Deleting CRD: $crd"
  # Remove finalizers first
  kubectl patch crd $crd -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
  # Then delete
  kubectl delete crd $crd --force --grace-period=0 2>/dev/null || true
done