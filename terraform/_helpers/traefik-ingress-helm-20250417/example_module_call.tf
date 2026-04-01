module "my_service_ingress" {
  source               = "../_helpers/traefik-ingress-helm-20250417/module"
  kubeconfig           = var.kubeconfig
  kubernetes_namespace = var.kubernetes_namespace
  instance_name        = "my_service"
  site_fqdn            = "foobar.com"
  credential_name      = "cert-my_service-foobar.com"
  certmanager_issuer   = "letsencrypt-prod"
  service_port         = "80"
}
