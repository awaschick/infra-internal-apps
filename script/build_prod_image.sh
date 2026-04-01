#!/bin/bash

source "$(dirname "$0")/common.sh"

printf "\n Building local copy of production image: \n\n"
(
    set -x;
    docker buildx build \
      --no-cache \
      --platform ${prod_image_platform}\
      -t ${build_image_repo}:${build_image_version} \
      -f "${project_path}/${docker_file_name}" \
      "${project_path}";
    docker inspect ${build_image_repo}:${build_image_version};
)

printf "\n Tagging local image to deploy specific version tag: \n\n"
    (
        set -x;
        docker tag \
            ${build_image_repo}:${build_image_version} \
            ${prod_image_registry}/${prod_image_repo}:${prod_image_tag}
    )

printf "\n Tagging local image to deploy:latest tag: \n\n"
    (
        set -x;
        docker tag \
            ${build_image_repo}:${build_image_version} \
            ${prod_image_registry}/${prod_image_repo}:latest
    )

