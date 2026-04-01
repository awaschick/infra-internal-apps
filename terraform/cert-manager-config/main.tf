terraform {
  required_version = ">= 1.5"
  backend "local" {
    path = "../_state/cert-manager-config"
  }
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1.1"
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
      { package = "cert-manager", option = "kubernetes-namespace" },
      { package = "aws", option = "region" },
      { package = "aws", option = "aws-access-key" },
      { package = "aws", option = "aws-secret" },
      { package = "cert-manager", option = "cert-domain" },
      { package = "cert-manager", option = "cluster-issuer-name" },
      { package = "cert-manager", option = "letsencrypt-server" },
      { package = "cert-manager", option = "letsencrypt-email" }
    ]
    cluster_selection = local.cluster
    cluster_path      = "../../config/_clusters/${local.cluster}"
    common_path       = "../../config/"
    }
  ))
}

# this is set to /opt/kubeconfigs/default, which is a symlink to whichever cluster's kubeconfig is currently selected
variable "kubeconfig" { type = string }

provider "kubernetes" {
  config_path = var.kubeconfig
}

provider "helm" {
  kubernetes = {
    config_path = var.kubeconfig
  }
}

resource "kubernetes_secret" "aws_access" {
  metadata {
    name      = "aws-access-secret"
    namespace = local.config.cert-manager_kubernetes-namespace
  }
  data = {
    aws_secret = local.config.aws_aws-secret
  }
}

resource "helm_release" "letsencrypt-cluster-issuer" {
  name             = "letsencrypt-cluster-issuer"
  chart            = "${path.module}/yaml-wrapper"
  namespace        = local.config.cert-manager_kubernetes-namespace
  create_namespace = false
  cleanup_on_fail  = true

  set = [
    {
      name  = "kubernetes_namespace"
      value = local.config.cert-manager_kubernetes-namespace
    },
    {
      name  = "letsencrypt_server"
      value = local.config.cert-manager_letsencrypt-server
    },
    {
      name  = "letsencrypt_email"
      value = local.config.cert-manager_letsencrypt-email
    },
    {
      name  = "cert_domain"
      value = local.config.cert-manager_cert-domain
    },
    {
      name  = "aws_region"
      value = local.config.aws_region
    },
    {
      name  = "aws_access_key"
      value = local.config.aws_aws-access-key
    },
    {
      name  = "cluster_issuer_name"
      value = local.config.cert-manager_cluster-issuer-name
    },
    {
      name  = "aws_secret_ref_name"
      value = kubernetes_secret.aws_access.metadata.0.name
    }
  ]
}
