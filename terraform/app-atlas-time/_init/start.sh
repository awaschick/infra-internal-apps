#!/bin/bash

current_workspace="${workspace:-${TF_WORKSPACE:-default}}"
current_package="${package:-app-atlas-time}"
replica_title="Atlas Time"
replica_write_config="1"

# Do not deploy after a failed database refresh (the launcher does not use set -e).
source "${terraform_path}/_helpers/workspace-database-replica.sh" || exit $?
