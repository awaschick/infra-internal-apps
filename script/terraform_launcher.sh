#!/bin/bash
source "$(dirname "$0")/common.sh"

component="undefined"
dev="0"
restore_backup="0"
workspace="${TF_WORKSPACE:-default}"
unset TF_WORKSPACE

if [[ ! -z $1 ]]; then
    if [[ ! $1 == *"--"* ]]; then
        component=$1
    fi
fi
# overwrite params with arguments
while [ $# -gt 0 ]; do
   if [[ $1 == *"--"* ]]; then
        v="${1/--/}"
        declare $v="$2"
   fi
  shift
done


tf_bash()
{
    package=$1
    command=$2
    cd "${terraform_path}/${package}" && ${command}
}


tf_exec()
{
    package=$1
    # echo "KUBECONFIG is currently set to ${KUBECONFIG}"
    source ./.venv/bin/activate
    rm -f "${alias_cluster_state_path}"
    ln -s "${cluster_state_path}" "${alias_cluster_state_path}"
    if [ "${workspace}" != "default" ]; then
        mkdir -p "${cluster_config_path}/${package}/_instances/${workspace}"
    fi

    cd "${terraform_path}/${package}" && terraform init -reconfigure
    cd "${terraform_path}/${package}" && terraform workspace select "${workspace}" >/dev/null 2>&1 || terraform workspace new "${workspace}"

    if [ ${mode} = "start" ]; then
        if [ -f "${terraform_path}/${package}/_init/start.sh" ]; then
            source "${terraform_path}/${package}/_init/start.sh"
        fi

        cd "${terraform_path}/${package}" && terraform apply -auto-approve -var "kubeconfig=${KUBECONFIG}"

        if [ -f "${terraform_path}/${package}/_init/start_complete.sh" ]; then
            source "${terraform_path}/${package}/_init/start_complete.sh"
        fi


    elif [ ${mode} = "stop" ]; then
        if [ -f "${terraform_path}/${package}/_init/stop.sh" ]; then
            source "${terraform_path}/${package}/_init/stop.sh"
        fi

        cd "${terraform_path}/${package}" && terraform destroy -auto-approve -var "kubeconfig=${KUBECONFIG}"

        if [ -f "${terraform_path}/${package}/_init/stop_complete.sh" ]; then
            source "${terraform_path}/${package}/_init/stop_complete.sh"
        fi

    elif [ ${mode} = "plan" ]; then
        cd "${terraform_path}/${package}" && terraform plan -var "kubeconfig=${KUBECONFIG}"
    fi
}

case $component in
    "foo")
        printf "\n${div}\n Foobar  \n${div}\n\n"
    ;;

    *)
        tf_exec ${component}
    ;;
esac
