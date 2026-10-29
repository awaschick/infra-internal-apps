#!/bin/bash
# The launcher runs this only after a successful Terraform apply.
python3 "${base_path}/script/sync_postgres_read_only_users.py" --apply
