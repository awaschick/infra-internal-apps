#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <dagster-version> <destination-root>" >&2
  exit 1
fi

version="$1"
dest_root="$2"
dest_dir="${dest_root}/dagster-${version}"
archive_url="https://dagster-io.github.io/helm/dagster-${version}.tgz"
tmp_dir="$(mktemp -d)"

cleanup() {
  rm -rf "${tmp_dir}"
}

trap cleanup EXIT

mkdir -p "${dest_root}"
rm -rf "${dest_dir}"
mkdir -p "${dest_dir}"

curl -fsSL "${archive_url}" -o "${tmp_dir}/dagster.tgz"
tar -xzf "${tmp_dir}/dagster.tgz" -C "${dest_dir}"

# The published Dagster charts reference kubernetesjsonschema.dev in their values schemas.
# Strip schema files so installs do not depend on that external endpoint.
find "${dest_dir}" -name 'values.schema.json' -delete

if [[ ! -f "${dest_dir}/dagster/Chart.yaml" ]]; then
  echo "Vendored chart is missing ${dest_dir}/dagster/Chart.yaml" >&2
  exit 1
fi

echo "Vendored Dagster chart ${version} into ${dest_dir}"
