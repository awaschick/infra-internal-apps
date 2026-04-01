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

printf "\n${div}\n Doris PV Usage (cluster: %s, namespace: %s)\n${div}\n\n" "$cluster_selection" "$namespace"

printf "kubectl get pvc -n %s --kubeconfig=%s\n" "$namespace" "$KUBECONFIG"
kubectl get pvc -n "$namespace" --kubeconfig="$KUBECONFIG" \
  -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,CAPACITY:.status.capacity.storage,REQUEST:.spec.resources.requests.storage,STORAGECLASS:.spec.storageClassName,VOLUME:.spec.volumeName,AGE:.metadata.creationTimestamp"

pods=$(kubectl get pods -n "$namespace" --kubeconfig="$KUBECONFIG" \
  --field-selector=status.phase=Running \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
  | awk '/(^|-)fe-[0-9]+$|(^|-)be-[0-9]+$|(^|-)cn-[0-9]+$/')

if [ -z "$pods" ]; then
  echo
  echo "No running Doris FE/BE/CN pods found in namespace '$namespace'."
  exit 0
fi

echo
printf "%-45s %-35s %-20s %-8s %-8s %-8s %-6s\n" "POD" "MOUNT" "FILESYSTEM" "SIZE" "USED" "AVAIL" "USE%"
printf "%-45s %-35s %-20s %-8s %-8s %-8s %-6s\n" \
  "---------------------------------------------" \
  "-----------------------------------" \
  "--------------------" \
  "--------" "--------" "--------" "------"

for pod in $pods; do
  mount_paths="/opt/apache-doris/be/storage /opt/apache-doris/be/log /opt/apache-doris/fe/doris-meta /opt/apache-doris/fe/storage /opt/apache-doris/fe/log"

  if [[ "$pod" =~ (^|-)be-[0-9]+$ ]]; then
    mount_paths="${mount_paths} /opt/apache-doris/be/storage/spill"
  fi

  for path in $mount_paths; do
    result=$(kubectl exec -n "$namespace" "$pod" --kubeconfig="$KUBECONFIG" -- sh -c \
      "if [ -d '$path' ]; then df -h '$path' | awk 'NR==2 {print \$1\" \"\$2\" \"\$3\" \"\$4\" \"\$5}'; fi" 2>/dev/null)
    if [ -n "$result" ]; then
      filesystem=$(echo "$result" | awk '{print $1}')
      size=$(echo "$result" | awk '{print $2}')
      used=$(echo "$result" | awk '{print $3}')
      avail=$(echo "$result" | awk '{print $4}')
      usepct=$(echo "$result" | awk '{print $5}')
      printf "%-45s %-35s %-20s %-8s %-8s %-8s %-6s\n" \
        "$pod" "$path" "$filesystem" "$size" "$used" "$avail" "$usepct"
    fi
  done
done

echo
echo "Tip: pass an explicit namespace with: make doris-pv-usage <namespace>"
