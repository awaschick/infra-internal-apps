# Define paths to the scripts managing makefile actions
s_build_local_image = ./script/build_local_image.sh
s_build_local_image_no_cache = ./script/build_local_image_no_cache.sh
s_build_prod_image = ./script/build_prod_image.sh
s_docker_auth = ./script/docker_auth.sh
s_push_prod_image = ./script/push_prod_image.sh
s_run_container = ./script/run_container.sh
s_run_container_foreground = ./script/run_container_foreground.sh
s_show_containers = ./script/show_containers.sh
s_stop_container = ./script/stop_container.sh
s_connect_background_container = ./script/connect_background_container.sh
s_init_terraform = ./script/init_terraform.sh
s_terraform_start = ./script/terraform_start.sh
s_terraform_stop = ./script/terraform_stop.sh
s_terraform_plan = ./script/terraform_plan.sh
s_terraform_import = ./script/terraform_import.sh
s_k8s_status = ./script/k8s_status.sh
s_k8s_monitor = ./script/k8s_monitor.sh
s_k8s_project_shell = ./script/k8s_project_shell.sh
s_doris_pv_usage = ./script/doris_pv_usage.sh
s_doris_pv_resize = ./script/doris_pv_resize.sh
s_doris_force_redeploy = ./script/doris_force_redeploy.sh
s_doris_recovery_status = ./script/doris_recovery_status.sh
s_doris_ready_check = ./script/doris_ready_check.sh
s_doris_sync_root_password = ./script/doris_sync_root_password.sh
s_doris_memory_vitals = ./script/doris_memory_vitals.sh
s_doris_be_log_audit = ./script/doris_be_log_audit.sh
s_choose_cluster = ./script/choose_cluster.sh
s_check_selection = ./script/check_selection.sh

.PHONY: tf-start tf-stop tf-plan

.ONESHELL:
	SHELL = /bin/bash

define run
	@chmod +x $1
	@$1 $2
endef

all:
	@echo "\033[1mCONTAINER BUILD, DEPLOY, AND MANAGEMNENT\033[0m"
	@echo ""
	@echo "This makefile will trigger scripts in the local \033[3m/script\033[0m directory, as defined by values in the \033[3m/config\033[0m directory, deploy and manage workloads in various target Kubernetes environments."
	@echo ""
# 	@echo "These scripts will use the same Dockerfile used for development in the root of the project, but will build it with options defined in the infrastructure config. This should give you decent flexibility in local versus production environments, while still maintaining consistency in internal package selection and configuration."
# 	@echo ""
# 	@echo "\033[1mContainer Building Commands:\033[0m"
# 	@echo "  make build - Build the container for local infrastructure, no caching of layers"
# 	@echo "  make build-quick - Build the container for local infrastructure, with caching"
# 	@echo "  make build-prod - Build the container for production infrastructure"
# 	@echo "  make push-prod - Push the last-built production container image to the designated container registry"
# 	@echo "  make build-push-prod - Build the container for production infrastructure and immediately push it to the registry"
# 	@echo "  make docker-auth - Sign into the designated container registry"
# 	@echo ""
# 	@echo "\033[1mContainer Testing/Execution Commands:\033[0m"
# 	@echo "  make start - Run the container for local infrastructure in the background, building first if necessary"
# 	@echo "  make stop - Terminate the instance of the container running in the background"
# 	@echo "  make connect - Open a console to the instance of the container running in the background"
# 	@echo "  make start-foreground - Run the container for local infrastructure in the foreground, building first if necessary"
# 	@echo ""
	@echo "\033[1mKubernetes Cluster Management Commands:\033[0m"

	@echo "  make k8s-select - Choose which cluster configuration to work with. Defaults to \033[3mlocal\033[0m"
	@echo "  make k8s-status - Get the current state of the selected Kubernetes cluster"
	@echo "  make k8s-monitor {pod} {namespace?} - Tail logs for a pod (auto-finds namespace if omitted)"
	@echo "  make k8s-shell {pod} {namespace?} - Open a shell in a pod (auto-finds namespace if omitted)"
	@echo ""

	@echo "\033[1mDeclarative Infrastructure Commands:\033[0m"
	@echo "  make tf-init  - Install Terraform executable into a local .venv in this directory"
	@echo "  make tf-start {plan} - Deploy one of the terraform plans found in the \033[3m/infrastructure/terraform\033[0m directory"
	@echo "  make tf-stop {plan} - Terminate one of the terraform plans on the target system"
	@echo "  make tf-plan {plan} - Review target state, show proposed deployment steps for a given plan"
# 	@echo "  make tf-import {plan}  - Synchronize the current infrastructure state against the TF module's local state"
	@echo ""

	@echo "\033[1mApplication Management Commands:\033[0m"
	@echo "  \033[1mApache Doris:\033[0m"
	@echo "    make doris-ready-check {namespace?} - Fail unless FE master/quorum, BE alive, and Doris pods are Ready"
	@echo "    make doris-memory-vitals {namespace?} - Check Doris memory pressure, spill-state health, and OOM risk"
	@echo "    make doris-be-log-audit {namespace?} {since?} - Scan all BE pod logs for memory exhaustion errors"
	@echo "      {NAMESPACE=...} {SINCE=4h} {TAIL_LINES=200} {QID=...} {MEMORY_GREP=...}"
	@echo "    make doris-sync-root-password {namespace?} {CURRENT_ROOT_PASSWORD=...} {FORCE=1} - Sync FE root password to config/doris/root-password"
	@echo "    make doris-pv-usage {namespace?} - Show Doris PVCs and FE/BE/CN volume usage"
	@echo "    make doris-pv-resize {namespace?} - Resize existing Doris BE/FE PVCs to configured sizes"
	@echo "    make doris-force-redeploy {namespace?} {NAMESPACE=...} {FORCE=1} {NO_WAIT=1} {GROUP_PAUSE_SECONDS=10} {DORIS_GROUP=fe|be|cn|broker} "
	@echo "      Restart FE->BE->CN->Broker (each highest index to lowest)"
	@echo "    make doris-recovery-status {namespace?} {DORIS_CLUSTER=...} - Show Doris recovery diagnostics and cluster health"


# build:
# 	$(call run, $(s_build_local_image_no_cache) )
#
# build-quick:
# 	$(call run, $(s_build_local_image) )
#
# build-prod:
# 	$(call run, $(s_build_prod_image) )
#
# push-prod:
# 	$(call run, $(s_docker_auth) )
# 	$(call run, $(s_push_prod_image) )
#
# build-push-prod:
# 	$(call run, $(s_docker_auth) )
# 	$(call run, $(s_build_prod_image) )
# 	$(call run, $(s_push_prod_image) )
#
# start:
# 	$(call run, $(s_run_container) )
# 	$(call run, $(s_show_containers) )
#
# start-foreground:
# 	$(call run, $(s_run_container_foreground) )
#
# stop:
# 	$(call run, $(s_stop_container) )
#
# connect:
# 	$(call run, $(s_connect_background_container) )
#
# docker-auth:
# 	$(call run, $(s_docker_auth) )

tf-init:
	$(call run, $(s_check_selection) )
	$(call run, $(s_init_terraform) )

tf-start:
	$(call run, $(s_check_selection) )
	$(call run, $(s_terraform_start),$(filter-out $@,$(MAKECMDGOALS)))

tf-stop:
	$(call run, $(s_check_selection) )
	$(call run, $(s_terraform_stop),$(filter-out $@,$(MAKECMDGOALS)))

tf-plan:
	$(call run, $(s_check_selection) )
	$(call run, $(s_terraform_plan),$(filter-out $@,$(MAKECMDGOALS)))

# tf-import:
# 	$(call run, $(s_check_selection) )
# 	$(call run, $(s_terraform_import),$(filter-out $@,$(MAKECMDGOALS)))

k8s-status:
	$(call run, $(s_check_selection) )
	$(call run, $(s_k8s_status) )

k8s-monitor:
	$(call run, $(s_check_selection) )
	$(call run, $(s_k8s_monitor),$(filter-out $@,$(MAKECMDGOALS)))

k8s-select:
	$(call run, $(s_choose_cluster) )

k8s-shell:
	$(call run, $(s_check_selection) )
	$(call run, $(s_k8s_project_shell),$(filter-out $@,$(MAKECMDGOALS)))

doris-pv-usage:
	$(call run, $(s_check_selection) )
	$(call run, $(s_doris_pv_usage),$(filter-out $@,$(MAKECMDGOALS)))

doris-pv-resize:
	$(call run, $(s_check_selection) )
	$(call run, $(s_doris_pv_resize),$(filter-out $@,$(MAKECMDGOALS)))

doris-force-redeploy:
	$(call run, $(s_check_selection) )
	$(call run, $(s_doris_force_redeploy),$(filter-out $@,$(MAKECMDGOALS)))

doris-recovery-status:
	$(call run, $(s_check_selection) )
	$(call run, $(s_doris_recovery_status),$(filter-out $@,$(MAKECMDGOALS)))

doris-ready-check:
	$(call run, $(s_check_selection) )
	$(call run, $(s_doris_ready_check),$(filter-out $@,$(MAKECMDGOALS)))

doris-memory-vitals:
	$(call run, $(s_check_selection) )
	$(call run, $(s_doris_memory_vitals),$(filter-out $@,$(MAKECMDGOALS)))

doris-be-log-audit:
	$(call run, $(s_check_selection) )
	$(call run, $(s_doris_be_log_audit),$(filter-out $@,$(MAKECMDGOALS)))

doris-sync-root-password:
	$(call run, $(s_check_selection) )
	$(call run, $(s_doris_sync_root_password),$(filter-out $@,$(MAKECMDGOALS)))

%:
	@true
