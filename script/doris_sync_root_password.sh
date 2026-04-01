#!/bin/bash

source "$(dirname "$0")/common.sh"

namespace="${NAMESPACE}"
current_root_password="${CURRENT_ROOT_PASSWORD:-${CURRENT_PASSWORD}}"
auto_yes=0

if [ "${AUTO_YES}" = "1" ] || [ "${FORCE}" = "1" ] || [ "${YES}" = "1" ]; then
  auto_yes=1
fi

for arg in "$@"; do
  case "$arg" in
    --yes|-y)
      auto_yes=1
      ;;
    *)
      if [ -z "$namespace" ]; then
        namespace="$arg"
      else
        echo "Usage: make doris-sync-root-password [namespace]"
        echo "or:    make doris-sync-root-password NAMESPACE=<namespace> CURRENT_ROOT_PASSWORD='<current>' FORCE=1"
        exit 1
      fi
      ;;
  esac
done

if [ -z "$namespace" ]; then
  namespace=$(set_local_config "doris" "kubernetes-namespace")
fi

if [ -z "$namespace" ]; then
  echo "Error: Doris namespace is not configured."
  echo "Set config/doris/kubernetes-namespace or pass namespace explicitly."
  exit 1
fi

target_password=$(set_local_config "doris" "root-password")
if [ -z "$target_password" ]; then
  echo "Error: config value doris/root-password is empty."
  exit 1
fi

printf "\n%s\n Doris Root Password Sync (cluster: %s, namespace: %s)\n%s\n\n" "$div" "$cluster_selection" "$namespace" "$div"

fe_pods=$(kubectl get pods -n "$namespace" --kubeconfig="$KUBECONFIG" \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
  | awk '/(^|-)fe-[0-9]+$/' | sort)
if [ -z "$fe_pods" ]; then
  echo "Error: no FE pods found."
  exit 1
fi
probe_fe=$(echo "$fe_pods" | head -n 1)
echo "Using FE probe pod: ${probe_fe}"

escape_single_quotes() {
  printf "%s" "$1" | sed "s/'/'\"'\"'/g"
}

try_auth_on_probe() {
  local pass="$1"
  if [ -n "$pass" ]; then
    local esc_pass
    esc_pass=$(escape_single_quotes "$pass")
    kubectl exec -n "$namespace" "$probe_fe" --kubeconfig="$KUBECONFIG" -- \
      sh -c "mysql -h127.0.0.1 -P9030 -uroot -p'${esc_pass}' -e 'SELECT 1'" \
      1>/dev/null 2>/dev/null
    return $?
  fi
  kubectl exec -n "$namespace" "$probe_fe" --kubeconfig="$KUBECONFIG" -- \
    sh -c "mysql -h127.0.0.1 -P9030 -uroot -e 'SELECT 1'" \
    1>/dev/null 2>/dev/null
}

auth_mode=""
auth_password=""

if try_auth_on_probe "$target_password"; then
  auth_mode="target"
  auth_password="$target_password"
  echo "Current root authentication already matches configured target password."
elif [ -n "$current_root_password" ] && try_auth_on_probe "$current_root_password"; then
  auth_mode="current"
  auth_password="$current_root_password"
  echo "Authenticated with CURRENT_ROOT_PASSWORD; will sync to configured target password."
elif try_auth_on_probe ""; then
  auth_mode="empty"
  auth_password=""
  echo "Authenticated with empty root password; will sync to configured target password."
else
  echo "Error: could not authenticate as root on FE using:"
  echo "  1) configured target password"
  echo "  2) CURRENT_ROOT_PASSWORD (if provided)"
  echo "  3) empty password"
  echo
  echo "Provide the current FE root password and retry:"
  echo "  make doris-sync-root-password NAMESPACE=${namespace} CURRENT_ROOT_PASSWORD='<current-password>' FORCE=1"
  exit 1
fi

if [ "$auth_mode" = "target" ]; then
  echo "No password rotation needed. Proceeding with verification checks."
else
  echo
  echo "This will set Doris SQL user credentials to match config/doris/root-password."
  echo "  - root@'%'"
  echo "  - root@'localhost'"
  echo
  if [ "$auto_yes" -ne 1 ]; then
    read -r -p "Type SYNC to continue: " confirm
    if [ "$confirm" != "SYNC" ]; then
      echo "Cancelled."
      exit 1
    fi
  fi

  sql_target_password="${target_password//\'/\'\'}"
  sync_sql="
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '${sql_target_password}';
CREATE USER IF NOT EXISTS 'root'@'localhost' IDENTIFIED BY '${sql_target_password}';
ALTER USER 'root'@'%' IDENTIFIED BY '${sql_target_password}';
ALTER USER 'root'@'localhost' IDENTIFIED BY '${sql_target_password}';
GRANT ADMIN_PRIV ON *.*.* TO 'root'@'%';
GRANT NODE_PRIV ON *.*.* TO 'root'@'%';
"

  if [ -n "$auth_password" ]; then
    esc_auth_password=$(escape_single_quotes "$auth_password")
    if ! kubectl exec -i -n "$namespace" "$probe_fe" --kubeconfig="$KUBECONFIG" -- \
      sh -c "mysql -h127.0.0.1 -P9030 -uroot -p'${esc_auth_password}'" \
      <<<"$sync_sql" >/dev/null; then
      echo "Error: failed applying password sync SQL (authenticated mode)."
      exit 1
    fi
  else
    if ! kubectl exec -i -n "$namespace" "$probe_fe" --kubeconfig="$KUBECONFIG" -- \
      sh -c "mysql -h127.0.0.1 -P9030 -uroot" <<<"$sync_sql" >/dev/null; then
      echo "Error: failed applying password sync SQL (empty-password mode)."
      exit 1
    fi
  fi
  echo "Root password sync SQL applied."
fi

echo
echo "Verification:"

esc_target_password=$(escape_single_quotes "$target_password")
fe_failures=0
for fe in $fe_pods; do
  if kubectl exec -n "$namespace" "$fe" --kubeconfig="$KUBECONFIG" -- \
      sh -c "mysql -h127.0.0.1 -P9030 -uroot -p'${esc_target_password}' -e 'SELECT 1'" \
      1>/dev/null 2>/dev/null; then
    echo "  [PASS] FE auth on ${fe}"
  else
    echo "  [FAIL] FE auth on ${fe}"
    fe_failures=$((fe_failures + 1))
  fi
done

be_pod=$(kubectl get pods -n "$namespace" --kubeconfig="$KUBECONFIG" \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
  | awk '/(^|-)be-[0-9]+$/' | sort | head -n 1)
fe_internal_service=$(kubectl get svc -n "$namespace" --kubeconfig="$KUBECONFIG" -o name \
  | sed 's#service/##' | awk '/fe-internal$/ {print; exit}')

be_check_failed=0
if [ -n "$be_pod" ] && [ -n "$fe_internal_service" ]; then
  if kubectl exec -n "$namespace" "$be_pod" --kubeconfig="$KUBECONFIG" -- \
      sh -c "mysql -h ${fe_internal_service}.${namespace}.svc.cluster.local -P9030 -uroot -p'${esc_target_password}' -e 'SHOW FRONTENDS'" \
      1>/dev/null 2>/dev/null; then
    echo "  [PASS] BE->FE root auth (${be_pod} -> ${fe_internal_service})"
  else
    echo "  [FAIL] BE->FE root auth (${be_pod} -> ${fe_internal_service})"
    be_check_failed=1
  fi
else
  echo "  [WARN] Skipped BE->FE auth check (missing BE pod or fe-internal service)."
fi

echo
if [ "$fe_failures" -eq 0 ] && [ "$be_check_failed" -eq 0 ]; then
  echo "Doris root password sync complete and verified."
  exit 0
fi

echo "Doris root password sync completed, but verification reported failures."
exit 1
