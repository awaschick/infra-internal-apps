#!/usr/bin/env zsh

# Kubernetes config directory
KUBE_CONFIG_DIR="$HOME/.kube"
KUBE_CONFIG_FILES_DIR="$KUBE_CONFIG_DIR/config-files"
KUBE_CONFIG_ACTIVE="$KUBE_CONFIG_DIR/config.active"

# Create directories if they don't exist
mkdir -p "${KUBE_CONFIG_FILES_DIR}"

# Set KUBECONFIG to the active symlink
if [[ -L "${KUBE_CONFIG_ACTIVE}" ]]; then
  export KUBECONFIG="${KUBE_CONFIG_ACTIVE}"
fi

# Function to switch kubectl configurations
kubeconfig-switch() {
  local config_name="$1"
  
  if [[ -z "$config_name" ]]; then
    echo "Usage: kubeconfig-switch <config-name>"
    echo ""
    echo "Available configurations:"
    for config_file in "${KUBE_CONFIG_FILES_DIR}"/*.{yml,yaml}(N); do
      local basename="${config_file:t:r}"
      if [[ -L "${KUBE_CONFIG_ACTIVE}" ]] && [[ "$(readlink "${KUBE_CONFIG_ACTIVE}")" == "$config_file" ]]; then
        echo "  * $basename (active)"
      else
        echo "    $basename"
      fi
    done
    return 1
  fi
  
  local target_config="${KUBE_CONFIG_FILES_DIR}/${config_name}.yaml"
  if [[ ! -f "$target_config" ]]; then
    target_config="${KUBE_CONFIG_FILES_DIR}/${config_name}.yml"
  fi
  
  if [[ ! -f "$target_config" ]]; then
    echo "Error: Configuration '${config_name}' not found in ${KUBE_CONFIG_FILES_DIR}"
    return 1
  fi
  
  ln -sf "$target_config" "${KUBE_CONFIG_ACTIVE}"
  export KUBECONFIG="${KUBE_CONFIG_ACTIVE}"
  echo "Switched to kubectl config: ${config_name}"
}

# Scan available configs and display info
echo ""
echo "📦 Kubernetes Configuration Manager"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ -L "${KUBE_CONFIG_ACTIVE}" ]]; then
  local active_config="$(readlink "${KUBE_CONFIG_ACTIVE}")"
  local active_name="${active_config:t:r}"
  echo "Active config: ${active_name}"
else
  echo "No active config set"
fi

echo ""
echo "Available configs:"
local has_configs=false
for config_file in "${KUBE_CONFIG_FILES_DIR}"/*.{yml,yaml}(N); do
  has_configs=true
  echo "  - ${config_file:t:r}"
done

if [[ "$has_configs" == "false" ]]; then
  echo "  (none found in ${KUBE_CONFIG_FILES_DIR})"
fi

echo ""
echo "To switch configurations, use:"
echo "  kubeconfig-switch <config-name>"
echo ""
echo "Example:"
for config_file in "${KUBE_CONFIG_FILES_DIR}"/*.{yml,yaml}(N); do
  echo "  kubeconfig-switch ${config_file:t:r}"
  break
done
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
