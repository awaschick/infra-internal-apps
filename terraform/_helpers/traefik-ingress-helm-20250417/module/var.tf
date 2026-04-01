variable "kubeconfig" { type = string }
variable "kubernetes_namespace" { default = "default" }
variable "instance_name" { default = "my-service" }
variable "site_fqdn" { default = "foobar.com" }
variable "credential_name" { default = "cert-foobar" }
variable "certmanager_issuer" { default = "selfsigned" }
variable "service_port" { default = "80" }
