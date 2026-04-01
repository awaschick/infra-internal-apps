terraform {
  required_version = ">= 1.5"
  backend "local" {
    path = "../_state/cert-manager"
  }
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0.1"
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

provider "kubernetes" {
  config_path = var.kubeconfig
}

resource "kubernetes_namespace_v1" "cert_manager_namespace" {
  metadata {
    name = local.config.cert-manager_kubernetes-namespace
    labels = {
      "scheduling.atlas/default-node-group" = "platform"
    }
  }
}

resource "helm_release" "cert-manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = kubernetes_namespace_v1.cert_manager_namespace.metadata[0].name
  create_namespace = false
  cleanup_on_fail  = true
  wait             = true
  timeout          = 600

  values = [
    <<-EOT
nodeSelector:
  workload.atlas/node-group: platform
tolerations:
  - key: workload.atlas/node-group
    operator: Equal
    value: platform
    effect: NoSchedule
webhook:
  nodeSelector:
    workload.atlas/node-group: platform
  tolerations:
    - key: workload.atlas/node-group
      operator: Equal
      value: platform
      effect: NoSchedule
cainjector:
  nodeSelector:
    workload.atlas/node-group: platform
  tolerations:
    - key: workload.atlas/node-group
      operator: Equal
      value: platform
      effect: NoSchedule
startupapicheck:
  nodeSelector:
    workload.atlas/node-group: platform
  tolerations:
    - key: workload.atlas/node-group
      operator: Equal
      value: platform
      effect: NoSchedule
EOT
  ]

  set = [
    {
      name  = "installCRDs"
      value = true
    }
  ]

  depends_on = [kubernetes_namespace_v1.cert_manager_namespace]
}
