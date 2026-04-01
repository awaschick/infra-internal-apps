#!/bin/bash

script_path="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
base_path="$( dirname ${script_path} )"
config_path="${base_path}/config"

if [ ! -f "${config_path}/_clusters/selection" ]; then
  source "${script_path}/choose_cluster.sh"
fi

