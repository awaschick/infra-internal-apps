#!/bin/bash

source "$(dirname "$0")/common.sh"

namespace="${NAMESPACE}"
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

root_password=$(set_local_config "doris" "root-password")
failures=0

print_result() {
  local status="$1"
  local message="$2"
  printf "[%s] %s\n" "$status" "$message"
}

echo
printf "%s\n Doris Ready Check (cluster: %s, namespace: %s)\n%s\n" "$div" "$cluster_selection" "$namespace" "$div"
echo ""

fe_pod=$(kubectl get pods -n "$namespace" --kubeconfig="$KUBECONFIG" \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
  | awk '/(^|-)fe-[0-9]+$/' | sort | head -n 1)

if [ -z "$fe_pod" ]; then
  print_result "FAIL" "No FE pod found."
  failures=$((failures + 1))
else
  print_result "INFO" "Using FE pod '${fe_pod}' for SQL health checks."
fi

frontends_raw=""
backends_raw=""
if [ -n "$fe_pod" ]; then
  if [ -n "$root_password" ]; then
    frontends_raw=$(kubectl exec -n "$namespace" "$fe_pod" --kubeconfig="$KUBECONFIG" -- \
      sh -c "mysql -B -h127.0.0.1 -P9030 -uroot -p'${root_password}' -e 'SHOW FRONTENDS'" 2>/dev/null || true)
    backends_raw=$(kubectl exec -n "$namespace" "$fe_pod" --kubeconfig="$KUBECONFIG" -- \
      sh -c "mysql -B -h127.0.0.1 -P9030 -uroot -p'${root_password}' -e 'SHOW BACKENDS'" 2>/dev/null || true)
  else
    frontends_raw=$(kubectl exec -n "$namespace" "$fe_pod" --kubeconfig="$KUBECONFIG" -- \
      sh -c "mysql -B -h127.0.0.1 -P9030 -uroot -e 'SHOW FRONTENDS'" 2>/dev/null || true)
    backends_raw=$(kubectl exec -n "$namespace" "$fe_pod" --kubeconfig="$KUBECONFIG" -- \
      sh -c "mysql -B -h127.0.0.1 -P9030 -uroot -e 'SHOW BACKENDS'" 2>/dev/null || true)
  fi
fi

if [ -z "$frontends_raw" ]; then
  print_result "FAIL" "Unable to query SHOW FRONTENDS from FE."
  failures=$((failures + 1))
else
  fe_eval=$(echo "$frontends_raw" | awk '
    BEGIN{
      FS="\t"
    }
    function norm(v){
      gsub(/\r/, "", v)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      return tolower(v)
    }
    function is_true(v){
      v=norm(v)
      return (v=="true" || v=="yes" || v=="1")
    }
    NR==1{
      for (i=1; i<=NF; i++) {
        col=norm($i)
        if (col=="ismaster") master_col=i
        if (col=="alive") alive_col=i
      }
      next
    }
    NR>1{
      total++
      if (alive_col>0 && is_true($alive_col)) alive++
      if (master_col>0 && is_true($master_col)) masters++
    }
    END{
      quorum=int(total/2)+1
      printf "%d %d %d %d\n", total, alive, masters, quorum
    }')
  fe_total=$(echo "$fe_eval" | awk '{print $1}')
  fe_alive=$(echo "$fe_eval" | awk '{print $2}')
  fe_masters=$(echo "$fe_eval" | awk '{print $3}')
  fe_quorum=$(echo "$fe_eval" | awk '{print $4}')

  if [ "${fe_total:-0}" -gt 0 ] && [ "${fe_alive:-0}" -ge "${fe_quorum:-999}" ] && [ "${fe_masters:-0}" -eq 1 ]; then
    print_result "PASS" "FE health ok: total=${fe_total}, alive=${fe_alive}, masters=${fe_masters}, quorum=${fe_quorum}."
  else
    print_result "FAIL" "FE health failed: total=${fe_total:-0}, alive=${fe_alive:-0}, masters=${fe_masters:-0}, quorum=${fe_quorum:-0}."
    failures=$((failures + 1))
  fi
fi

if [ -z "$backends_raw" ]; then
  print_result "FAIL" "Unable to query SHOW BACKENDS from FE."
  failures=$((failures + 1))
else
  be_eval=$(echo "$backends_raw" | awk '
    BEGIN{
      FS="\t"
    }
    function norm(v){
      gsub(/\r/, "", v)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      return tolower(v)
    }
    function is_true(v){
      v=norm(v)
      return (v=="true" || v=="yes" || v=="1")
    }
    NR==1{
      for (i=1; i<=NF; i++) {
        col=norm($i)
        if (col=="alive") alive_col=i
      }
      next
    }
    NR>1{
      total++
      if (alive_col>0 && is_true($alive_col)) alive++
    }
    END{
      printf "%d %d\n", total, alive
    }')
  be_total=$(echo "$be_eval" | awk '{print $1}')
  be_alive=$(echo "$be_eval" | awk '{print $2}')

  if [ "${be_total:-0}" -gt 0 ] && [ "${be_total:-0}" -eq "${be_alive:-0}" ]; then
    print_result "PASS" "BE health ok: all backends alive (${be_alive}/${be_total})."
  else
    print_result "FAIL" "BE health failed: alive=${be_alive:-0}, total=${be_total:-0}."
    failures=$((failures + 1))
  fi
fi

pod_lines=$(kubectl get pods -n "$namespace" --kubeconfig="$KUBECONFIG" --no-headers 2>/dev/null \
  | awk '$1 ~ /(^|-)fe-[0-9]+$/ || $1 ~ /(^|-)be-[0-9]+$/ || $1 ~ /(^|-)cn-[0-9]+$/ || $1 ~ /(^|-)broker-[0-9]+$/')

if [ -z "$pod_lines" ]; then
  print_result "FAIL" "No Doris FE/BE/CN/Broker pods found."
  failures=$((failures + 1))
else
  pod_issues=$(echo "$pod_lines" | awk '
    {
      name=$1
      ready=$2
      status=$3
      split(ready, r, "/")
      if (r[1] != r[2] || status ~ /CrashLoopBackOff|Error|ImagePullBackOff|Init:|Pending|ContainerCreating/) {
        print $0
      }
    }')
  if [ -z "$pod_issues" ]; then
    print_result "PASS" "Pod health ok: all Doris pods are Ready and not in crash/error states."
  else
    print_result "FAIL" "Pod health failed: some Doris pods are not fully Ready or are in unhealthy states."
    echo "$pod_issues" | awk '{printf "  - %s\n", $0}'
    failures=$((failures + 1))
  fi
fi

echo
if [ "$failures" -eq 0 ]; then
  print_result "PASS" "Doris ready check passed."
  exit 0
fi

print_result "FAIL" "Doris ready check failed with ${failures} failing condition(s)."
exit 1
