#!/bin/bash

source "$(dirname "$0")/common.sh"

printf "\n${div}\n ${cluster_selection} Cluster Node Status:  \n${div}\n\n"
printf "kubectl top nodes --kubeconfig=${KUBECONFIG}\n"
kubectl top nodes --kubeconfig=${KUBECONFIG}
printf "\n${div}\n ${cluster_selection} Cluster Pod Status:  \n${div}\n\n"
printf "kubectl get pods --all-namespaces --kubeconfig=${KUBECONFIG}\n"
kubectl get pods --all-namespaces --kubeconfig=${KUBECONFIG}
