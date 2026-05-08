#!/bin/bash
source "$(dirname "$0")/common.sh"
set -euo pipefail

workspace="${TF_WORKSPACE:-dev}"
package="app-change-control"
source_db=""
target_db=""
replace="0"
backup_existing="1"
backup_dir="${base_path}/db/backups"
write_config="0"

usage() {
    cat <<'USAGE'
Usage:
  ./script/replicate_workspace_database.sh [options]

Options:
  --package NAME        Config package with db-name and _instances. Defaults to app-change-control.
  --workspace NAME      Instance workspace to prepare. Defaults to TF_WORKSPACE or dev.
  --source-db NAME      Source database. Defaults to the selected cluster package db-name.
  --target-db NAME      Target database. Defaults to instance db-name, or <source>_<workspace>.
  --replace             Drop and recreate the target database if it already exists.
  --no-backup           With --replace, do not dump the existing target before dropping it.
  --backup-dir DIR      Directory for replaced target backups. Defaults to db/backups.
  --write-config        Write the resolved target db-name to the workspace instance config.
  --help                Show this help.

The script reads Postgres host, port, user, and password from the same selected
cluster config files used by Terraform.
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --package)
            package="${2:?Missing value for --package}"
            shift 2
            ;;
        --workspace)
            workspace="${2:?Missing value for --workspace}"
            shift 2
            ;;
        --source-db)
            source_db="${2:?Missing value for --source-db}"
            shift 2
            ;;
        --target-db)
            target_db="${2:?Missing value for --target-db}"
            shift 2
            ;;
        --replace)
            replace="1"
            shift
            ;;
        --no-backup)
            backup_existing="0"
            shift
            ;;
        --backup-dir)
            backup_dir="${2:?Missing value for --backup-dir}"
            shift 2
            ;;
        --write-config)
            write_config="1"
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [ -z "${cluster_selection:-}" ] || [ ! -d "${cluster_config_path:-}" ]; then
    echo "No selected cluster config was found. Check config/_clusters/selection." >&2
    exit 1
fi

if [[ ! "${package}" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
    echo "Package names must use only letters, numbers, underscores, and hyphens, and cannot start with punctuation: ${package}" >&2
    exit 1
fi

find_config_file() {
    local group="$1"
    local option="$2"
    local instance="${3:-}"
    local instance_path="${cluster_config_path}/${group}/_instances/${instance}/${option}"
    local cluster_path="${cluster_config_path}/${group}/${option}"
    local common_path="${config_path}/${group}/${option}"

    if [ -n "${instance}" ] && [ -f "${instance_path}" ]; then
        printf '%s\n' "${instance_path}"
    elif [ -f "${cluster_path}" ]; then
        printf '%s\n' "${cluster_path}"
    elif [ -f "${common_path}" ]; then
        printf '%s\n' "${common_path}"
    else
        echo "Missing config value: ${group}/${option}" >&2
        exit 1
    fi
}

config_value() {
    read_config_value "$(find_config_file "$1" "$2" "${3:-}")"
}

if ! command -v psql >/dev/null 2>&1 && [ -d /opt/homebrew/opt/libpq/bin ]; then
    export PATH="/opt/homebrew/opt/libpq/bin:${PATH}"
fi

for command_name in psql pg_dump pg_restore createdb dropdb; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "Missing required PostgreSQL command: ${command_name}" >&2
        exit 1
    fi
done

host="$(config_value aws-rds-postgres endpoint)"
port="$(config_value aws-rds-postgres db-port)"
user="$(config_value aws-rds-postgres db-username)"
password="$(config_value aws-rds-postgres db-password)"

if [ -z "${source_db}" ]; then
    source_db="$(config_value "${package}" db-name)"
fi

if [ -z "${target_db}" ]; then
    target_config_path="${cluster_config_path}/${package}/_instances/${workspace}/db-name"
    if [ -f "${target_config_path}" ]; then
        target_db="$(read_config_value "${target_config_path}")"
    else
        target_db="${source_db}_${workspace}"
    fi
fi

if [ "${source_db}" = "${target_db}" ]; then
    echo "Refusing to replicate ${source_db} onto itself." >&2
    exit 1
fi

for db_name in "${source_db}" "${target_db}"; do
    if [[ ! "${db_name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        echo "Database names must use only letters, numbers, and underscores, and cannot start with a number: ${db_name}" >&2
        exit 1
    fi
done

export PGPASSWORD="${password}"
psql_base=(psql -h "${host}" -p "${port}" -U "${user}" -d postgres -v ON_ERROR_STOP=1 -P pager=off)

database_exists() {
    local db_name="$1"
    "${psql_base[@]}" -At \
        -c "SELECT 1 FROM pg_database WHERE datname = '${db_name}';" | grep -qx "1"
}

exact_row_total() {
    local db_name="$1"
    psql -h "${host}" -p "${port}" -U "${user}" -d "${db_name}" -v ON_ERROR_STOP=1 -P pager=off -At <<'SQL'
SELECT COALESCE(
    SUM(
        ((xpath(
            '/row/c/text()',
            query_to_xml(format('SELECT count(*) AS c FROM %I.%I', schemaname, tablename), false, true, '')
        ))[1]::text)::bigint
    ),
    0
)
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema');
SQL
}

relation_count() {
    local db_name="$1"
    psql -h "${host}" -p "${port}" -U "${user}" -d "${db_name}" -v ON_ERROR_STOP=1 -P pager=off -At <<'SQL'
SELECT count(*)
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND c.relkind IN ('r', 'p', 'v', 'm', 'S', 'f');
SQL
}

echo "Selected cluster: ${cluster_selection}"
echo "Package: ${package}"
echo "Source database: ${source_db}"
echo "Target database: ${target_db}"

if ! database_exists "${source_db}"; then
    echo "Source database does not exist: ${source_db}" >&2
    exit 1
fi

if database_exists "${target_db}"; then
    if [ "${replace}" != "1" ]; then
        echo "Target database already exists: ${target_db}" >&2
        echo "Re-run with --replace if you want to rebuild it from ${source_db}." >&2
        exit 1
    fi

    if [ "${backup_existing}" = "1" ]; then
        mkdir -p "${backup_dir}"
        timestamp="$(date +%Y%m%d%H%M%S)"
        backup_file="${backup_dir}/${target_db}-pre-replace-${timestamp}.dump"
        echo "Backing up existing target to ${backup_file}"
        pg_dump -h "${host}" -p "${port}" -U "${user}" -d "${target_db}" -Fc --no-owner --no-acl -f "${backup_file}"
    fi

    echo "Dropping existing target database"
    "${psql_base[@]}" -c \
        "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${target_db}' AND pid <> pg_backend_pid();"
    dropdb -h "${host}" -p "${port}" -U "${user}" --if-exists "${target_db}"
fi

dump_file="$(mktemp "${TMPDIR:-/tmp}/${package}-${source_db}.XXXXXX.dump")"
cleanup() {
    rm -f "${dump_file}"
}
trap cleanup EXIT

echo "Dumping ${source_db}"
pg_dump -h "${host}" -p "${port}" -U "${user}" -d "${source_db}" -Fc --no-owner --no-acl -f "${dump_file}"

echo "Creating ${target_db}"
createdb -h "${host}" -p "${port}" -U "${user}" "${target_db}"

echo "Restoring ${target_db}"
pg_restore --no-owner --no-acl -f - "${dump_file}" \
    | sed '/^SET transaction_timeout = 0;$/d' \
    | psql -h "${host}" -p "${port}" -U "${user}" -d "${target_db}" -v ON_ERROR_STOP=1 -P pager=off -q

source_relations="$(relation_count "${source_db}")"
target_relations="$(relation_count "${target_db}")"
source_rows="$(exact_row_total "${source_db}")"
target_rows="$(exact_row_total "${target_db}")"

echo "Source relations: ${source_relations}"
echo "Target relations: ${target_relations}"
echo "Source rows: ${source_rows}"
echo "Target rows: ${target_rows}"

if [ "${source_relations}" != "${target_relations}" ] || [ "${source_rows}" != "${target_rows}" ]; then
    echo "Replica verification failed: source and target counts differ." >&2
    exit 1
fi

if [ "${write_config}" = "1" ]; then
    instance_config_dir="${cluster_config_path}/${package}/_instances/${workspace}"
    mkdir -p "${instance_config_dir}"
    printf '%s' "${target_db}" > "${instance_config_dir}/db-name"
    echo "Wrote ${instance_config_dir}/db-name"
fi

echo "Replica complete."
