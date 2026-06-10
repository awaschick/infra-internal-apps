#!/bin/bash

current_workspace="${workspace:-${TF_WORKSPACE:-default}}"
current_package="${package:-app-atlas-construct}"
replica_title="Atlas Construct"

source "${terraform_path}/_helpers/workspace-database-replica.sh"
