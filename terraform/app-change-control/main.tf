terraform {
  required_version = ">= 1.5"
  backend "local" {
    path = "../_state/app-change-control"
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.31.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0.1"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.6.2"
    }
  }
}

locals {
  cluster      = trimspace(file("../../config/_clusters/selection"))
  cluster_path = "../../config/_clusters/${local.cluster}"
  config = jsondecode(templatefile("../_helpers/config.tmpl", {
    options = [
      { package = "aws", option = "region" },
      { package = "aws", option = "aws-access-key" },
      { package = "aws", option = "aws-secret" },

      { package = "cluster", option = "site-domain" },
      { package = "cluster", option = "domain-aws-id" },

      { package = "aws-rds-postgres", option = "endpoint" },
      { package = "aws-rds-postgres", option = "db-port" },
      { package = "aws-rds-postgres", option = "db-username" },
      { package = "aws-rds-postgres", option = "db-password" },

      { package = "app-change-control", option = "app-name" },
      { package = "app-change-control", option = "kubernetes-namespace" },
      { package = "app-change-control", option = "node-group-name" },
      { package = "app-change-control", option = "alb-name" },
      { package = "app-change-control", option = "site-hostname" },
      { package = "app-change-control", option = "image-uri" },
      { package = "app-change-control", option = "image-pull-policy" },
      { package = "app-change-control", option = "container-port" },
      { package = "app-change-control", option = "service-port" },
      { package = "app-change-control", option = "replicas" },
      { package = "app-change-control", option = "db-name" },
      { package = "app-change-control", option = "jwt-secret" },
    ]
    cluster_selection = local.cluster
    cluster_path      = local.cluster_path
    common_path       = "../../config/"
  }))

  app_name            = local.config["app-change-control_app-name"]
  namespace_name      = local.config["app-change-control_kubernetes-namespace"]
  app_hostname        = local.config["app-change-control_site-hostname"]
  app_fqdn            = "${local.app_hostname}.${local.config["cluster_site-domain"]}"
  alb_name            = local.config["app-change-control_alb-name"]
  image_uri           = local.config["app-change-control_image-uri"]
  image_pull_policy   = local.config["app-change-control_image-pull-policy"]
  container_port      = tonumber(local.config["app-change-control_container-port"])
  service_port        = tonumber(local.config["app-change-control_service-port"])
  replicas            = tonumber(local.config["app-change-control_replicas"])
  database_name       = local.config["app-change-control_db-name"]
  database_url        = "postgresql://${urlencode(local.config["aws-rds-postgres_db-username"])}:${urlencode(local.config["aws-rds-postgres_db-password"])}@${local.config["aws-rds-postgres_endpoint"]}:${local.config["aws-rds-postgres_db-port"]}/${local.database_name}"
  public_app_base_url = "https://${local.app_fqdn}"
  app_labels = {
    app = "${local.app_name}-web"
  }
}

variable "kubeconfig" {
  type = string
}

provider "kubernetes" {
  config_path = var.kubeconfig
}

provider "aws" {
  region     = local.config["aws_region"]
  access_key = local.config["aws_aws-access-key"]
  secret_key = local.config["aws_aws-secret"]
}

resource "kubernetes_namespace_v1" "app" {
  metadata {
    name = local.namespace_name
    labels = {
      "scheduling.atlas/default-node-group" = local.config["app-change-control_node-group-name"]
    }
  }
}

resource "kubernetes_secret_v1" "app_env" {
  metadata {
    name      = "${local.app_name}-env"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }

  data = {
    APP_BASE_URL          = local.public_app_base_url
    DATABASE_URL          = local.database_url
    JWT_SECRET            = local.config["app-change-control_jwt-secret"]
    NODE_ENV              = "production"
    PGDATABASE            = local.database_name
    PGHOST                = local.config["aws-rds-postgres_endpoint"]
    PGPASSWORD            = local.config["aws-rds-postgres_db-password"]
    PGPORT                = local.config["aws-rds-postgres_db-port"]
    PGUSER                = local.config["aws-rds-postgres_db-username"]
    PORT                  = tostring(local.container_port)
    PREVIEW_ALLOWED_HOSTS = local.app_fqdn
  }

  type = "Opaque"
}

resource "kubernetes_deployment_v1" "app" {
  metadata {
    name      = "${local.app_name}-web"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
    labels    = local.app_labels
  }

  spec {
    replicas = local.replicas

    selector {
      match_labels = local.app_labels
    }

    template {
      metadata {
        labels = local.app_labels
      }

      spec {
        container {
          name              = local.app_name
          image             = local.image_uri
          image_pull_policy = local.image_pull_policy

          port {
            container_port = local.container_port
          }

          env_from {
            secret_ref {
              name = kubernetes_secret_v1.app_env.metadata[0].name
            }
          }

          readiness_probe {
            http_get {
              path = "/"
              port = local.container_port
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }

          liveness_probe {
            http_get {
              path = "/"
              port = local.container_port
            }
            initial_delay_seconds = 30
            period_seconds        = 20
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "app" {
  metadata {
    name      = "${local.app_name}-web"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
    labels    = local.app_labels
  }

  spec {
    selector = local.app_labels

    port {
      name        = "http"
      port        = local.service_port
      target_port = local.container_port
    }

    type = "ClusterIP"
  }
}

resource "aws_acm_certificate" "app" {
  domain_name       = local.app_fqdn
  validation_method = "DNS"
}

resource "aws_route53_record" "app_validation" {
  for_each = {
    for dvo in aws_acm_certificate.app.domain_validation_options :
    dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  }

  zone_id = local.config["cluster_domain-aws-id"]
  name    = each.value.name
  type    = each.value.type
  records = [each.value.value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "app" {
  certificate_arn = aws_acm_certificate.app.arn
  validation_record_fqdns = [
    for record in aws_route53_record.app_validation : record.fqdn
  ]
}

resource "kubernetes_ingress_v1" "app_public" {
  wait_for_load_balancer = true

  metadata {
    name      = "${local.app_name}-public"
    namespace = kubernetes_namespace_v1.app.metadata[0].name

    annotations = {
      "kubernetes.io/ingress.class"                  = "alb"
      "alb.ingress.kubernetes.io/scheme"             = "internet-facing"
      "alb.ingress.kubernetes.io/load-balancer-name" = local.alb_name
      "alb.ingress.kubernetes.io/listen-ports"       = "[{\"HTTP\":80},{\"HTTPS\":443}]"
      "alb.ingress.kubernetes.io/ssl-redirect"       = "443"
      "alb.ingress.kubernetes.io/certificate-arn"    = aws_acm_certificate.app.arn
      "alb.ingress.kubernetes.io/target-type"        = "ip"
      "alb.ingress.kubernetes.io/healthcheck-path"   = "/"
      "alb.ingress.kubernetes.io/success-codes"      = "200-399"
    }
  }

  spec {
    rule {
      host = local.app_fqdn

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service_v1.app.metadata[0].name
              port {
                number = local.service_port
              }
            }
          }
        }
      }
    }
  }

  depends_on = [aws_acm_certificate_validation.app]
}

resource "aws_route53_record" "app_cname" {
  zone_id = local.config["cluster_domain-aws-id"]
  name    = local.app_fqdn
  type    = "CNAME"
  ttl     = 60
  records = [kubernetes_ingress_v1.app_public.status[0].load_balancer[0].ingress[0].hostname]
}

resource "local_file" "capture_https_fqdn" {
  filename = "${local.cluster_path}/app-change-control/https-fqdn"
  content  = local.public_app_base_url
}

output "app_change_control_url" {
  value = local.public_app_base_url
}
