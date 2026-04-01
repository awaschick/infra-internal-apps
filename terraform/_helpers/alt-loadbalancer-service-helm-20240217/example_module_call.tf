module "dremio_coordinator_external" {
  source               = "../_helpers/loadbalancer-service-helm-20240217/module"
  kubeconfig_path      = var.kubeconfig
  kubernetes_namespace = local.kubernetes_namespace
  instance_name        = "dremio-client"
  selector_key         = "app"
  selector_value       = "dremio-coordinator"
  selector_key_2       = "version"
  selector_value_2     = "foobar"
  service_port_1       = "31010"
  external_port_1      = "31010"
  service_port_2       = "32010"
  external_port_2      = "6969"
  values_template      = "default"
  ingress_address      = local.metallb_ingress_address
}

# Omit values you don't want to use, e.g. external_port_1 or selector_key_2
