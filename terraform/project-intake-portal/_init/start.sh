#!/bin/bash

current_workspace="${workspace:-${TF_WORKSPACE:-default}}"
current_package="${package:-project-intake-portal}"
divider="-------------------------------------------------------------------------------------"
if [ -n "${div:-}" ]; then
    divider="${div}"
fi

if [ "${current_workspace}" = "default" ]; then
    return 0 2>/dev/null || exit 0
fi

printf "\n%s\n" "${divider}"
printf " Project Intake Portal database replica\n"
printf "%s\n\n" "${divider}"
printf "Terraform is about to deploy package '%s' in workspace '%s'.\n" "${current_package}" "${current_workspace}"
printf "Would you like to refresh this workspace database from the default workspace database before Terraform apply?\n"
printf "If the target workspace database already exists, this will back it up and replace it.\n\n"

read -r -p "Replicate database now? [y/N] " replicate_database

case "${replicate_database}" in
    y|Y|yes|YES|Yes)
        "${base_path}/script/replicate_workspace_database.sh" \
            --package "${current_package}" \
            --workspace "${current_workspace}" \
            --replace \
            --write-config
        ;;
    *)
        printf "Skipping database replication.\n"
        ;;
esac
