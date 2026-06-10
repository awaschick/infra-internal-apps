#!/bin/bash

current_workspace="${workspace:-${TF_WORKSPACE:-default}}"
current_package="${package:-app-change-control}"
replica_title="App Change Control"

source "${terraform_path}/_helpers/workspace-database-replica.sh"
