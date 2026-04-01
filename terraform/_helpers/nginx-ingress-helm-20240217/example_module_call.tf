module "my_service_ingress" {
  source               = "../_helpers/nginx-ingress-helm-20240217/module"
  kubeconfig           = var.kubeconfig
  kubernetes_namespace = var.kubernetes_namespace
  instance_name        = "my_service"
  site_fqdn            = "foobar.com"
  credential_name      = "cert-my_service-foobar.com"
  certmanager_issuer   = "letsencrypt-prod"
  service_port         = "80"
}
