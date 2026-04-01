terraform {
  required_providers {
    helm = {
      source = "hashicorp/helm"
    }
  }
  required_version = ">= 0.13"
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "helm" {
  kubernetes = {
    config_path = var.kubeconfig_path
  }
}

resource "helm_release" "loadbalancer_service_2" {
  name             = "${var.instance_name}-loadbalancer-service"
  chart            = "${path.module}/yaml-wrapper"
  namespace        = var.kubernetes_namespace
  force_update     = true
  create_namespace = true
  values = [templatefile("${path.module}/templates/values-${var.values_template}.yaml.tpl", {
    instance_name        = var.instance_name
    kubernetes_namespace = var.kubernetes_namespace
    service_port_1       = var.service_port_1
    service_port_2       = var.service_port_2
    service_port_3       = var.service_port_3
    service_port_4       = var.service_port_4
    service_port_5       = var.service_port_5
    service_port_6       = var.service_port_6
    external_port_1      = var.external_port_1
    external_port_2      = var.external_port_2
    external_port_3      = var.external_port_3
    external_port_4      = var.external_port_4
    external_port_5      = var.external_port_5
    external_port_6      = var.external_port_6
    selector_key         = var.selector_key
    selector_value       = var.selector_value
    selector_key_2       = var.selector_key_2
    selector_value_2     = var.selector_value_2
    selector_key_3       = var.selector_key_3
    selector_value_3     = var.selector_value_3
    ingress_address      = var.ingress_address
  })]
}
