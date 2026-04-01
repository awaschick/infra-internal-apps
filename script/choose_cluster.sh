#!/bin/bash

source "$(dirname "$0")/common.sh"
cluster_selection="local"
name=$(ask_if_empty "" "${cluster_selection}" "Please enter the k8s cluster you want to interact with:" "")

sh -c "printf ${name} > ${config_path}/_clusters/selection"
cluster_selection=$(<"${config_path}/_clusters/selection")
mkdir -p "${config_path}/_clusters/${cluster_selection}"
mkdir -p "${config_path}/_clusters/${cluster_selection}/_state"
mkdir -p "${config_path}/_clusters/${cluster_selection}/aws"
mkdir -p "${config_path}/_clusters/${cluster_selection}/cluster"

if [ ! -f "${config_path}/_clusters/${cluster_selection}/_k8s/kubeconfig" ]; then
    mkdir -p "${config_path}/_clusters/${cluster_selection}/_k8s/"
    printf "\n${div}\n No Kubeconfig file found at ${config_path}/_clusters/${cluster_selection}/_k8s!\n"
    printf " Paste in the Kubeconfig for this cluster, press [ctrl-d] when finished:\n${div}\n"
    new_kubeconfig=$(ask_multiline)
    echo "${new_kubeconfig}" >> "${config_path}/_clusters/${cluster_selection}/_k8s/kubeconfig"
fi

printf "\n${div}\nCurrent cluster defined as [${name}]\n${div}\n"
