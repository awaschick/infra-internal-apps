#!/bin/bash

source "$(dirname "$0")/common.sh"

pod_name="$1"
namespace_arg="$2"
namespace="$namespace_arg"

if [ -z "$pod_name" ]; then
  echo "Usage: make k8s-monitor <pod-name> [namespace]"
  echo "Example: make k8s-monitor cloudwatch-agent-g58hs"
  echo "Example: make k8s-monitor cloudwatch-agent-g58hs kube-system"
  exit 1
fi

if [ -z "$namespace" ]; then
  matching_namespaces=$(kubectl get pods --all-namespaces --kubeconfig="$KUBECONFIG" -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\n"}{end}' | awk -v pod="$pod_name" '$2 == pod {print $1}')
  match_count=$(echo "$matching_namespaces" | awk 'NF' | wc -l | tr -d ' ')

  if [ "$match_count" -eq 0 ]; then
    echo "Error: No pod named '$pod_name' found in any namespace."
    exit 1
  fi

  if [ "$match_count" -gt 1 ]; then
    echo "Error: Pod name '$pod_name' exists in multiple namespaces:"
    echo "$matching_namespaces" | awk 'NF {printf "  - %s\n", $1}'
    echo "Specify a namespace explicitly: make k8s-monitor $pod_name <namespace>"
    exit 1
  fi

  namespace=$(echo "$matching_namespaces" | awk 'NF {print $1; exit}')
fi

printf "\n${div}\n Streaming logs for pod '%s' in namespace '%s' on cluster '%s'\n${div}\n\n" "$pod_name" "$namespace" "$cluster_selection"
printf "kubectl logs -f -n %s %s --kubeconfig=%s\n\n" "$namespace" "$pod_name" "$KUBECONFIG"

kubectl logs -f -n "$namespace" "$pod_name" --kubeconfig="$KUBECONFIG"
