#!/bin/bash

source "$(dirname "$0")/common.sh"

namespace="${NAMESPACE}"
doris_cluster="${DORIS_CLUSTER:-doris}"

if [ -z "$namespace" ]; then
  namespace="$1"
fi

if [ -z "$namespace" ]; then
  namespace=$(set_local_config "doris" "kubernetes-namespace")
fi

if [ -z "$namespace" ]; then
  echo "Error: Doris namespace is not configured."
  echo "Set config/doris/kubernetes-namespace or pass namespace explicitly."
  exit 1
fi

section() {
  echo
  printf "%s\n %s\n%s\n" "$div" "$1" "$div"
}

section "Doris Recovery Status (cluster: ${cluster_selection}, namespace: ${namespace})"
echo "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"

section "DorisCluster Resources"
if kubectl get dorisclusters -n "$namespace" --kubeconfig="$KUBECONFIG" >/dev/null 2>&1; then
  kubectl get dorisclusters -n "$namespace" --kubeconfig="$KUBECONFIG"
  if ! kubectl get doriscluster "$doris_cluster" -n "$namespace" --kubeconfig="$KUBECONFIG" >/dev/null 2>&1; then
    first_cluster=$(kubectl get dorisclusters -n "$namespace" --kubeconfig="$KUBECONFIG" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$first_cluster" ]; then
      echo
      echo "Requested DORIS_CLUSTER='${doris_cluster}' not found. Using '${first_cluster}' for detailed status."
      doris_cluster="$first_cluster"
    fi
  fi

  if kubectl get doriscluster "$doris_cluster" -n "$namespace" --kubeconfig="$KUBECONFIG" >/dev/null 2>&1; then
    echo
    echo "Detailed status for DorisCluster '${doris_cluster}':"
    kubectl get doriscluster "$doris_cluster" -n "$namespace" --kubeconfig="$KUBECONFIG" -o yaml \
      | awk '/^status:/{flag=1} flag{print}'
  fi
else
  echo "DorisCluster CRD/resource not found in namespace '${namespace}'."
fi

section "StatefulSets"
kubectl get statefulsets -n "$namespace" --kubeconfig="$KUBECONFIG" -o wide 2>/dev/null \
  | awk 'NR==1 || /doris|fe|be|cn|broker/'

section "Pods (Wide)"
kubectl get pods -n "$namespace" --kubeconfig="$KUBECONFIG" -o wide \
  | awk 'NR==1 || /(^|-)fe-[0-9]+$|(^|-)be-[0-9]+$|(^|-)cn-[0-9]+$|(^|-)broker-[0-9]+$/'

section "Pods (Readiness, Restarts, Start Time)"
kubectl get pods -n "$namespace" --kubeconfig="$KUBECONFIG" \
  -o custom-columns="NAME:.metadata.name,READY:.status.containerStatuses[*].ready,PHASE:.status.phase,RESTARTS:.status.containerStatuses[*].restartCount,START_TIME:.status.startTime,NODE:.spec.nodeName" \
  | awk 'NR==1 || /(^|-)fe-[0-9]+$|(^|-)be-[0-9]+$|(^|-)cn-[0-9]+$|(^|-)broker-[0-9]+$/'

section "Services and Endpoints"
kubectl get svc -n "$namespace" --kubeconfig="$KUBECONFIG" -o wide 2>/dev/null | awk 'NR==1 || /doris|fe|be|cn|broker/'
echo
kubectl get endpoints -n "$namespace" --kubeconfig="$KUBECONFIG" 2>/dev/null | awk 'NR==1 || /doris|fe|be|cn|broker/'

section "Recent Namespace Events (latest 60)"
kubectl get events -n "$namespace" --kubeconfig="$KUBECONFIG" --sort-by=.lastTimestamp 2>/dev/null | tail -n 60

section "Recent Doris Pod Warnings (latest 40)"
kubectl get events -n "$namespace" --kubeconfig="$KUBECONFIG" --sort-by=.lastTimestamp \
  -o custom-columns="TIME:.lastTimestamp,TYPE:.type,OBJECT:.involvedObject.name,REASON:.reason,MESSAGE:.message" 2>/dev/null \
  | awk 'NR==1 || ($2=="Warning" && ($3 ~ /fe-|be-|cn-|broker-/ || $3 ~ /doris/))' \
  | tail -n 40

section "FE HTTP Probe (/api/show_proc)"
fe_pods=$(kubectl get pods -n "$namespace" --kubeconfig="$KUBECONFIG" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
  | awk '/(^|-)fe-[0-9]+$/' | sort)

if [ -z "$fe_pods" ]; then
  echo "No FE pods found."
else
  fe_probe_pod=$(echo "$fe_pods" | head -n 1)
  echo "Using FE pod '${fe_probe_pod}' for frontend/backend membership probes."
  echo
  echo "[frontends]"
  kubectl exec -n "$namespace" "$fe_probe_pod" --kubeconfig="$KUBECONFIG" -- sh -c \
    'if command -v curl >/dev/null 2>&1; then curl -m 5 -fsS "http://127.0.0.1:8030/api/show_proc?path=/frontends"; elif command -v wget >/dev/null 2>&1; then wget -T 5 -qO- "http://127.0.0.1:8030/api/show_proc?path=/frontends"; else echo "No curl/wget in FE container."; fi' \
    2>/dev/null || echo "Failed to query /frontends from FE pod."
  echo
  echo "[backends]"
  kubectl exec -n "$namespace" "$fe_probe_pod" --kubeconfig="$KUBECONFIG" -- sh -c \
    'if command -v curl >/dev/null 2>&1; then curl -m 5 -fsS "http://127.0.0.1:8030/api/show_proc?path=/backends"; elif command -v wget >/dev/null 2>&1; then wget -T 5 -qO- "http://127.0.0.1:8030/api/show_proc?path=/backends"; else echo "No curl/wget in FE container."; fi' \
    2>/dev/null || echo "Failed to query /backends from FE pod."
fi

section "Quick Follow-Up Commands"
echo "make doris-recovery-status ${namespace}"
echo "make k8s-status"
echo "make doris-pv-usage ${namespace}"
