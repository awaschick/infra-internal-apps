#!/bin/bash

source "$(dirname "$0")/common.sh"

(
    set -x;
    docker buildx build \
      --no-cache \
      --platform ${local_image_platform}\
      -t ${local_image_repo}:${local_image_tag} \
      -f "${project_path}/${docker_file_name}" \
      "${project_path}";
    docker inspect ${local_image_repo}:${local_image_tag};

)
