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

node_mem_warn_pct="${NODE_MEM_WARN_PCT:-85}"
node_mem_fail_pct="${NODE_MEM_FAIL_PCT:-92}"
pod_mem_warn_pct="${POD_MEM_WARN_PCT:-85}"
pod_mem_fail_pct="${POD_MEM_FAIL_PCT:-95}"
spill_fs_warn_pct="${SPILL_FS_WARN_PCT:-85}"
spill_fs_fail_pct="${SPILL_FS_FAIL_PCT:-95}"
psi_some_warn="${PSI_SOME_WARN:-0.20}"
psi_some_fail="${PSI_SOME_FAIL:-1.00}"
psi_full_warn="${PSI_FULL_WARN:-0.05}"
psi_full_fail="${PSI_FULL_FAIL:-0.20}"

failures=0
warnings=0

print_result() {
  local status="$1"
  local message="$2"
  printf "[%s] %s\n" "$status" "$message"
}

note_fail() {
  failures=$((failures + 1))
  print_result "FAIL" "$1"
}

note_warn() {
  warnings=$((warnings + 1))
  print_result "WARN" "$1"
}

note_pass() {
  print_result "PASS" "$1"
}

echo
printf "%s\n Doris Memory Vitals (cluster: %s, namespace: %s)\n%s\n" "$div" "$cluster_selection" "$namespace" "$div"
echo

doris_pods=$(kubectl get pods -n "$namespace" --kubeconfig="$KUBECONFIG" \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null \
  | awk '/(^|-)fe-[0-9]+$|(^|-)be-[0-9]+$|(^|-)cn-[0-9]+$|(^|-)broker-[0-9]+$/' | sort)

if [ -z "$doris_pods" ]; then
  note_fail "No Doris FE/BE/CN/Broker pods found in namespace '${namespace}'."
  echo
  print_result "FAIL" "Doris memory vitals failed with ${failures} critical condition(s) and ${warnings} warning(s)."
  exit 1
fi

# Node condition checks (MemoryPressure + Ready)
node_condition_lines=$(kubectl get nodes --kubeconfig="$KUBECONFIG" \
  -o custom-columns='NAME:.metadata.name,READY:.status.conditions[?(@.type=="Ready")].status,MEMORY_PRESSURE:.status.conditions[?(@.type=="MemoryPressure")].status' \
  --no-headers 2>/dev/null || true)

if [ -z "$node_condition_lines" ]; then
  note_warn "Unable to read node conditions (Ready/MemoryPressure)."
else
  mem_pressure_nodes=$(echo "$node_condition_lines" | awk '$3=="True" {print $1}')
  not_ready_nodes=$(echo "$node_condition_lines" | awk '$2!="True" {print $1}')

  if [ -n "$mem_pressure_nodes" ]; then
    note_fail "MemoryPressure=True on node(s): $(echo "$mem_pressure_nodes" | tr '\n' ' ' | sed 's/[[:space:]]\+$//')."
  else
    note_pass "No nodes report MemoryPressure=True."
  fi

  if [ -n "$not_ready_nodes" ]; then
    note_fail "Node(s) not Ready: $(echo "$not_ready_nodes" | tr '\n' ' ' | sed 's/[[:space:]]\+$//')."
  else
    note_pass "All nodes are Ready."
  fi
fi

# Node memory saturation from metrics-server
node_top=$(kubectl top nodes --kubeconfig="$KUBECONFIG" --no-headers 2>/dev/null || true)
if [ -z "$node_top" ]; then
  note_warn "kubectl top nodes unavailable (metrics-server missing or inaccessible); skipped node memory utilization threshold checks."
else
  node_fail_list=$(echo "$node_top" | awk -v fail="$node_mem_fail_pct" '{gsub(/%/,"",$5); if ($5+0 >= fail) print $1 "=" $5 "%"}')
  node_warn_list=$(echo "$node_top" | awk -v warn="$node_mem_warn_pct" -v fail="$node_mem_fail_pct" '{gsub(/%/,"",$5); if ($5+0 >= warn && $5+0 < fail) print $1 "=" $5 "%"}')

  if [ -n "$node_fail_list" ]; then
    note_fail "High node memory utilization (>=${node_mem_fail_pct}%): $(echo "$node_fail_list" | tr '\n' ' ' | sed 's/[[:space:]]\+$//')."
  elif [ -n "$node_warn_list" ]; then
    note_warn "Elevated node memory utilization (>=${node_mem_warn_pct}%): $(echo "$node_warn_list" | tr '\n' ' ' | sed 's/[[:space:]]\+$//')."
  else
    note_pass "Node memory utilization is below ${node_mem_warn_pct}% on all nodes."
  fi
fi

# Pod-level memory usage vs configured limits
limits_tmp=$(mktemp)
usage_tmp=$(mktemp)
trap 'rm -f "$limits_tmp" "$usage_tmp"' EXIT

kubectl get pods -n "$namespace" --kubeconfig="$KUBECONFIG" \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .spec.containers[*]}{.resources.limits.memory}{","}{end}{"\n"}{end}' 2>/dev/null \
  | awk '/(^|-)fe-[0-9]+$|(^|-)be-[0-9]+$|(^|-)cn-[0-9]+$|(^|-)broker-[0-9]+$/' > "$limits_tmp"

kubectl top pods -n "$namespace" --kubeconfig="$KUBECONFIG" --no-headers 2>/dev/null \
  | awk '/(^|-)fe-[0-9]+$|(^|-)be-[0-9]+$|(^|-)cn-[0-9]+$|(^|-)broker-[0-9]+$/' > "$usage_tmp"

if [ ! -s "$usage_tmp" ]; then
  note_warn "kubectl top pods unavailable for Doris pods; skipped pod memory saturation checks."
else
  pod_eval=$(awk -v warn_pct="$pod_mem_warn_pct" -v fail_pct="$pod_mem_fail_pct" '
    function to_mi(v,   n, u) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      if (v == "" || v == "<unknown>") return -1
      n = v
      gsub(/[A-Za-z]+$/, "", n)
      u = substr(v, length(n) + 1)
      if (u == "Ki") return n / 1024
      if (u == "Mi") return n
      if (u == "Gi") return n * 1024
      if (u == "Ti") return n * 1024 * 1024
      if (u == "K") return n / 1000
      if (u == "M") return n
      if (u == "G") return n * 1000
      if (u == "T") return n * 1000 * 1000
      return -1
    }
    FNR == NR {
      pod = $1
      split($2, parts, ",")
      sum = 0
      has_limit = 0
      for (i in parts) {
        m = to_mi(parts[i])
        if (m >= 0) {
          sum += m
          has_limit = 1
        }
      }
      if (has_limit) limits[pod] = sum
      next
    }
    {
      pod = $1
      used = to_mi($3)
      if (used < 0) next
      if (!(pod in limits)) {
        nolimit[pod] = used
        next
      }
      pct = (used / limits[pod]) * 100
      if (pct >= fail_pct) {
        fail[pod] = sprintf("%s=%.1f%% (used=%.0fMi limit=%.0fMi)", pod, pct, used, limits[pod])
      } else if (pct >= warn_pct) {
        warn[pod] = sprintf("%s=%.1f%% (used=%.0fMi limit=%.0fMi)", pod, pct, used, limits[pod])
      }
    }
    END {
      for (k in fail) print "FAIL\t" fail[k]
      for (k in warn) print "WARN\t" warn[k]
      for (k in nolimit) print "NOLIMIT\t" k "=used=" sprintf("%.0fMi", nolimit[k])
    }
  ' "$limits_tmp" "$usage_tmp")

  pod_fail_list=$(echo "$pod_eval" | awk -F'\t' '$1=="FAIL" {print $2}')
  pod_warn_list=$(echo "$pod_eval" | awk -F'\t' '$1=="WARN" {print $2}')
  pod_nolimit_list=$(echo "$pod_eval" | awk -F'\t' '$1=="NOLIMIT" {print $2}')

  if [ -n "$pod_fail_list" ]; then
    note_fail "Doris pod memory utilization exceeds ${pod_mem_fail_pct}% of limits: $(echo "$pod_fail_list" | tr '\n' '; ' | sed 's/; $//')."
  elif [ -n "$pod_warn_list" ]; then
    note_warn "Doris pod memory utilization exceeds ${pod_mem_warn_pct}% of limits: $(echo "$pod_warn_list" | tr '\n' '; ' | sed 's/; $//')."
  else
    note_pass "Doris pod memory utilization is below ${pod_mem_warn_pct}% of configured limits."
  fi

  if [ -n "$pod_nolimit_list" ]; then
    note_warn "Some Doris pods have no explicit memory limit found: $(echo "$pod_nolimit_list" | tr '\n' '; ' | sed 's/; $//')."
  fi
fi

# OOM / restart signals from pod statuses
oom_table_cmd_output=$(kubectl get pods -n "$namespace" --kubeconfig="$KUBECONFIG" \
  -o custom-columns='NAME:.metadata.name,WAITING:.status.containerStatuses[*].state.waiting.reason,LAST_TERM:.status.containerStatuses[*].lastState.terminated.reason' \
  --no-headers 2>&1)
oom_table_cmd_rc=$?
if [ "$oom_table_cmd_rc" -ne 0 ]; then
  note_warn "Unable to read Doris pod OOM status details (kubectl get pods failed)."
else
  oom_lines=$(echo "$oom_table_cmd_output" \
    | awk '$1 ~ /(^|-)fe-[0-9]+$|(^|-)be-[0-9]+$|(^|-)cn-[0-9]+$|(^|-)broker-[0-9]+$/ && ($2 ~ /OOMKilled/ || $3 ~ /OOMKilled/) {print $1 ": waiting=" $2 ", lastTerm=" $3}')
  if [ -n "$oom_lines" ]; then
    note_fail "OOMKilled detected in Doris containers: $(echo "$oom_lines" | tr '\n' '; ' | sed 's/; $//')."
  else
    note_pass "No OOMKilled state detected in Doris containers."
  fi
fi

restarts_cmd_output=$(kubectl get pods -n "$namespace" --kubeconfig="$KUBECONFIG" --no-headers 2>&1)
restarts_cmd_rc=$?
if [ "$restarts_cmd_rc" -ne 0 ]; then
  note_warn "Unable to read Doris pod restart counts (kubectl get pods failed)."
else
  restarts_table=$(echo "$restarts_cmd_output" \
    | awk '$1 ~ /(^|-)fe-[0-9]+$|(^|-)be-[0-9]+$|(^|-)cn-[0-9]+$|(^|-)broker-[0-9]+$/ {if ($4+0 > 0) print $1 "=" $4}')
  if [ -n "$restarts_table" ]; then
    note_warn "Doris pods with restart count > 0: $(echo "$restarts_table" | tr '\n' ' ' | sed 's/[[:space:]]\+$//')."
  else
    note_pass "No Doris pod restarts recorded."
  fi
fi

# Doris spill state checks (BE config + spill path pressure)
expected_spill_config=$(set_local_config "doris" "back-end-spill-to-disk" 2>/dev/null || true)
expected_spill_norm=$(echo "${expected_spill_config}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')

be_pods=$(kubectl get pods -n "$namespace" --kubeconfig="$KUBECONFIG" \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null \
  | awk '/(^|-)be-[0-9]+$/' | sort)

if [ -z "$be_pods" ]; then
  note_warn "No Doris BE pods found; skipped spill configuration and spill-disk checks."
else
  spill_disabled_pods=""
  spill_config_read_fail=""
  spill_dir_missing=""
  spill_fs_warn=""
  spill_fs_fail=""
  spill_cfg_mismatch=""

  for be_pod in $be_pods; do
    be_conf=$(kubectl exec -n "$namespace" "$be_pod" --kubeconfig="$KUBECONFIG" -- \
      sh -c "cat /opt/apache-doris/be/conf/be.conf" 2>/dev/null || true)
    if [ -z "$be_conf" ]; then
      spill_config_read_fail="${spill_config_read_fail}${be_pod} "
      continue
    fi

    enable_spill=$(echo "$be_conf" | awk -F'=' '
      /^[[:space:]]*#/ {next}
      {
        line=$0
        sub(/[[:space:]]*#.*/, "", line)
        split(line, a, "=")
        key=a[1]
        gsub(/[[:space:]]/, "", key)
        if (tolower(key)=="enable_spill") {
          val=substr(line, index(line, "=")+1)
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
          print tolower(val)
          exit
        }
      }')
    spill_dir=$(echo "$be_conf" | awk -F'=' '
      /^[[:space:]]*#/ {next}
      {
        line=$0
        sub(/[[:space:]]*#.*/, "", line)
        split(line, a, "=")
        key=a[1]
        gsub(/[[:space:]]/, "", key)
        if (tolower(key)=="spill_dir") {
          val=substr(line, index(line, "=")+1)
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
          print val
          exit
        }
      }')
    spill_storage_root_path=$(echo "$be_conf" | awk -F'=' '
      /^[[:space:]]*#/ {next}
      {
        line=$0
        sub(/[[:space:]]*#.*/, "", line)
        split(line, a, "=")
        key=a[1]
        gsub(/[[:space:]]/, "", key)
        if (tolower(key)=="spill_storage_root_path") {
          val=substr(line, index(line, "=")+1)
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
          print val
          exit
        }
      }')

    if [ -z "$spill_dir" ]; then
      spill_dir="$spill_storage_root_path"
    fi
    if [ -z "$spill_dir" ]; then
      spill_dir="/opt/apache-doris/be/storage/spill"
    fi

    if [ "$enable_spill" != "true" ] && [ "$enable_spill" != "1" ] && [ "$enable_spill" != "yes" ]; then
      spill_disabled_pods="${spill_disabled_pods}${be_pod}(enable_spill=${enable_spill:-unset}) "
      if [ "$expected_spill_norm" = "true" ] || [ "$expected_spill_norm" = "1" ] || [ "$expected_spill_norm" = "yes" ]; then
        spill_cfg_mismatch="${spill_cfg_mismatch}${be_pod}(expected=true, actual=${enable_spill:-unset}) "
      fi
      continue
    fi

    if [ "$expected_spill_norm" = "false" ] || [ "$expected_spill_norm" = "0" ] || [ "$expected_spill_norm" = "no" ]; then
      spill_cfg_mismatch="${spill_cfg_mismatch}${be_pod}(expected=false, actual=true) "
    fi

    spill_df_result=$(kubectl exec -n "$namespace" "$be_pod" --kubeconfig="$KUBECONFIG" -- \
      sh -c '
        raw="$1"
        found_path=""
        found_usepct=""
        old_ifs="$IFS"
        IFS=",;"
        set -- $raw
        IFS="$old_ifs"
        for candidate in "$@"; do
          candidate=$(echo "$candidate" | sed '"'"'s/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//;s/^'"'"'"'"'"'//;s/'"'"'"'"'"'$//'"'"')
          [ -z "$candidate" ] && continue
          if [ -d "$candidate" ]; then
            found_path="$candidate"
            found_usepct=$(df -P "$candidate" | awk '"'"'NR==2 {print $5}'"'"')
            break
          fi
        done
        if [ -z "$found_path" ]; then
          echo "MISSING|$raw"
        else
          echo "${found_path}|${found_usepct}"
        fi
      ' sh "$spill_dir" 2>/dev/null || true)

    spill_df_path=$(echo "$spill_df_result" | awk -F'|' '{print $1}')
    spill_usepct=$(echo "$spill_df_result" | awk -F'|' '{print $2}')
    if [ -z "$spill_df_result" ] || [ "$spill_df_path" = "MISSING" ] || [ -z "$spill_usepct" ]; then
      spill_dir_missing="${spill_dir_missing}${be_pod}(path=${spill_dir}) "
      continue
    fi

    spill_usepct_num=$(echo "$spill_usepct" | tr -d '%')
    if [ -z "$spill_usepct_num" ]; then
      spill_config_read_fail="${spill_config_read_fail}${be_pod}(bad-df=${spill_usepct}) "
      continue
    fi

    if [ "$spill_usepct_num" -ge "$spill_fs_fail_pct" ]; then
      spill_fs_fail="${spill_fs_fail}${be_pod}(${spill_df_path}=${spill_usepct}) "
    elif [ "$spill_usepct_num" -ge "$spill_fs_warn_pct" ]; then
      spill_fs_warn="${spill_fs_warn}${be_pod}(${spill_df_path}=${spill_usepct}) "
    fi
  done

  if [ -n "$spill_cfg_mismatch" ]; then
    note_warn "BE spill config differs from configured back-end-spill-to-disk intent: ${spill_cfg_mismatch}"
  fi
  if [ -n "$spill_config_read_fail" ]; then
    note_warn "Could not fully read/parse BE spill settings for pod(s): ${spill_config_read_fail}"
  fi
  if [ -n "$spill_disabled_pods" ]; then
    note_warn "Spill is disabled on BE pod(s): ${spill_disabled_pods}"
  elif [ -z "$spill_config_read_fail" ]; then
    note_pass "Spill is enabled on all parsed BE pods."
  fi
  if [ -n "$spill_dir_missing" ]; then
    note_fail "Spill enabled but spill directory missing/unreadable on BE pod(s): ${spill_dir_missing}"
  fi
  if [ -n "$spill_fs_fail" ]; then
    note_fail "Spill filesystem usage is critically high (>=${spill_fs_fail_pct}%): ${spill_fs_fail}"
  elif [ -n "$spill_fs_warn" ]; then
    note_warn "Spill filesystem usage is elevated (>=${spill_fs_warn_pct}%): ${spill_fs_warn}"
  elif [ -z "$spill_dir_missing" ] && [ -z "$spill_config_read_fail" ]; then
    note_pass "Spill filesystem usage is below ${spill_fs_warn_pct}% on parsed BE pods."
  fi
fi

# Kernel paging pressure state: sample one running Doris pod per node for /proc/pressure/memory
sample_nodes=$(kubectl get pods -n "$namespace" --kubeconfig="$KUBECONFIG" \
  --field-selector=status.phase=Running \
  -o custom-columns='NAME:.metadata.name,NODE:.spec.nodeName' --no-headers 2>/dev/null \
  | awk '$1 ~ /(^|-)fe-[0-9]+$|(^|-)be-[0-9]+$|(^|-)cn-[0-9]+$|(^|-)broker-[0-9]+$/ {if (!seen[$2]++) print $1 "\t" $2}')

if [ -z "$sample_nodes" ]; then
  note_warn "No running Doris pods available for PSI sampling."
else
  psi_issues=""
  psi_missing=0

  while IFS=$'\t' read -r sample_pod sample_node; do
    [ -z "$sample_pod" ] && continue

    psi=$(kubectl exec -n "$namespace" "$sample_pod" --kubeconfig="$KUBECONFIG" -- \
      sh -c "cat /proc/pressure/memory" 2>/dev/null || true)

    if [ -z "$psi" ]; then
      psi_missing=$((psi_missing + 1))
      continue
    fi

    psi_eval=$(echo "$psi" | awk -v sw="$psi_some_warn" -v sf="$psi_some_fail" -v fw="$psi_full_warn" -v ff="$psi_full_fail" '
      /^some / {
        for (i = 1; i <= NF; i++) {
          if ($i ~ /^avg10=/) {
            some = $i
            sub(/^avg10=/, "", some)
          }
        }
      }
      /^full / {
        for (i = 1; i <= NF; i++) {
          if ($i ~ /^avg10=/) {
            full = $i
            sub(/^avg10=/, "", full)
          }
        }
      }
      END {
        if (some == "") some = -1
        if (full == "") full = -1
        status = "PASS"
        if (some >= sf || full >= ff) status = "FAIL"
        else if (some >= sw || full >= fw) status = "WARN"
        printf "%s %.2f %.2f\n", status, some, full
      }
    ' 2>/dev/null)
    psi_eval_rc=$?
    if [ "$psi_eval_rc" -ne 0 ] || [ -z "$psi_eval" ]; then
      psi_issues+="WARN:${sample_node}:psi_parse_failed;"
      continue
    fi

    psi_status=$(echo "$psi_eval" | awk '{print $1}')
    psi_some=$(echo "$psi_eval" | awk '{print $2}')
    psi_full=$(echo "$psi_eval" | awk '{print $3}')
    psi_issues+="${psi_status}:${sample_node}:psi_some_avg10=${psi_some},psi_full_avg10=${psi_full};"
  done <<< "$sample_nodes"

  psi_fail_lines=$(echo "$psi_issues" | tr ';' '\n' | awk -F':' '$1=="FAIL" {print $2 "(" $3 ")"}')
  psi_warn_lines=$(echo "$psi_issues" | tr ';' '\n' | awk -F':' '$1=="WARN" && $3 != "psi_parse_failed" {print $2 "(" $3 ")"}')
  psi_parse_lines=$(echo "$psi_issues" | tr ';' '\n' | awk -F':' '$1=="WARN" && $3 == "psi_parse_failed" {print $2}')

  if [ -n "$psi_fail_lines" ]; then
    note_fail "Kernel memory pressure (PSI) is high: $(echo "$psi_fail_lines" | tr '\n' ' ' | sed 's/[[:space:]]\+$//')."
  elif [ -n "$psi_warn_lines" ]; then
    note_warn "Kernel memory pressure (PSI) is elevated: $(echo "$psi_warn_lines" | tr '\n' ' ' | sed 's/[[:space:]]\+$//')."
  elif [ -n "$psi_parse_lines" ]; then
    note_warn "PSI parsing failed on node sample(s): $(echo "$psi_parse_lines" | tr '\n' ' ' | sed 's/[[:space:]]\+$//')."
  elif [ "$psi_missing" -gt 0 ]; then
    note_warn "PSI files were unavailable in ${psi_missing} sample(s); skipped pressure thresholds for those nodes."
  else
    note_pass "Kernel memory pressure (PSI avg10) is below warning thresholds on sampled nodes."
  fi
fi

echo
if [ "$failures" -gt 0 ]; then
  print_result "FAIL" "Doris memory vitals failed with ${failures} critical condition(s) and ${warnings} warning(s)."
  exit 1
fi

if [ "$warnings" -gt 0 ]; then
  print_result "WARN" "Doris memory vitals completed with ${warnings} warning(s) and no critical conditions."
  exit 0
fi

print_result "PASS" "Doris memory vitals passed with no alarming conditions detected."
exit 0
