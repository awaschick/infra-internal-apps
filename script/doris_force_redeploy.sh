#!/bin/bash

source "$(dirname "$0")/common.sh"

namespace="${NAMESPACE}"
auto_yes=0
wait_for_ready=1
group_pause_seconds="${GROUP_PAUSE_SECONDS:-0}"
requested_groups_raw="${DORIS_GROUPS:-${DORIS_GROUP:-${COMPONENTS:-${COMPONENT:-}}}}"

if [ "${AUTO_YES}" = "1" ] || [ "${FORCE}" = "1" ] || [ "${YES}" = "1" ]; then
  auto_yes=1
fi
if [ "${NO_WAIT}" = "1" ] || [ "${WAIT_READY}" = "0" ]; then
  wait_for_ready=0
fi

normalize_component() {
  local value
  value="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
  case "$value" in
    fe|frontend|frontends)
      echo "fe"
      ;;
    be|backend|backends)
      echo "be"
      ;;
    cn|compute|computenode|computenodes|compute-node|compute-nodes)
      echo "cn"
      ;;
    broker|brokers)
      echo "broker"
      ;;
    *)
      echo ""
      ;;
  esac
}

while [ "$#" -gt 0 ]; do
  arg="$1"
  shift
  case "$arg" in
    --yes|-y)
      auto_yes=1
      ;;
    --no-wait)
      wait_for_ready=0
      ;;
    --group=*)
      if [ -n "$requested_groups_raw" ]; then
        requested_groups_raw="${requested_groups_raw},${arg#*=}"
      else
        requested_groups_raw="${arg#*=}"
      fi
      ;;
    --group)
      if [ "$#" -eq 0 ]; then
        echo "Error: --group requires a value."
        exit 1
      fi
      if [ -n "$requested_groups_raw" ]; then
        requested_groups_raw="${requested_groups_raw},$1"
      else
        requested_groups_raw="$1"
      fi
      shift
      ;;
    *)
      if [ -z "$namespace" ]; then
        namespace="$arg"
      else
        echo "Usage: make doris-force-redeploy [namespace]"
        echo "or:    make doris-force-redeploy NAMESPACE=<namespace> DORIS_GROUP=<fe|be|cn|broker|frontend|backend|compute> FORCE=1 NO_WAIT=1 GROUP_PAUSE_SECONDS=10"
        echo "or:    make doris-force-redeploy [namespace] AUTO_YES=1"
        exit 1
      fi
      ;;
  esac
done

if ! [[ "$group_pause_seconds" =~ ^[0-9]+$ ]]; then
  echo "Error: GROUP_PAUSE_SECONDS must be a non-negative integer."
  exit 1
fi

requested_components=""
if [ -n "$requested_groups_raw" ]; then
  normalized_tokens=$(echo "$requested_groups_raw" | tr ',|' ' ')
  for token in $normalized_tokens; do
    [ -z "$token" ] && continue
    normalized_component="$(normalize_component "$token")"
    if [ -z "$normalized_component" ]; then
      echo "Error: Unknown Doris group '$token'."
      echo "Valid groups: fe, be, cn, broker (aliases: frontend, backend, compute)."
      exit 1
    fi
    case " $requested_components " in
      *" $normalized_component "*) ;;
      *) requested_components="$requested_components $normalized_component" ;;
    esac
  done
  requested_components="$(echo "$requested_components" | xargs)"
fi

if [ -z "$namespace" ]; then
  namespace=$(set_local_config "doris" "kubernetes-namespace")
fi

if [ -z "$namespace" ]; then
  echo "Error: Doris namespace is not configured."
  echo "Set config/doris/kubernetes-namespace or pass namespace explicitly."
  exit 1
fi

printf "\n${div}\n Doris Force Redeploy (cluster: %s, namespace: %s)\n${div}\n\n" "$cluster_selection" "$namespace"

pod_candidates=$(kubectl get pods -n "$namespace" --kubeconfig="$KUBECONFIG" \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
  | awk '/(^|-)fe-[0-9]+$|(^|-)be-[0-9]+$|(^|-)cn-[0-9]+$|(^|-)broker-[0-9]+$/')

if [ -z "$pod_candidates" ]; then
  echo "No Doris FE/BE/CN/Broker pods found in namespace '$namespace'."
  exit 0
fi

get_component_pods() {
  local component="$1"
  echo "$pod_candidates" \
    | awk -v comp="$component" '
        {
          name=$0
          n=split(name, parts, "-")
          ord=parts[n]
          pattern = "(^|-)" comp "-[0-9]+$"
          if (name ~ pattern && ord ~ /^[0-9]+$/) {
            printf "%s\t%s\n", ord, name
          }
        }' \
    | sort -t $'\t' -k1,1nr -k2,2 \
    | awk -F $'\t' '{print $2}'
}

has_later_groups() {
  local current="$1"
  local seen=0
  for c in $active_component_order; do
    if [ "$seen" -eq 1 ] && [ -n "$(get_component_pods "$c")" ]; then
      return 0
    fi
    if [ "$c" = "$current" ]; then
      seen=1
    fi
  done
  return 1
}

component_order="fe be cn broker"
active_component_order="$component_order"
if [ -n "$requested_components" ]; then
  active_component_order=""
  for component in $component_order; do
    case " $requested_components " in
      *" $component "*) active_component_order="$active_component_order $component" ;;
    esac
  done
  active_component_order="$(echo "$active_component_order" | xargs)"
fi

total_count=0

if [ -n "$requested_components" ]; then
  groups_display=$(echo "$active_component_order" | tr '[:lower:]' '[:upper:]' | sed 's/ / -> /g')
  echo "This will delete and recreate Doris pods one-by-one in this selected order:"
  echo "  ${groups_display} (each highest ordinal to lowest)"
else
  echo "This will delete and recreate Doris pods one-by-one in this order:"
  echo "  FE -> BE -> CN -> Broker (each highest ordinal to lowest)"
fi
echo

for component in $active_component_order; do
  component_pods=$(get_component_pods "$component")
  if [ -z "$component_pods" ]; then
    continue
  fi
  echo "[$(echo "$component" | tr '[:lower:]' '[:upper:]')]"
  echo "$component_pods" | awk '{printf "  - %s\n", $1}'
  count=$(echo "$component_pods" | awk 'NF' | wc -l | tr -d ' ')
  total_count=$((total_count + count))
  echo
done

if [ "$total_count" -eq 0 ]; then
  echo "No ordinal Doris FE/BE/CN/Broker pods found in namespace '$namespace'."
  exit 0
fi

if [ "$wait_for_ready" -eq 1 ]; then
  echo "Each pod will be waited on until it reports Ready before continuing."
else
  echo "NO_WAIT is enabled. Pods will be deleted without waiting for Ready."
fi
if [ "$group_pause_seconds" -gt 0 ]; then
  echo "A pause of ${group_pause_seconds}s will be applied between component groups."
fi
echo "This is intended for forcing Doris nodes to re-initialize with latest config."
echo

if [ "$auto_yes" -ne 1 ]; then
  read -r -p "Type REDEPLOY to continue: " confirm
  if [ "$confirm" != "REDEPLOY" ]; then
    echo "Cancelled."
    exit 1
  fi
fi

for component in $active_component_order; do
  component_pods=$(get_component_pods "$component")
  if [ -z "$component_pods" ]; then
    continue
  fi

  printf "\n%s\nRestarting %s pods...\n%s\n" "$div" "$(echo "$component" | tr '[:lower:]' '[:upper:]')" "$div"
  for pod in $component_pods; do
    printf "\nRestarting pod %s ...\n" "$pod"
    kubectl delete pod "$pod" -n "$namespace" --kubeconfig="$KUBECONFIG"
    if [ "$wait_for_ready" -eq 1 ]; then
      kubectl wait --for=condition=Ready "pod/$pod" -n "$namespace" --kubeconfig="$KUBECONFIG" --timeout=20m
    fi
  done

  if [ "$group_pause_seconds" -gt 0 ] && has_later_groups "$component"; then
    echo
    echo "Pausing ${group_pause_seconds}s before next component group..."
    sleep "$group_pause_seconds"
  fi
done

echo
echo "Doris force redeploy complete."
