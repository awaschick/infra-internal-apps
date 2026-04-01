#!/bin/bash

source "$(dirname "$0")/common.sh"


if [[ "${prod_image_registry_user}" == "AWS" ]]; then
    printf "\n Verifying ECR repository '${prod_image_registry}/${prod_image_repo}' exists... \n\n"

    output=$(aws ecr --profile ${aws_cli_profile} --region ${aws_region} describe-repositories --repository-names ${prod_image_repo} 2>&1)
    if [ $? -ne 0 ]; then
        if echo ${output} | grep -q RepositoryNotFoundException; then
            aws ecr --profile ${aws_cli_profile} --region ${aws_region}  create-repository --repository-name ${prod_image_repo}
        else
            >&2 echo ${output}
        fi
    fi
fi

printf "\n Pushing deploy tag to registry: \n\n"
    (
        set -x;
        docker push \
            ${prod_image_registry}/${prod_image_repo}:${prod_image_tag}
    )

printf "\n Pushing latest tag to registry: \n\n"
    (
        set -x;
        docker push \
            ${prod_image_registry}/${prod_image_repo}:latest
    )
