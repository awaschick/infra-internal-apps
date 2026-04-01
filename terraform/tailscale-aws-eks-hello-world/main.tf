terraform {
  required_version = ">= 1.5"
  backend "local" {
    path = "../_state/tailscale-aws-eks-hello-world"
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.28.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0.1"
    }
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
  cluster      = file("../../config/_clusters/selection")
  cluster_path = "../../config/_clusters/${trimspace(local.cluster)}"
  config = jsondecode(templatefile("../_helpers/config.tmpl", {
    options = [
      { package = "tailscale-aws-eks-hello-world", option = "endpoint-suffix" },
      { package = "tailscale-aws-eks-hello-world", option = "tailscale-hostname" },
      { package = "tailscale-operator", option = "tailnet-domain" },
      { package = "tailscale-aws-eks-hello-world", option = "route53-enabled" },
      { package = "tailscale-aws-eks-hello-world", option = "route53-hostname" },
      { package = "tailscale-aws-eks-hello-world", option = "service-tags" },

      { package = "aws-eks-hello-world", option = "kubernetes-namespace" },
      { package = "aws-eks-hello-world", option = "app-name" },

      { package = "tailscale-operator", option = "api-key" },
      { package = "tailscale-operator", option = "node-group-name" },

      { package = "cluster", option = "site-domain" },
      { package = "cluster", option = "domain-aws-id" },

      { package = "aws", option = "region" },
      { package = "aws", option = "aws-access-key" },
      { package = "aws", option = "aws-secret" },
    ]
    cluster_selection = local.cluster
    cluster_path      = "../../config/_clusters/${local.cluster}"
    common_path       = "../../config/"
    }
  ))

  tailscale_proxy_class_name = "tailscale-hello-world-${local.config.tailscale-aws-eks-hello-world_endpoint-suffix}"
  tailscale_service_fqdn     = "${local.config.tailscale-aws-eks-hello-world_tailscale-hostname}.${local.config.tailscale-operator_tailnet-domain}"
  route53_record_fqdn        = "${local.config.tailscale-aws-eks-hello-world_route53-hostname}.private.${local.config.cluster_site-domain}"
  tailscale_devices_response = jsondecode(data.http.tailscale_devices.response_body)
  tailscale_matching_devices = [
    for device in try(local.tailscale_devices_response.devices, []) : device
    if lower(trim(device.name, ".")) == lower(local.tailscale_service_fqdn)
  ]
  tailscale_service_ipv4_addrs = [
    for addr in flatten([
      for device in local.tailscale_matching_devices : try(device.addresses, [])
    ]) : addr
    if can(regex("^\\d+\\.\\d+\\.\\d+\\.\\d+$", addr))
  ]
  tailscale_service_private_ip = try(local.tailscale_service_ipv4_addrs[0], null)
}

# this is set to /opt/kubeconfigs/default, which is a symlink to whichever cluster's kubeconfig is currently selected
variable "kubeconfig" { type = string }

provider "aws" {
  region     = local.config.aws_region
  access_key = local.config.aws_aws-access-key
  secret_key = local.config.aws_aws-secret
}

provider "kubernetes" {
  config_path = var.kubeconfig
}

provider "kubectl" {
  config_path = var.kubeconfig
}

resource "kubectl_manifest" "tailscale_aws_eks_hello_world_loadbalancer" {
  yaml_body = <<YAML
apiVersion: v1
kind: Service
metadata:
  name: tailscale-hello-world-${local.config.tailscale-aws-eks-hello-world_endpoint-suffix}
  namespace: ${local.config.aws-eks-hello-world_kubernetes-namespace}
  annotations:
    tailscale.com/proxy-class: ${local.tailscale_proxy_class_name}
    tailscale.com/hostname: ${local.config.tailscale-aws-eks-hello-world_tailscale-hostname}
    tailscale.com/tags: ${local.config.tailscale-aws-eks-hello-world_service-tags}
spec:
  type: LoadBalancer
  loadBalancerClass: tailscale
  ports:
    - name: http
      port: 80
      targetPort: 80
      protocol: TCP
    - name: mysql
      port: 3306
      targetPort: 80
      protocol: TCP
  selector:
    app: ${local.config.aws-eks-hello-world_app-name}-web
YAML

  depends_on = [kubectl_manifest.tailscale_aws_eks_hello_world_proxy_class]
}

data "http" "tailscale_devices" {
  url = "https://api.tailscale.com/api/v2/tailnet/${local.config.tailscale-operator_tailnet-domain}/devices"

  request_headers = {
    Authorization = "Bearer ${trimspace(local.config.tailscale-operator_api-key)}"
    Accept        = "application/json"
  }

  depends_on = [kubectl_manifest.tailscale_aws_eks_hello_world_loadbalancer]
}

resource "aws_route53_record" "tailscale_aws_eks_hello_world_a_record" {
  count = tobool(trimspace(local.config.tailscale-aws-eks-hello-world_route53-enabled)) ? 1 : 0

  zone_id = local.config.cluster_domain-aws-id
  name    = local.route53_record_fqdn
  type    = "A"
  ttl     = 60
  records = [local.tailscale_service_private_ip]

  lifecycle {
    precondition {
      condition     = local.tailscale_service_private_ip != null
      error_message = "Could not find an IPv4 address in Tailscale API for ${local.tailscale_service_fqdn}. Verify the service is healthy, the hostname matches, and tailscale-operator/api-key can read devices."
    }
  }
}

resource "kubectl_manifest" "tailscale_aws_eks_hello_world_proxy_class" {
  yaml_body = <<YAML
apiVersion: tailscale.com/v1alpha1
kind: ProxyClass
metadata:
  name: ${local.tailscale_proxy_class_name}
spec:
  statefulSet:
    pod:
      nodeSelector:
        workload.atlas/node-group: ${local.config.tailscale-operator_node-group-name}
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchExpressions:
                    - key: tailscale.com/managed
                      operator: In
                      values:
                        - "true"
                topologyKey: kubernetes.io/hostname
YAML
}

output "tailscale_hello_world_private_ip" {
  value = local.tailscale_service_private_ip
}

resource "local_file" "capture_tailnet_private_ip" {
  filename = "${local.cluster_path}/tailscale-aws-eks-hello-world/tailnet-ip"
  content  = local.tailscale_service_private_ip
}
