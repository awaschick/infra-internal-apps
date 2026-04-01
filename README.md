# Data Mart Infrastructure Configuration

This directory contains scripts and configuration files to deploy workloads for operating an Apache Doris-based datamart and associated services into a Kubernetes cluster.

## Using these tools

You will find a `Makefile` in this directory that executes a number of scripts (in the `scripts` directory, directed by settings in the `config` directory) that handle tasks to make the container image and code accessible to the Kubernetes environment. Other scripts will initialize that environment with support services (using Terraform plans in the `terraform` directory,) and then launch the project container and mount this project directory at the expected container path, in the same way `docker-compose.yml` does when in local development. 

You can get a list of possible commands by opening this directory with a terminal and using the `make` command.  This will describe all options, which consist of:

### Declarative Infrastructure Commands

-  `make tf-init`  - Install Terraform executable into a local .venv in this directory.
-  `make tf-start {plan}`  - Deploy one of the terraform plans found in the `terraform` directory.
-  `make tf-stop {plan}`  - Terminate one of the terraform plans on the target system
-  `make tf-plan {plan}`  - Review target state, show proposed deployment steps for a given plan.
-  `make k8s-status`  - Get the current state of the selected Kubernetes cluster.
-  `make k8s-select`  - Choose which cluster configuration to work with. Defaults to `local` if not set. Wil also be run for any commands that require cluster-specific configuration, such as the `tf` commands. 
- *Terraform Plans* - Because Terraform is [idempotent](https://en.wikipedia.org/wiki/Idempotence), you can run these commands at any time, regardless of the current installation state. If anything is out of place, it will be reset according to the specification. In practice, you shouldn't need to run most of these once the k3s cluster is set up.  If you do, the order to run them in is:
  - `make tf-{action} cert-manager` - Installs `cert-manager`, which will register SSL certificates for http services hosted in the cluster.  
  - `make tf-{action} cert-manager-config` - Run after cert-manager installation, this defines the certificate valuidation strategy it will use. We will be using the `dns-01` strategy with a subdomain in AWS Route 53.
  - `make tf-{action} ecr-secret-operator ` - Installs a tool that will automatically retrieve a valid authentication token for the k8s environment to pull images from a private AWS Elastic Container Registry. 
  - `make tf-{action} doris` - Installs the Doris data warewhouse server.
  - `make tf-{action} {whatever workload}` - For any other directory in the `terraform` directory

### Application Management Commands

- `make doris-pv-usage {namespace?}` - Show Doris PVCs and FE/BE/CN volume usage.
- `make doris-pv-resize {namespace?}` - Resize existing Doris BE/FE PVCs to configured sizes.
- `make doris-force-redeploy {namespace?}` - Force-delete Doris pods one-by-one in this group order: FE, then BE, then CN, then Broker. Within each group, pods restart in reverse ordinal order (highest node number to lowest), waiting for `Ready` by default. Prompts for typed confirmation.
- `make doris-force-redeploy NAMESPACE=<namespace> FORCE=1` - Same force redeploy behavior, but skips the confirmation prompt.
- `make doris-force-redeploy NAMESPACE=<namespace> FORCE=1 NO_WAIT=1` - Deletes pods in the same FE->BE->CN->Broker order but does not wait for each replacement pod to become `Ready`.
- `make doris-force-redeploy NAMESPACE=<namespace> FORCE=1 GROUP_PAUSE_SECONDS=10` - Adds a pause between component groups during restart.
- `make doris-force-redeploy NAMESPACE=<namespace> DORIS_GROUP=frontend FORCE=1` - Redeploy only FE (frontend) pods.
- `make doris-force-redeploy NAMESPACE=<namespace> DORIS_GROUPS=fe,be FORCE=1` - Redeploy only specific groups, in normal FE->BE->CN->Broker precedence.
- `make doris-recovery-status {namespace?}` - Show recovery diagnostics including DorisCluster status, pod readiness/restarts, services/endpoints, recent events, and FE membership probes.
- `make doris-ready-check {namespace?}` - Strict readiness gate: requires FE quorum with exactly one master, all BE alive, and all Doris FE/BE/CN/Broker pods fully ready.
- `make doris-memory-vitals {namespace?}` - Check Doris memory health signals including node/pod memory pressure, OOMKilled indicators, BE spill configuration/disk pressure, and paging pressure (PSI).
- `make doris-sync-root-password {namespace?}` - Synchronize FE `root` credentials to the configured `doris/root-password`, then verify FE local auth and BE-to-FE auth.

### Installing make & other basic support

The helper scripts (in the `script` directory) are all launched by the ancient and venerable `make` utility, which is controlled by the `Makefile` found at the root of `infrastructure`. 

- On a fresh Linux machine, you may have to install it with this command: `sudo apt install make` 
- On a Mac, you might need to install it with `brew install make`

There are a handful of other miscellaneous tools used to manage terraform and python virtual environment, which also might not be installed. If you're on linux, run the commands: 

- `sudo apt install python3 python3-pip python3-venv`
- `sudo apt install jq`
- `sudo apt install unzip`

### Initial AWS CLI Setup

A few of the contaier-build processes are going to interact with Amazon Web Services in a way that demands software be installed and user settings be defined.  We do this so we can issue commands such as `aws ecr --profile ${aws_cli_profile} --region ${aws_region}  create-repository --repository-name ${prod_image_repo}` that nobody wants to have to type into a console. 

#### Install AWS command-line tools

Your host machine will need to be able to talk with AWS to store container images and define domain name resources. This is done through the `aws` command that comes with the [AWS Command Line Interface](https://aws.amazon.com/cli/). Follow the installation instructions [here](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html) for specific details, but the basic process on a Mac is:

``` bash 
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /
```

After this process completes, verify the `aws` command is properly installed by running the command `aws --version` - which should return something like `aws-cli/2.19.1 Python/3.11.6 Darwin/23.3.0 botocore/2.4.5`

#### Define an AWS profile with valid Access and Secret

After the AWS CLI tools are installed, you'll need to define a profile for interacting with the Atlas infrastructure. In the config files, the default named AWS profile is `atlas` and is defined in `config/aws/cli_profile`. 

Get an appropriately-privileged Access key and Secret key, and edit (or create) the credentials file in your home directory, at  `~/.aws/credentials`. Add a block to the file like so: 

```[atlas]
[atlas]
aws_access_key_id = AKIA0000000000000000
aws_secret_access_key = xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Combined with the `--profile` option, the `aws` command in the helper scripts in this repo will now make use of these credentials.  

### Terraform Initialization

Finally, we need to install Terraform.  We'll do this inside this local directory, using a python `.venv` directory to host it.  And, while the earlier steps are very manual owing to the likelihood of variations in the host machine, this is entirely locally defined and thus, we have a helper command in `make` to do it for us.  Run the command `make tf-init` to establish the .venv and load the proper executables. Make sure you activate the .venv with `source ./.venv/bin/activate` so the scripts can see the command. 

## How Configuration Works

The `config` directory contains a lot of tiny text files, grouped into directories according to what they define. Most files will contain a single line of text—*no carriage return at the end*—that informs the behavior of one (or several) of the `make` actions listed above. 

### Config File Override Levels

There are two levels to configuration files. 

The first is what defines **generic, default, or local-development** values.  These are at the root of the config folder, and define stuff like the Docker registry we should be pushing to, how Terraform is configured, etc. There are a number of placeholder files with bogus values here, though, that serve as a guide to the **cluster-specific** values that are found in the `_clusters` directory. 

This repo is built to eventually accommodate deploying the same project to multiple Kubernetes clusters. This is done by having multiple folders in the `_clusters` directory. You can choose which cluster you want to deploy to by editing the `config/_clusters/selection` file. Within each directory in`_clusters`, you'll find a partial copy of the folders in the root `config` directory.  If a config file for a specific setting is found in the selected cluster config directory, it will be used instead of the generic value in the root config. 

Before you start working with a fresh pull of this repo, though, there will be a number of files that won't be there, since they'd contain credentials or other sensitive data.  We'll have to supply those ourselves, using the instructions below.

### Config files you'll need to supply on your own

Beyond accommodating the `aws` command, we will also need to supply credentials in the `config` directory, so we can deploy our application into the Kubernetes cluster. These files are in `.gitignore` so they won't be committed into the repo, nor be supplied for you on a fresh pull:

- `config/aws/access-key` - This is an AWS IAM key that is attached to privileges that can make updates to Route 53 domains and download container images from Elastic Container Registry. The same one we set up under the `atlas` profile for AWS CLI will work here. 
- `config/aws/access-secret` - The corresponding secret to the access key. 
- `config/aws/account-id` - the numeric ID of the Atlas AWS account that the key and secret are attached to. 
- `config/clusters/{local-cluster-name}/_k8s/kubeconfig` - A YAML-formatted file containing instructions for Terraform and the `kubectl` command to define resources in our local Kubernetes cluster. `kubectl` was installed when we installed k3s. On a k3s installation, a copy of the config file can be found at `/etc/rancher/k3s/k3s.yaml`.  

## Git SSH Keys For Dev Workspace

The `efs-workspace-init-datamart` Terraform plan now supports injecting an arbitrary Git SSH keypair into the dev workspace pod at startup, without baking keys into the container image.

Use cluster-specific overrides so secrets stay local:

1. Create the cluster override directory if needed:
```bash
mkdir -p config/_clusters/$(cat config/_clusters/selection)/efs-workspace-init-datamart
```
2. Place your private key in:
`config/_clusters/<cluster>/efs-workspace-init-datamart/git-ssh-private-key`
3. Place the matching public key in:
`config/_clusters/<cluster>/efs-workspace-init-datamart/git-ssh-public-key`
4. Optional: preseed host keys in:
`config/_clusters/<cluster>/efs-workspace-init-datamart/git-ssh-known-hosts`
5. Apply the workspace plan:
```bash
make tf-start efs-workspace-init-datamart
```

At runtime, the key is copied to `/root/.ssh/id_git` and `GIT_SSH_COMMAND` is set automatically, so cloning `git@github.com:atlas-digital-group/datamart-dagster.git` works with that key.

These cluster-level `git-ssh-*` files are ignored by git via `.gitignore`, so you can rotate or replace keys without committing credentials or rebuilding the workload image.
