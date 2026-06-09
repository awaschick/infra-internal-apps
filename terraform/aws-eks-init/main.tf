terraform {
  required_version = ">= 1.5"
  backend "local" {
    path = "../_state/aws-eks-init"
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.28.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0.1"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3.5"
    }
  }
}


# set variables prefixed with `local.`
# These are defined by files in `config/{package}` and overridden by `_clusters/{selected cluster}/{package}
# variables defined in `options` are used with the format: local.config.{package}_{option}, and will contain
# the contents of the file in that config directory.

locals {
  cluster      = file("../../config/_clusters/selection")
  cluster_path = "../../config/_clusters/${trimspace(local.cluster)}"
  config = jsondecode(templatefile("../_helpers/config.tmpl", {
    options = [
      { package = "aws-vpc", option = "vpc-id" },
      { package = "aws-vpc", option = "private-subnet-ids" },

      { package = "aws-eks-init", option = "cluster-name" },
      { package = "aws-eks-init", option = "cluster-kubernetes-version" },

      # Endpoint access controls (bootstrap-friendly defaults recommended)
      { package = "aws-eks-init", option = "cluster-endpoint-public-access" },
      { package = "aws-eks-init", option = "cluster-endpoint-private-access" },

      # Comma-separated CIDRs OR the literal string AUTO (to use the helper script)
      { package = "aws-eks-init", option = "cluster-endpoint-public-access-cidrs" },

      { package = "aws-eks-init", option = "group-platform-instance-types" },
      { package = "aws-eks-init", option = "group-platform-instance-count" },
      { package = "aws-eks-init", option = "group-platform-disk-size-gb" },

      { package = "aws", option = "region" },
      { package = "aws", option = "aws-access-key" },
      { package = "aws", option = "aws-secret" },
    ]
    cluster_selection = local.cluster
    cluster_path      = local.cluster_path
    common_path       = "../../config/"
    }
  ))

  # Parse comma-separated subnet IDs from the VPC output file
  subnet_ids = split(",", trimspace(local.config.aws-vpc_private-subnet-ids))
}

# this is set to /opt/kubeconfigs/default, which is a symlink to whichever cluster's kubeconfig is currently selected
variable "kubeconfig" { type = string }

provider "aws" {
  region     = local.config.aws_region
  access_key = local.config.aws_aws-access-key
  secret_key = local.config.aws_aws-secret
}

# Resolve the caller's current public IP for bootstrap allow-listing (optional).
# If config value for `cluster-endpoint-public-access-cidrs` is "AUTO", we'll use this.
data "external" "public_ip" {
  program = ["bash", "${path.module}/../../script/get_public_ip_cidr.sh"]
}

data "aws_caller_identity" "current" {}

locals {
  endpoint_public_access  = tobool(trimspace(local.config.aws-eks-init_cluster-endpoint-public-access))
  endpoint_private_access = tobool(trimspace(local.config.aws-eks-init_cluster-endpoint-private-access))

  endpoint_public_access_cidrs_raw = trimspace(local.config.aws-eks-init_cluster-endpoint-public-access-cidrs)

  endpoint_public_access_cidrs = (
    local.endpoint_public_access_cidrs_raw == "AUTO"
    ? [data.external.public_ip.result.cidr]
    : (
      local.endpoint_public_access_cidrs_raw == ""
      ? []
      : [for c in split(",", local.endpoint_public_access_cidrs_raw) : trimspace(c)]
    )
  )
}

# ---
# Kubernetes provider wiring
#
# This module uses the EKS control plane endpoint (which exists even before nodes join)
# to manage the aws-auth ConfigMap so that managed node groups can register.
#
data "aws_eks_cluster" "this" {
  name       = module.eks.cluster_name
  depends_on = [module.eks]
}

data "aws_eks_cluster_auth" "this" {
  name       = module.eks.cluster_name
  depends_on = [module.eks]
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.14.0"

  name               = local.config.aws-eks-init_cluster-name
  kubernetes_version = local.config.aws-eks-init_cluster-kubernetes-version
  vpc_id             = local.config.aws-vpc_vpc-id
  subnet_ids         = local.subnet_ids
  enable_irsa        = true

  authentication_mode = "API_AND_CONFIG_MAP"

  # Grant admin to whoever is running Terraform (recommended for bootstrap)
  access_entries = {
    terraform_admin = {
      principal_arn = data.aws_caller_identity.current.arn

      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  # Bootstrap-friendly endpoint access:
  # - Private access for nodes and in-VPC clients
  # - Public access for your laptop, restricted by CIDR
  endpoint_public_access       = local.endpoint_public_access
  endpoint_private_access      = local.endpoint_private_access
  endpoint_public_access_cidrs = local.endpoint_public_access_cidrs

  eks_managed_node_groups = {
    platform = {
      instance_types = [local.config.aws-eks-init_group-platform-instance-types]
      desired_size   = local.config.aws-eks-init_group-platform-instance-count
      disk_size      = tonumber(trimspace(local.config.aws-eks-init_group-platform-disk-size-gb))
      subnet_ids     = local.subnet_ids
      min_size       = local.config.aws-eks-init_group-platform-instance-count
      max_size       = max(2, local.config.aws-eks-init_group-platform-instance-count + 1)
      update_config = {
        max_unavailable = 1
      }
      labels = {
        "workload.atlas/node-group" = "platform"
      }
      taints = {
        dedicated = {
          key    = "workload.atlas/node-group"
          value  = "platform"
          effect = "NO_SCHEDULE"
        }
      }
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 2
      }
    }
  }
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = module.eks.cluster_name
  addon_name   = "vpc-cni"
  # addon_version = "..." # optional
  resolve_conflicts_on_create = "OVERWRITE"
}

resource "aws_eks_addon" "coredns" {
  cluster_name = module.eks.cluster_name
  addon_name   = "coredns"
  configuration_values = jsonencode({
    nodeSelector = {
      "workload.atlas/node-group" = "platform"
    }
    tolerations = [
      {
        key    = "node-role.kubernetes.io/control-plane"
        effect = "NoSchedule"
      },
      {
        key      = "CriticalAddonsOnly"
        operator = "Exists"
      },
      {
        key      = "workload.atlas/node-group"
        operator = "Equal"
        value    = "platform"
        effect   = "NoSchedule"
      }
    ]
  })
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
}

resource "aws_eks_addon" "metrics_server" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "metrics-server"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  configuration_values = jsonencode({
    tolerations = [
      {
        key      = "CriticalAddonsOnly"
        operator = "Exists"
      },
      {
        key      = "workload.atlas/node-group"
        operator = "Equal"
        value    = "platform"
        effect   = "NoSchedule"
      }
    ]
  })
}

locals {
  # Map each managed node group's IAM role into the standard aws-auth role mapping.
  # This authorizes kubelet bootstrap + node registration.
  eks_managed_node_role_arns = [for _, ng in module.eks.eks_managed_node_groups : ng.iam_role_arn]

  aws_auth_roles = [
    for arn in local.eks_managed_node_role_arns : {
      rolearn  = arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups   = ["system:bootstrappers", "system:nodes"]
    }
  ]
}

resource "local_file" "eks_kubeconfig" {
  filename = "${local.cluster_path}/_k8s/kubeconfig"

  content = <<-YAML
apiVersion: v1
kind: Config
clusters:
- name: ${module.eks.cluster_name}
  cluster:
    server: ${module.eks.cluster_endpoint}
    certificate-authority-data: ${module.eks.cluster_certificate_authority_data}

contexts:
- name: ${module.eks.cluster_name}
  context:
    cluster: ${module.eks.cluster_name}
    user: aws

current-context: ${module.eks.cluster_name}

users:
- name: aws
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      command: aws
      args:
        - eks
        - get-token
        - --cluster-name
        - ${module.eks.cluster_name}
        - --region
        - ${local.config.aws_region}
YAML
}

resource "local_file" "capture_eks_cluster_id" {
  filename = "${local.cluster_path}/aws-eks-init/cluster-id"
  content  = module.eks.cluster_name
}

resource "local_file" "capture_eks_cluster_endpoint" {
  filename = "${local.cluster_path}/aws-eks-init/cluster-endpoint"
  content  = module.eks.cluster_endpoint
}

resource "local_file" "capture_eks_oidc_provider_arn" {
  filename = "${local.cluster_path}/aws-eks-init/oidc-provider-arn"
  content  = module.eks.oidc_provider_arn
}

resource "local_file" "capture_eks_oidc_provider" {
  filename = "${local.cluster_path}/aws-eks-init/oidc-provider"
  content  = module.eks.oidc_provider
}

resource "local_file" "capture_eks_cluster_ca_certificate" {
  filename = "${local.cluster_path}/aws-eks-init/ca-certificate"
  content  = module.eks.cluster_certificate_authority_data
}

resource "local_file" "capture_eks_kms_key_arn" {
  filename = "${local.cluster_path}/aws-eks-init/kms-key-arn"
  content  = module.eks.kms_key_arn
}

resource "local_file" "capture_eks_platform_node_role_arn" {
  filename = "${local.cluster_path}/aws-eks-init/group-platform-role-arn"
  content  = module.eks.eks_managed_node_groups["platform"].iam_role_arn
}
