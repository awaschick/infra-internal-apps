terraform {
  required_version = ">= 1.5"
  backend "local" {
    path = "../_state/tailscale-subnet-router"
  }
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.19.0"
    }
  }
}

# set variables prefixed with `local.`
# These are defined by files in `config/{package}` and overridden by `_clusters/{selected cluster}/{package}
# variables defined in `options` are used with the format: local.config.{package}_{option}, and will contain
# the contents of the file in that config directory.

locals {
  cluster      = trimspace(file("../../config/_clusters/selection"))
  cluster_path = "../../config/_clusters/${local.cluster}"
  config = jsondecode(templatefile("../_helpers/config.tmpl", {
    options = [
      { package = "tailscale-subnet-router", option = "connector-name" },
      { package = "tailscale-subnet-router", option = "hostname" },
      { package = "tailscale-subnet-router", option = "service-tags" },
      { package = "tailscale-subnet-router", option = "advertised-routes" },
      { package = "tailscale-subnet-router", option = "node-group-name" },

      { package = "tailscale-operator", option = "kubernetes-namespace" },
      { package = "aws-vpc", option = "vpc-cidr" },
    ]
    cluster_selection = local.cluster
    cluster_path      = local.cluster_path
    common_path       = "../../config/"
    }
  ))

  tailscale_tags = [
    for tag in split(",", trimspace(local.config.tailscale-subnet-router_service-tags)) : trimspace(tag)
    if trimspace(tag) != ""
  ]

  advertised_routes_raw = trimspace(local.config.tailscale-subnet-router_advertised-routes)
  advertised_routes = (
    local.advertised_routes_raw == ""
    ? [trimspace(local.config.aws-vpc_vpc-cidr)]
    : [for route in split(",", local.advertised_routes_raw) : trimspace(route) if trimspace(route) != ""]
  )

  cluster_subnet_router_config_dir_exists = can(fileset("${local.cluster_path}/tailscale-subnet-router", "*"))
}

# this is set to /opt/kubeconfigs/default, which is a symlink to whichever cluster's kubeconfig is currently selected
variable "kubeconfig" { type = string }

provider "kubectl" {
  config_path = var.kubeconfig
}

# https://tailscale.com/kb/1441/kubernetes-operator-connector
resource "kubectl_manifest" "tailscale_subnet_router" {
  yaml_body = <<YAML
apiVersion: tailscale.com/v1alpha1
kind: Connector
metadata:
  name: ${local.config.tailscale-subnet-router_connector-name}
  namespace: ${local.config.tailscale-operator_kubernetes-namespace}
spec:
  hostname: ${local.config.tailscale-subnet-router_hostname}
  tags:
${join("\n", [for tag in local.tailscale_tags : "    - ${tag}"])}
  subnetRouter:
    advertiseRoutes:
${join("\n", [for route in local.advertised_routes : "      - ${route}"])}
YAML
}

resource "local_file" "capture_advertised_routes" {
  count    = local.cluster_subnet_router_config_dir_exists ? 1 : 0
  filename = "${local.cluster_path}/tailscale-subnet-router/advertised-routes-effective"
  content  = join(",", local.advertised_routes)
}

output "tailscale_subnet_router_name" {
  value = local.config.tailscale-subnet-router_connector-name
}

output "tailscale_subnet_router_advertised_routes" {
  value = local.advertised_routes
}
