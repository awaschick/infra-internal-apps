#!/bin/bash

source "$(dirname "$0")/common.sh"

docker exec -ti ${executing_container_name} /bin/bash

show_containers="1"
printf "\n${div}\n Remember, container ${executing_container_name} is still running!  Run 'make stop' to shut it down. \n${div}\n\n"
