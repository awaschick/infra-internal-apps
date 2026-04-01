terraform {
  required_version = ">= 1.5"
  backend "local" {
    path = "../_state/nginx-ingress"
  }
  required_providers {
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
      { package = "nginx-ingress", option = "kubernetes-namespace" },
      { package = "nginx-ingress", option = "gateway-address" },
      { package = "cert-manager", option = "cluster-issuer-name" }
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

resource "helm_release" "nginx-ingress" {
  name             = "nginx-ingress"
  repository       = "https://helm.nginx.com/stable"
  chart            = "nginx-ingress"
  namespace        = local.config.nginx-ingress_kubernetes-namespace
  create_namespace = true
  timeout          = 600

  set = [
    {
      name  = "controller.service.loadBalancerIP"
      value = local.config.nginx-ingress_gateway-address
    },
    {
      name  = "controller.publishService.enabled"
      value = true
    },
    {
      name  = "controller.admissionWebhooks.certManager.enabled"
      value = true
    },
    {
      name  = "controller.allowSnippetAnnotations"
      value = true
    },
    {
      name  = "controller.enableSnippets"
      value = true
    },
    {
      name  = "controller.enableCustomResources"
      value = true
    },
    {
      name  = "controller.config.enable-real-ip"
      value = true
    },
    {
      name  = "controller.config.use-forwarded-headers"
      value = true
    },
    {
      name  = "controller.service.externalTrafficPolicy"
      value = "Local"
    },
    {
      name  = "controller.scope.namespace"
      value = local.config.nginx-ingress_kubernetes-namespace
    },
    # {
    #     name = "controller.tcp.configMapNamespace"
    #     value = kubernetes_namespace.project.metadata[0].name
    # },

    {
      name  = "webhook.enabled"
      value = true
    },
    {
      name  = "rbac.create"
      value = true
    },
    {
      name  = "webhook.enabled"
      value = true
    },
    {
      name  = "ingressShim.defaultIssuerKind"
      value = "ClusterIssuer"
    },
    {
      name  = "ingressShim.defaultIssuerName"
      value = local.config.cert-manager_cluster-issuer-name
    }
  ]
}
