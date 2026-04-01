terraform {
  required_version = ">= 1.5"
  backend "local" {
    path = "../_state/minio-standalone"
  }
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1.1"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.24.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38.0"
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
      { package = "minio-standalone", option = "kubernetes-namespace" },
      { package = "minio-standalone", option = "root-user" },
      { package = "minio-standalone", option = "root-password" },
      { package = "minio-standalone", option = "loadbalancer-ip" },
      { package = "minio-standalone", option = "loadbalancer-site-hostname" },
      { package = "minio-standalone", option = "web-hostname" },
      { package = "minio-standalone", option = "services-hostname" },
      { package = "minio-standalone", option = "storage-class" },
      { package = "cluster", option = "domain-aws-id" },
      { package = "cluster", option = "site-domain" },
      { package = "cert-manager", option = "cluster-issuer-name" },
      { package = "aws", option = "aws-region" },
      { package = "aws", option = "aws-access-key" },
      { package = "aws", option = "aws-secret" },
      { package = "nginx-ingress", option = "gateway-address" },
    ]
    cluster_selection = local.cluster
    cluster_path      = "../../config/_clusters/${local.cluster}"
    common_path       = "../../config/"
    }
  ))
}

# this is set to /opt/kubeconfigs/default, which is a symlink to whichever cluster's kubeconfig is currently selected
variable "kubeconfig" { type = string }

provider "helm" {
  kubernetes = {
    config_path = var.kubeconfig
  }
}

provider "aws" {
  region     = local.config.aws_aws-region
  access_key = local.config.aws_aws-access-key
  secret_key = local.config.aws_aws-secret
}

provider "kubernetes" {
  config_path = var.kubeconfig
}

resource "helm_release" "minio-standalone" {
  name             = "minio-standalone"
  repository       = "https://charts.min.io/"
  chart            = "minio"
  namespace        = local.config.minio-standalone_kubernetes-namespace
  create_namespace = true
  timeout          = 600

  set = [
    {
      name  = "rootUser"
      value = "${local.config.minio-standalone_root-user}"
    },
    {
      name  = "rootPassword"
      value = "${local.config.minio-standalone_root-password}"
    },
    {
      name  = "persistence.storageClass"
      value = "${local.config.minio-standalone_storage-class}"
    },
    {
      name  = "mode"
      value = "standalone"
    },
    {
      name  = "drivesPerNode"
      value = "1"
    },
    {
      name  = "replicas"
      value = "1"
    },
    {
      name  = "zones"
      value = "1"
    }
  ]
}

resource "aws_route53_record" "minio_loadbalancer_dns_record" {
  zone_id = local.config.cluster_domain-aws-id
  name    = "${local.config.minio-standalone_loadbalancer-site-hostname}.${local.config.cluster_site-domain}"
  type    = "A"
  ttl     = 300
  records = [local.config.minio-standalone_loadbalancer-ip]
}

resource "aws_route53_record" "minio_web_dns_record" {
  zone_id = local.config.cluster_domain-aws-id
  name    = "${local.config.minio-standalone_web-hostname}.${local.config.cluster_site-domain}"
  type    = "A"
  ttl     = 300
  records = [local.config.nginx-ingress_gateway-address]
}

module "minio-web-ingress" {
  source               = "../_helpers/nginx-ingress-helm-20240217/module"
  kubeconfig           = var.kubeconfig
  kubernetes_namespace = local.config.minio-standalone_kubernetes-namespace
  instance_name        = "minio-standalone-console"
  site_fqdn            = "${local.config.minio-standalone_web-hostname}.${local.config.cluster_site-domain}"
  credential_name      = "cert-${local.config.minio-standalone_web-hostname}.${local.config.cluster_site-domain}"
  certmanager_issuer   = local.config.cert-manager_cluster-issuer-name
  service_port         = 9001
}

resource "aws_route53_record" "minio_svc_dns_record" {
  zone_id = local.config.cluster_domain-aws-id
  name    = "${local.config.minio-standalone_services-hostname}.${local.config.cluster_site-domain}"
  type    = "A"
  ttl     = 300
  records = [local.config.nginx-ingress_gateway-address]
}

module "minio-svc-ingress" {
  source               = "../_helpers/nginx-ingress-helm-20240217/module"
  kubeconfig           = var.kubeconfig
  kubernetes_namespace = local.config.minio-standalone_kubernetes-namespace
  instance_name        = "minio-standalone"
  site_fqdn            = "${local.config.minio-standalone_services-hostname}.${local.config.cluster_site-domain}"
  credential_name      = "cert-${local.config.minio-standalone_services-hostname}.${local.config.cluster_site-domain}"
  certmanager_issuer   = local.config.cert-manager_cluster-issuer-name
  service_port         = 9000
}
