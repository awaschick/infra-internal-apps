terraform {
  required_version = ">= 1.5"
  backend "local" {
    path = "../_state/aws-vpc"
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.28.0"
    }
  }
}

# set variables prefixed with `local.`
# These are defined by files in `config/{package}` and overridden by `_clusters/{selected cluster}/{package}
# variables defined in `options` are used with the format: local.config.{package}_{option}, and will contain
# the contents of the file in that config directory.

locals {
  cluster = file("../../config/_clusters/selection")
  config = jsondecode(templatefile("../_helpers/config.tmpl", {
    options = [

      { package = "aws-vpc", option = "availability-zones" },
      { package = "aws-vpc", option = "public-subnets" },
      { package = "aws-vpc", option = "private-subnets" },
      { package = "aws-vpc", option = "vpc-name" },
      { package = "aws-vpc", option = "vpc-cidr" },

      { package = "aws", option = "region" },
      { package = "aws", option = "aws-access-key" },
      { package = "aws", option = "aws-secret" },
    ]
    cluster_selection = local.cluster
    cluster_path      = "../../config/_clusters/${local.cluster}"
    common_path       = "../../config/"
    }
  ))

  # Parse comma-separated values from config files
  azs             = split(",", trimspace(local.config.aws-vpc_availability-zones))
  public_subnets  = split(",", trimspace(local.config.aws-vpc_public-subnets))
  private_subnets = split(",", trimspace(local.config.aws-vpc_private-subnets))
}

# this is set to /opt/kubeconfigs/default, which is a symlink to whichever cluster's kubeconfig is currently selected
variable "kubeconfig" { type = string }

provider "aws" {
  region     = local.config.aws_region
  access_key = local.config.aws_aws-access-key
  secret_key = local.config.aws_aws-secret
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = local.config.aws-vpc_vpc-name
  cidr = local.config.aws-vpc_vpc-cidr

  azs             = local.azs
  public_subnets  = local.public_subnets
  private_subnets = local.private_subnets

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "local_file" "capture_vpc_id" {
  filename = "${local.config.cluster_path}/aws-vpc/vpc-id"
  content  = module.vpc.vpc_id
}

resource "local_file" "capture_vpc_private_subnet_ids" {
  filename = "${local.config.cluster_path}/aws-vpc/private-subnet-ids"
  content  = join(",", module.vpc.private_subnets)
}

resource "local_file" "capture_vpc_public_subnet_ids" {
  filename = "${local.config.cluster_path}/aws-vpc/public-subnet-ids"
  content  = join(",", module.vpc.public_subnets)
}
