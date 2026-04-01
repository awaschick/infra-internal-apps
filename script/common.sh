#!/bin/bash

# Path initialization
script_path="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
base_path="$( dirname ${script_path} )"
config_path="${base_path}/config"
terraform_path="${base_path}/terraform"
project_path="$( dirname ${base_path} )"
div="-------------------------------------------------------------------------------------"

#local_image_repo=$(<"${config_path}/docker/local_repository")
local_image_tag="latest"
executing_container_name="${local_image_repo}-local"
build_image_repo="${local_image_repo}-predeploy"
build_image_version="latest"
#docker_dev_mode=$(<"${config_path}/docker/dev_mode")

#prod_image_platform=$(<"${config_path}/docker/platform")
#local_image_platform=$(<"${config_path}/docker/local_platform")
#prod_image_registry=$(<"${config_path}/docker/registry")
#prod_image_registry_user=$(<"${config_path}/docker/registry_user")
#prod_image_repo=$(<"${config_path}/docker/repository")
#prod_image_tag=$(<"${config_path}/docker/tag")
#docker_file_name=$(<"${config_path}/docker/docker_file_name")
#docker_env_filename=$(<"${config_path}/docker/env_filename")

if [ -f "${config_path}/_clusters/selection" ]; then
    # Set environment variable expected by Terraform for the path of the kubeconfig file
    cluster_selection=$(<"${config_path}/_clusters/selection")
    cluster_config_path="${config_path}/_clusters/${cluster_selection}"
    KUBECONFIG="${config_path}/_clusters/${cluster_selection}/_k8s/kubeconfig"
    cluster_state_path="${config_path}/_clusters/${cluster_selection}/_state"
    alias_cluster_state_path="${terraform_path}/_state"
fi

# Retrieve a config value that might be overridden by an option in the _clusters directory
function read_config_value() {
    local value_path="$1"
    tr -d '\r\n' < "${value_path}"
}

function set_local_config() {
    local group="$1"
    local option="$2"
    local default_path="${config_path}/${group}/${option}"
    local response="$(read_config_value "${default_path}")"
    if [ -d "${cluster_config_path}" ]; then
        local cluster_option_path="${cluster_config_path}/${group}/${option}"
        if [ -f "${cluster_option_path}" ]; then
            response="$(read_config_value "${cluster_option_path}")"
        fi
    fi
    printf '%s\n' "${response}"
}

aws_cli_profile=$(set_local_config "aws" "cli_profile")
aws_region=$(set_local_config "aws" "region")
python_executable=$(set_local_config "python" "executable")
terraform_platform=$(set_local_config "terraform" "platform")

build_image=0
no_cache=0
run_foreground=0
show_containers="1"

# formatting shortcuts
text_bold=$(tput bold)
text_underline=$(tput smul)
text_invert=$(tput rev)
text_normal=$(tput sgr0)

# Fancy interactive prompt
# example use:
#   image_tag=$(ask_if_empty "" "spark-thrift-local" "Build the local container with what tag?" "")
function ask_if_empty() {
    local value="$1"
    local default="$2"
    local message="$3"
    local options="${4:-}"  # pass "-s" for passwords
    if [[ -z "$value" ]]; then
        read $options -p "$message [$default] " value
    fi
    echo "${value:-$default}"
}

function ask_multiline() {
    local message="$1"
    new_input=$(</dev/stdin)
    echo "${new_input}"
}
