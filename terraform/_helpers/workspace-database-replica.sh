#!/bin/bash

current_workspace="${workspace:-${TF_WORKSPACE:-default}}"
current_package="${package:-${current_package:-}}"
divider="-------------------------------------------------------------------------------------"
if [ -n "${div:-}" ]; then
    divider="${div}"
fi

if [ "${current_workspace}" = "default" ]; then
    return 0 2>/dev/null || exit 0
fi

replica_config_file() {
    local option="$1"
    local instance="${current_workspace}"
    if [ "$#" -gt 1 ]; then
        instance="$2"
    fi
    local instance_path="${cluster_config_path}/${current_package}/_instances/${instance}/${option}"
    local cluster_path="${cluster_config_path}/${current_package}/${option}"
    local common_path="${config_path}/${current_package}/${option}"

    if [ -n "${instance}" ] && [ -f "${instance_path}" ]; then
        printf '%s\n' "${instance_path}"
    elif [ -f "${cluster_path}" ]; then
        printf '%s\n' "${cluster_path}"
    elif [ -f "${common_path}" ]; then
        printf '%s\n' "${common_path}"
    fi
}

replica_config_value() {
    local config_file
    if [ "$#" -gt 1 ]; then
        config_file="$(replica_config_file "$1" "$2")"
    else
        config_file="$(replica_config_file "$1")"
    fi
    if [ -n "${config_file}" ]; then
        read_config_value "${config_file}"
    fi
}

replica_source_db="$(replica_config_value db-replica-source-db)"
replica_source_workspace="$(replica_config_value db-replica-source-workspace)"

if [ -z "${replica_source_db}" ] && [ -z "${replica_source_workspace}" ] && [ -z "$(replica_config_file db-name "")" ]; then
    return 0 2>/dev/null || exit 0
fi

replica_source_label="default workspace database"

if [ -n "${replica_source_db}" ]; then
    replica_source_label="database '${replica_source_db}'"
elif [ -n "${replica_source_workspace}" ]; then
    replica_source_label="workspace '${replica_source_workspace}' database"
fi

printf "\n%s\n" "${divider}"
printf " %s database replica\n" "${replica_title:-${current_package}}"
printf "%s\n\n" "${divider}"
printf "Terraform is about to deploy package '%s' in workspace '%s'.\n" "${current_package}" "${current_workspace}"
printf "Would you like to refresh this workspace database from the %s before Terraform apply?\n" "${replica_source_label}"
printf "If the target workspace database already exists, this will back it up and replace it.\n\n"

read -r -p "Replicate database now? [y/N] " replicate_database

case "${replicate_database}" in
    y|Y|yes|YES|Yes)
        replica_args=(
            --package "${current_package}" \
            --workspace "${current_workspace}" \
            --replace
        )
        if [ "${replica_write_config:-0}" = "1" ]; then
            replica_args+=(--write-config)
        fi
        if [ -n "${replica_source_db}" ]; then
            replica_args+=(--source-db "${replica_source_db}")
        elif [ -n "${replica_source_workspace}" ]; then
            replica_args+=(--source-workspace "${replica_source_workspace}")
        fi
        "${base_path}/script/replicate_workspace_database.sh" "${replica_args[@]}"
        ;;
    *)
        printf "Skipping database replication.\n"
        ;;
esac
