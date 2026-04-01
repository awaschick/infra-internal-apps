#!/usr/bin/env bash
set -euo pipefail

# Returns JSON for Terraform external data source.
# Uses AWS's simple "what is my IP" endpoint.
ip="$(curl -s https://checkip.amazonaws.com | tr -d '[:space:]')"

# Basic validation
if [[ ! "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  echo "{\"error\": \"failed to determine public ip\", \"raw\": \"$ip\"}"
  exit 1
fi

echo "{\"cidr\": \"${ip}/32\"}"
