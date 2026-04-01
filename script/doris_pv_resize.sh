#!/bin/bash

source "$(dirname "$0")/common.sh"

namespace_arg="$1"
namespace="$namespace_arg"

if [ -z "$namespace" ]; then
  namespace=$(set_local_config "doris" "kubernetes-namespace")
fi

if [ -z "$namespace" ]; then
  echo "Error: Doris namespace is not configured."
  echo "Set config/doris/kubernetes-namespace or pass namespace explicitly."
  exit 1
fi

be_size=$(set_local_config "doris" "back-end-storage-size")
fe_size=$(set_local_config "doris" "front-end-storage-size")

if [ -z "$be_size" ] || [ -z "$fe_size" ]; then
  echo "Error: Storage sizes are not configured."
  echo "Expected config values:"
  echo "  - doris/back-end-storage-size"
  echo "  - doris/front-end-storage-size"
  exit 1
fi

printf "\n${div}\n Doris PVC Resize (cluster: %s, namespace: %s)\n${div}\n\n" "$cluster_selection" "$namespace"
printf "Target sizes from config: BE=%s FE=%s\n\n" "$be_size" "$fe_size"

be_pvcs=$(kubectl get pvc -n "$namespace" --kubeconfig="$KUBECONFIG" -o name | sed 's#persistentvolumeclaim/##' | awk '/be-storage/')
fe_pvcs=$(kubectl get pvc -n "$namespace" --kubeconfig="$KUBECONFIG" -o name | sed 's#persistentvolumeclaim/##' | awk '/fe-meta/')

if [ -z "$be_pvcs" ] && [ -z "$fe_pvcs" ]; then
  echo "No Doris BE/FE PVCs found to resize."
  exit 0
fi

if [ -n "$be_pvcs" ]; then
  echo "Resizing BE PVCs:"
  for pvc in $be_pvcs; do
    printf "  - %s -> %s\n" "$pvc" "$be_size"
    read -r -p "    Apply this change? [y/N] " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      kubectl patch pvc "$pvc" -n "$namespace" --kubeconfig="$KUBECONFIG" \
        -p "{\"spec\":{\"resources\":{\"requests\":{\"storage\":\"${be_size}\"}}}}"
    else
      echo "    Skipped $pvc"
    fi
  done
  echo
fi

if [ -n "$fe_pvcs" ]; then
  echo "Resizing FE PVCs:"
  for pvc in $fe_pvcs; do
    printf "  - %s -> %s\n" "$pvc" "$fe_size"
    read -r -p "    Apply this change? [y/N] " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      kubectl patch pvc "$pvc" -n "$namespace" --kubeconfig="$KUBECONFIG" \
        -p "{\"spec\":{\"resources\":{\"requests\":{\"storage\":\"${fe_size}\"}}}}"
    else
      echo "    Skipped $pvc"
    fi
  done
  echo
fi

echo "Current PVC requested sizes:"
kubectl get pvc -n "$namespace" --kubeconfig="$KUBECONFIG" \
  -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,REQUEST:.spec.resources.requests.storage,CAPACITY:.status.capacity.storage" \
  | awk 'NR==1 || /be-storage|fe-meta/'

echo
echo "If any claim shows FileSystemResizePending, restart FE/BE pods one at a time."
echo "Use 'make doris-pv-usage' to verify filesystem size inside pods."
