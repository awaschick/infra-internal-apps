#!/bin/bash

source "$(dirname "$0")/common.sh"

namespace="${NAMESPACE}"
if [ -z "$namespace" ]; then
  namespace="$1"
fi
if [ -z "$namespace" ]; then
  namespace=$(set_local_config "doris" "kubernetes-namespace")
fi

since="${SINCE}"
if [ -z "$since" ]; then
  since="$2"
fi
if [ -z "$since" ]; then
  since="5m"
fi

tail_lines="${TAIL_LINES:-200}"
query_id="${QID:-}"
memory_grep="${MEMORY_GREP:-MEM_LIMIT_EXCEEDED|OutOfMemory|OOMKilled|bad_alloc|std::bad_alloc|Cannot allocate memory|memory tracker limit exceeded|Allocator mem tracker check failed|PODArray reserve memory failed|ScopedPeakMem|exec_mem_limit|process memory used}"

if [ -z "$namespace" ]; then
  echo "Error: Doris namespace is not configured."
  echo "Set config/doris/kubernetes-namespace or pass namespace explicitly."
  exit 1
fi

echo
printf "%s\n Doris BE Log Memory Audit (cluster: %s, namespace: %s, since: %s)\n%s\n" "$div" "$cluster_selection" "$namespace" "$since" "$div"
echo "Pattern: ${memory_grep}"
if [ -n "$query_id" ]; then
  echo "QueryId filter: ${query_id}"
fi
echo

be_pods=$(kubectl get pods -n "$namespace" --kubeconfig="$KUBECONFIG" \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null \
  | awk '/(^|-)be-[0-9]+$/' | sort)

if [ -z "$be_pods" ]; then
  echo "No BE pods found in namespace '${namespace}'."
  exit 1
fi

total_matches=0
pod_hits=0

for pod in $be_pods; do
  echo "---- ${pod}"
  pod_matches=$(kubectl logs -n "$namespace" "$pod" -c be --kubeconfig="$KUBECONFIG" --since="$since" 2>/dev/null \
    | grep -E "$memory_grep" || true)

  if [ -n "$query_id" ]; then
    pod_matches=$(printf "%s\n" "$pod_matches" | grep "$query_id" || true)
  fi

  hit_count=$(printf "%s\n" "$pod_matches" | sed '/^$/d' | wc -l | tr -d ' ')
  if [ "$hit_count" -gt 0 ]; then
    pod_hits=$((pod_hits + 1))
    total_matches=$((total_matches + hit_count))
    printf "%s\n" "$pod_matches" | tail -n "$tail_lines"
  else
    echo "(no matches)"
  fi
  echo
done

printf "Summary: %s/%s BE pods had matches; total matched lines: %s\n" \
  "$pod_hits" "$(printf "%s\n" "$be_pods" | wc -l | tr -d ' ')" "$total_matches"

#if [ "$total_matches" -gt 0 ]; then
#  echo "Result: potential memory-exhaustion signals found."
#  exit 2
#else
#  echo "Result: no memory-exhaustion patterns found in BE logs for the selected window."
#fi

