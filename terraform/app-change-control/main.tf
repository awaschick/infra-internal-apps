terraform {
  required_version = ">= 1.5"
  backend "local" {
    path          = "../_state/app-change-control"
    workspace_dir = "../_state/app-change-control-workspaces"
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
  module_name          = "app-change-control"
  cluster              = trimspace(file("../../config/_clusters/selection"))
  cluster_path         = "../../config/_clusters/${local.cluster}"
  deployment_instance  = terraform.workspace
  instance_name        = local.deployment_instance == "default" ? "" : local.deployment_instance
  instance_config_path = local.instance_name == "" ? "${local.cluster_path}/${local.module_name}" : "${local.cluster_path}/${local.module_name}/_instances/${local.instance_name}"
  config = jsondecode(templatefile("../_helpers/config-instance.tmpl", {
    options = [
      { package = "aws", option = "region" },
      { package = "aws", option = "aws-access-key" },
      { package = "aws", option = "aws-secret" },

      { package = "cluster", option = "site-domain" },
      { package = "cluster", option = "domain-aws-id" },

      { package = "aws-vpc", option = "private-subnet-ids" },
      { package = "aws-vpc", option = "public-subnet-ids" },

      { package = "aws-rds-postgres", option = "endpoint" },
      { package = "aws-rds-postgres", option = "db-port" },
      { package = "aws-rds-postgres", option = "db-username" },
      { package = "aws-rds-postgres", option = "db-password" },

      { package = "app-change-control", option = "app-name" },
      { package = "app-change-control", option = "kubernetes-namespace" },
      { package = "app-change-control", option = "node-group-name" },
      { package = "app-change-control", option = "alb-name" },
      { package = "app-change-control", option = "site-hostname" },
      { package = "app-change-control", option = "private-deployment" },
      { package = "app-change-control", option = "image-uri" },
      { package = "app-change-control", option = "image-pull-policy" },
      { package = "app-change-control", option = "container-port" },
      { package = "app-change-control", option = "server-port" },
      { package = "app-change-control", option = "service-port" },
      { package = "app-change-control", option = "replicas" },
      { package = "app-change-control", option = "db-name" },
      { package = "app-change-control", option = "jwt-secret" },
      { package = "app-change-control", option = "entra-client-id" },
      { package = "app-change-control", option = "entra-tenant-id" },
    ]
    cluster_selection = local.cluster
    cluster_path      = local.cluster_path
    common_path       = "../../config/"
    module_name       = local.module_name
    instance_name     = local.instance_name
  }))

  app_name            = local.config["app-change-control_app-name"]
  namespace_name      = local.config["app-change-control_kubernetes-namespace"]
  base_app_hostname   = local.config["app-change-control_site-hostname"]
  private_deployment  = tobool(local.config["app-change-control_private-deployment"])
  app_hostname        = local.private_deployment ? "${local.base_app_hostname}.private" : local.base_app_hostname
  app_fqdn            = "${local.app_hostname}.${local.config["cluster_site-domain"]}"
  alb_name            = local.config["app-change-control_alb-name"]
  alb_scheme          = local.private_deployment ? "internal" : "internet-facing"
  alb_exposure_name   = local.private_deployment ? "private" : "public"
  alb_subnet_ids      = [for subnet_id in split(",", local.private_deployment ? local.config["aws-vpc_private-subnet-ids"] : local.config["aws-vpc_public-subnet-ids"]) : trimspace(subnet_id)]
  image_uri           = local.config["app-change-control_image-uri"]
  image_pull_policy   = local.config["app-change-control_image-pull-policy"]
  container_port      = tonumber(local.config["app-change-control_container-port"])
  server_port         = tonumber(local.config["app-change-control_server-port"])
  service_port        = tonumber(local.config["app-change-control_service-port"])
  replicas            = tonumber(local.config["app-change-control_replicas"])
  database_name       = local.config["app-change-control_db-name"]
  entra_client_id     = local.config["app-change-control_entra-client-id"]
  entra_tenant_id     = local.config["app-change-control_entra-tenant-id"]
  database_url        = "postgresql://${urlencode(local.config["aws-rds-postgres_db-username"])}:${urlencode(local.config["aws-rds-postgres_db-password"])}@${local.config["aws-rds-postgres_endpoint"]}:${local.config["aws-rds-postgres_db-port"]}/${local.database_name}"
  public_app_base_url = "https://${local.app_fqdn}"
  app_labels = {
    app = "${local.app_name}-web"
  }
  app_env = merge({
    APP_BASE_URL          = local.public_app_base_url
    DATABASE_URL          = local.database_url
    JWT_SECRET            = local.config["app-change-control_jwt-secret"]
    NODE_ENV              = "production"
    PGDATABASE            = local.database_name
    PGHOST                = local.config["aws-rds-postgres_endpoint"]
    PGPASSWORD            = local.config["aws-rds-postgres_db-password"]
    PGPORT                = local.config["aws-rds-postgres_db-port"]
    PGUSER                = local.config["aws-rds-postgres_db-username"]
    PORT                  = tostring(local.server_port)
    CLIENT_PORT           = tostring(local.container_port)
    API_TARGET            = "http://127.0.0.1:${local.server_port}"
    PREVIEW_ALLOWED_HOSTS = local.app_fqdn
    },
    local.entra_client_id != "" ? {
      ENTRA_CLIENT_ID = local.entra_client_id
    } : {},
    local.entra_tenant_id != "" ? {
      ENTRA_TENANT_ID = local.entra_tenant_id
    } : {},
  )
  app_env_checksum = sha256(jsonencode(local.app_env))
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

  data = local.app_env

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
        annotations = {
          "checksum/app-env" = local.app_env_checksum
        }
      }

      spec {
        container {
          name              = local.app_name
          image             = local.image_uri
          image_pull_policy = local.image_pull_policy

          port {
            container_port = local.container_port
          }

          port {
            container_port = local.server_port
          }

          env_from {
            secret_ref {
              name = kubernetes_secret_v1.app_env.metadata[0].name
            }
          }

          readiness_probe {
            exec {
              command = [
                "sh",
                "-c",
                "wget -q -O /dev/null http://127.0.0.1:${local.container_port}/ && wget -q -O /dev/null http://127.0.0.1:${local.server_port}/api/health",
              ]
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }

          liveness_probe {
            exec {
              command = [
                "sh",
                "-c",
                "wget -q -O /dev/null http://127.0.0.1:${local.container_port}/ && wget -q -O /dev/null http://127.0.0.1:${local.server_port}/api/health",
              ]
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

  lifecycle {
    create_before_destroy = true
  }
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
    name      = "${local.app_name}-${local.alb_exposure_name}"
    namespace = kubernetes_namespace_v1.app.metadata[0].name

    annotations = {
      "kubernetes.io/ingress.class"                  = "alb"
      "alb.ingress.kubernetes.io/scheme"             = local.alb_scheme
      "alb.ingress.kubernetes.io/subnets"            = join(",", local.alb_subnet_ids)
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
  filename = "${local.instance_config_path}/https-fqdn"
  content  = local.public_app_base_url
}

output "app_change_control_url" {
  value = local.public_app_base_url
}

output "app_change_control_instance" {
  value = local.deployment_instance
}
