# Terraform Order of Operations for Cluster Deployment

Each of the modules in this repository's `terraform` directory deploys a certain component into some kind of host or service.  The inventory of modules handles a wide spectrum of resources, beginning at a very fundamental level, such as defining networking rules and computing infrastructure, and goes all the way up to fine-tuning of indvidual components in a service. 

As such, the order in which these modules are deployed is very important. Many components are dependent upon the successful deployment of prior modules. For instance, you can't deploy Apache Doris until you have a Kubernetes cluster.  You can't deploy a Kubernetes cluster in AWS until you define a network for it to run inside. 

This document will describe the optimal sequence of deployment for a data mart instance, when done manually using the `make tf-start {module}` command.  Any automated deployments that perform the same tasks should also follow this order of operations. 

## AWS EKS Deployment

This is our production platform. We use Amazon's *Elastic Kubernetes Service* here, which tightly integrates various Kubernetes APIs to (such as storage and networking) to other managed AWS services. When bringing up an new EKS deployment:

### Start with Configuring your Workspace

- Initialize your workspace, initialize Terraform, if this is the first time you've used the repo: `make tf-init` -- if you have used this repo before, activate the Python virtual-environment directory with `source ".venv/bin/activate`.
- Define your cluster identity: `make k8s-select` and enter a new name (one not found in `config/_clusters`) for the cluster.  It will mark that cluster as the current workspace and initialize the `_clusters/your-cluster-name` directory. 
- Copy selected directories from the base `config` directory for the modules below, along with `aws`, `python`, and `cluster` into your new directory in `_clusters`
- Customize the configuration values you copied into the new settings files.  Remember to avoid putting a carriage-return at the end of the setting value in the file. Each config value file *must* only be 1 line long.

### Deploy Services and Components

- Start up the private network segments and basic security rules that the cluster will run inside:  `make tf-start aws-vpc`
- Deploy the EKS control plane and cluster nodes in Amazon: `make tf-start aws-eks-init`
  - This will take about 15-20 minutes to finish 
- Provision managed PostgreSQL for platform workloads (Dagster state/event storage): `make tf-start aws-rds-postgres`
- Define basic services for cluster ingress, storage, security roles, etc.: `make tf-start aws-eks-base-config`
- Install cert-manager CRDs/controllers for in-cluster certificate issuance: `make tf-start cert-manager`
- Configure cert-manager's Let's Encrypt DNS-01 issuer for Route 53: `make tf-start cert-manager-config`
- Deploy private networking foundation services that will let us connect to internal cluster services via Tailscale: `make tf-start tailscale-operator`
- Advertise private VPC routes to approved Tailscale users (subnet router for private services like RDS): `make tf-start tailscale-subnet-router`
- Deploy Dagster platform services: `make tf-start dagster-eks`
- Initialize EFS workspace path and permissions for non-root Dagster code-server users: `make dagster-efs-workspace-init`

The `doris-v4-eks` module's public MySQL/TLS endpoint now depends on cert-manager being available in the cluster. If `cert-manager.io/v1 Certificate` is not registered yet, Doris deployment will fail when it tries to create the `doris-public-tls` certificate resource.

## Dagster EFS Workspace Initialization

The `dagster-efs-workspace-init` Terraform module now handles the full one-time bootstrap flow:

- Creates a new EFS filesystem
- Creates an NFS security group in the cluster VPC
- Creates EFS mount targets in selected private subnets
- Creates a static Kubernetes PV/PVC backed by that EFS filesystem
- Launches a one-shot Kubernetes Job that creates the workspace directory and applies ownership/mode for non-root usage

Configure these files before running:

- `config/dagster-efs-workspace-init/kubernetes-namespace`
- `config/dagster-efs-workspace-init/efs-filesystem-name`
- `config/dagster-efs-workspace-init/efs-security-group-name`
- `config/dagster-efs-workspace-init/efs-performance-mode`
- `config/dagster-efs-workspace-init/efs-throughput-mode`
- `config/dagster-efs-workspace-init/efs-encrypted`
- `config/dagster-efs-workspace-init/efs-transition-to-ia`
- `config/dagster-efs-workspace-init/mount-target-subnet-ids`
- `config/dagster-efs-workspace-init/nfs-allowed-cidrs`
- `config/dagster-efs-workspace-init/storage-class-name`
- `config/dagster-efs-workspace-init/pv-name`
- `config/dagster-efs-workspace-init/pvc-name`
- `config/dagster-efs-workspace-init/volume-size`
- `config/dagster-efs-workspace-init/pv-reclaim-policy`
- `config/dagster-efs-workspace-init/workspace-path`
- `config/dagster-efs-workspace-init/workspace-owner-uid`
- `config/dagster-efs-workspace-init/workspace-owner-gid`
- `config/dagster-efs-workspace-init/workspace-directory-mode`
- `config/dagster-efs-workspace-init/run-id`

If you need to re-run the initializer Job, increment `run-id` and apply again.
