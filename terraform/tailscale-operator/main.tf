terraform {
  required_version = ">= 1.5"
  backend "local" {
    path = "../_state/tailscale-operator"
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
      { package = "tailscale-operator", option = "kubernetes-namespace" },
      { package = "tailscale-operator", option = "client-id" },
      { package = "tailscale-operator", option = "client-secret" },
      { package = "tailscale-operator", option = "hostname" },
      { package = "tailscale-operator", option = "node-group-name" },
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

resource "kubernetes_namespace_v1" "tailscale_operator_namespace" {
  metadata {
    name = local.config.tailscale-operator_kubernetes-namespace
    labels = {
      "scheduling.atlas/default-node-group" = local.config.tailscale-operator_node-group-name
    }
  }
}

# https://tailscale.com/kb/1236/kubernetes-operator
resource "helm_release" "tailscale-operator" {
  name             = "tailscale-operator"
  repository       = "https://pkgs.tailscale.com/helmcharts"
  chart            = "tailscale-operator"
  version          = "1.94.1"
  namespace        = kubernetes_namespace_v1.tailscale_operator_namespace.metadata.0.name
  create_namespace = false
  timeout          = 300
  values = [
    <<EOT
oauth: 
  clientId: "${local.config.tailscale-operator_client-id}"
  clientSecret: "${local.config.tailscale-operator_client-secret}"
operatorConfig:
  hostname: "${local.config.tailscale-operator_hostname}"
  nodeSelector:
    workload.atlas/node-group: "${local.config.tailscale-operator_node-group-name}"
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
            - key: app.kubernetes.io/name
              operator: In
              values:
              - tailscale-operator
          topologyKey: kubernetes.io/hostname
EOT
  ]
}
