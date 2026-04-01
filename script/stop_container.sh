#!/bin/bash

source "$(dirname "$0")/common.sh"

printf "\n${div}\n Stopping and removing any instance of ${executing_container_name}... \n${div}\n\n"
docker stop ${executing_container_name} || true

docker rm ${executing_container_name} || true
