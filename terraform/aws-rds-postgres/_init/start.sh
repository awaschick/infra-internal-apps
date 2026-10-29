#!/bin/bash
# Validate before Terraform changes anything. RDS is a singleton deployment.
if [ "${workspace:-default}" != default ]; then
    echo 'aws-rds-postgres must use the default Terraform workspace.' >&2
    return 1
fi
python3 "${base_path}/script/sync_postgres_read_only_users.py" --check
