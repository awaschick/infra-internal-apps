# This file must be called with a `source` command in `start_complete.sh` or other
# script that defines project directory and other operational constants.
# Launching this directly will not work!

cluster_name=$(set_local_config "aws-eks-init" "cluster-name")
kubeconfig_path="${cluster_config_path}/_k8s/kubeconfig"

mkdir -p "${HOME}/.kube/config-files"
ln -sf "${kubeconfig_path}" "${HOME}/.kube/config-files/${cluster_name}.yaml"

echo
echo -e "${text_bold}${text_underline}LOCAL KUBECONFIG SETUP${text_normal}"
echo
echo -e "Successfully updated symbolic link from: \n  ${text_bold}${kubeconfig_path}${text_normal}\nto: \n  ${text_bold}${HOME}/.kube/config-files/${cluster_name}.yaml${text_normal}"
echo
echo -e "If you install the ${text_underline}Kubeconfig Manager${text_normal} found in the ${text_bold}utility${text_normal} directory of this repo, you can quickly activate and deactivate multiple Kubeconfig files. If already installed, run ${text_bold}kubeconfig-switch ${cluster_name}${text_normal} to activate it now."
