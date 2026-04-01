#!/bin/bash

source "$(dirname "$0")/common.sh"

env_file_path="${project_path}/${docker_env_filename}"

if [[ ${docker_dev_mode} == "true" ]]; then

    # Build and run
    if [[ "$(docker images -q ${local_image_repo}:${local_image_tag} 2> /dev/null)" == "" ]]; then
        printf "\n${div}\n Docker image \"${local_image_repo}:${local_image_tag}\" doesn't exist, building new version... \n${div}\n\n"
        build_image=1
    fi

    if [[ ${build_image} == 1 ]]; then

        if [[ ${no_cache} == 1 ]]; then
            # build_local_image_no_cache
            source "$(dirname "$0")/build_local_image_no_cache.sh"

        else
            # build_local_image
            source "$(dirname "$0")/build_local_image.sh"

        fi
        echo ""
    fi

    # set the local container name to the locally built version
    executing_image="${local_image_repo}:${local_image_tag}"

else
    # set the local container name to the remote registry version
    executing_image="${prod_image_registry}/${prod_image_repo}:${prod_image_tag}"
fi

(
    set -x;
    docker run \
        -it \
        -d \
        --restart unless-stopped \
        --name ${executing_container_name} \
        --env-file "${env_file_path}" \
        ${executing_image}\
        /bin/bash
)
