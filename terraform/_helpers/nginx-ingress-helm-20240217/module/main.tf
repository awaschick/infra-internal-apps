terraform {
  required_version = ">= 1.5"
  required_providers {
    helm = {
      source = "hashicorp/helm"
    }
  }
}

provider "helm" {
  kubernetes = {
    config_path = var.kubeconfig
  }
}

resource "helm_release" "nginx-ingress" {
  name             = "${var.instance_name}-ingress"
  chart            = "${path.module}/yaml-wrapper"
  namespace        = var.kubernetes_namespace
  create_namespace = false
  cleanup_on_fail  = true

  set = [
    {
      name  = "instance_name"
      value = var.instance_name
    },
    {
      name  = "site_fqdn"
      value = var.site_fqdn
    },
    {
      name  = "credential_name"
      value = var.credential_name
    },
    {
      name  = "certmanager_issuer"
      value = var.certmanager_issuer
    },
    {
      name  = "service_port"
      value = var.service_port
    }
  ]
}
