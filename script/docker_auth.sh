#!/bin/bash

source "$(dirname "$0")/common.sh"

echo "Signing into registry ${prod_image_registry}..."

if [[ "${prod_image_registry_user}" == "AWS" ]]; then
    aws ecr get-login-password --profile ${aws_cli_profile} --region ${aws_region} | docker login --username ${prod_image_registry_user} --password-stdin ${prod_image_registry}
else
    docker login --username ${prod_image_registry_user} ${prod_image_registry}
fi
