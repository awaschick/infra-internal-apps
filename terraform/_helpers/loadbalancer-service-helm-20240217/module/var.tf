
variable "kubeconfig_path" { default = "/etc/rancher/rke/kube_config_cluster.yml" }
variable "values_template" { default = "default" }

variable "instance_name" { default = "foo" }
variable "kubernetes_namespace" { default = "default" }
variable "service_port_1" { default = "22" }
variable "service_port_2" { default = "" }
variable "service_port_3" { default = "" }
variable "service_port_4" { default = "" }
variable "service_port_5" { default = "" }
variable "service_port_6" { default = "" }

variable "external_port_1" { default = "22" }
variable "external_port_2" { default = "" }
variable "external_port_3" { default = "" }
variable "external_port_4" { default = "" }
variable "external_port_5" { default = "" }
variable "external_port_6" { default = "" }

variable "selector_key" { default = "app" }
variable "selector_value" { default = "foobar" }
variable "selector_key_2" { default = "" }
variable "selector_value_2" { default = "" }
variable "selector_key_3" { default = "" }
variable "selector_value_3" { default = "" }
variable "ingress_address" { default = "0.0.0.0" }
