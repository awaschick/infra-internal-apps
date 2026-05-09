terraform {
  required_version = ">= 1.5"
  backend "local" {
    path          = "../_state/project-intake-portal"
    workspace_dir = "../_state/project-intake-portal-workspaces"
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
  module_name          = "project-intake-portal"
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

      { package = "aws-rds-postgres", option = "endpoint" },
      { package = "aws-rds-postgres", option = "db-port" },
      { package = "aws-rds-postgres", option = "db-username" },
      { package = "aws-rds-postgres", option = "db-password" },

      { package = "project-intake-portal", option = "app-name" },
      { package = "project-intake-portal", option = "kubernetes-namespace" },
      { package = "project-intake-portal", option = "node-group-name" },
      { package = "project-intake-portal", option = "alb-name" },
      { package = "project-intake-portal", option = "site-hostname" },
      { package = "project-intake-portal", option = "image-uri" },
      { package = "project-intake-portal", option = "image-pull-policy" },
      { package = "project-intake-portal", option = "container-port" },
      { package = "project-intake-portal", option = "service-port" },
      { package = "project-intake-portal", option = "replicas" },
      { package = "project-intake-portal", option = "db-name" },
      { package = "project-intake-portal", option = "jwt-secret" },
      { package = "project-intake-portal", option = "jwt-issuer" },
      { package = "project-intake-portal", option = "log-level" },
      { package = "project-intake-portal", option = "storage-class" },
      { package = "project-intake-portal", option = "project-files-volume-size" },
      { package = "project-intake-portal", option = "seed-database-on-start" },
      { package = "project-intake-portal", option = "anthropic-api-key" },
      { package = "project-intake-portal", option = "openai-api-key" },
      { package = "project-intake-portal", option = "slack-bot-token" },
      { package = "project-intake-portal", option = "slack-app-token" },
      { package = "project-intake-portal", option = "slack-signing-secret" },
      { package = "project-intake-portal", option = "azure-tenant-id" },
      { package = "project-intake-portal", option = "azure-client-id" },
      { package = "project-intake-portal", option = "azure-client-secret" },
      { package = "project-intake-portal", option = "dropbox-access-token" },
      { package = "project-intake-portal", option = "granola-api-key" },
      { package = "project-intake-portal", option = "google-service-account-key-json" },
      { package = "project-intake-portal", option = "spreadsheet-id" },
      { package = "project-intake-portal", option = "sheet-name" },
    ]
    cluster_selection = local.cluster
    cluster_path      = local.cluster_path
    common_path       = "../../config/"
    module_name       = local.module_name
    instance_name     = local.instance_name
  }))

  app_name                  = local.config["project-intake-portal_app-name"]
  namespace_name            = local.config["project-intake-portal_kubernetes-namespace"]
  app_hostname              = local.config["project-intake-portal_site-hostname"]
  app_fqdn                  = "${local.app_hostname}.${local.config["cluster_site-domain"]}"
  alb_name                  = local.config["project-intake-portal_alb-name"]
  image_uri                 = local.config["project-intake-portal_image-uri"]
  image_pull_policy         = local.config["project-intake-portal_image-pull-policy"]
  container_port            = tonumber(local.config["project-intake-portal_container-port"])
  service_port              = tonumber(local.config["project-intake-portal_service-port"])
  replicas                  = tonumber(local.config["project-intake-portal_replicas"])
  database_name             = local.config["project-intake-portal_db-name"]
  storage_class             = local.config["project-intake-portal_storage-class"]
  project_files_volume_size = local.config["project-intake-portal_project-files-volume-size"]
  database_url              = "postgresql://${urlencode(local.config["aws-rds-postgres_db-username"])}:${urlencode(local.config["aws-rds-postgres_db-password"])}@${local.config["aws-rds-postgres_endpoint"]}:${local.config["aws-rds-postgres_db-port"]}/${local.database_name}"
  public_app_base_url       = "https://${local.app_fqdn}"
  project_files_dir         = "/app/backend/data/project-files"
  app_labels = {
    app = "${local.app_name}-web"
  }
  optional_app_env = {
    for key, value in {
      ANTHROPIC_API_KEY               = local.config["project-intake-portal_anthropic-api-key"]
      OPENAI_API_KEY                  = local.config["project-intake-portal_openai-api-key"]
      SLACK_BOT_TOKEN                 = local.config["project-intake-portal_slack-bot-token"]
      SLACK_APP_TOKEN                 = local.config["project-intake-portal_slack-app-token"]
      SLACK_SIGNING_SECRET            = local.config["project-intake-portal_slack-signing-secret"]
      AZURE_TENANT_ID                 = local.config["project-intake-portal_azure-tenant-id"]
      AZURE_CLIENT_ID                 = local.config["project-intake-portal_azure-client-id"]
      AZURE_CLIENT_SECRET             = local.config["project-intake-portal_azure-client-secret"]
      DROPBOX_ACCESS_TOKEN            = local.config["project-intake-portal_dropbox-access-token"]
      GRANOLA_API_KEY                 = local.config["project-intake-portal_granola-api-key"]
      GOOGLE_SERVICE_ACCOUNT_KEY_JSON = local.config["project-intake-portal_google-service-account-key-json"]
      SPREADSHEET_ID                  = local.config["project-intake-portal_spreadsheet-id"]
      SHEET_NAME                      = local.config["project-intake-portal_sheet-name"]
    } : key => value if trimspace(value) != ""
  }
  app_env = merge({
    ALLOWED_ORIGIN          = local.public_app_base_url
    APP_BASE_URL            = local.public_app_base_url
    AZURE_REDIRECT_URI      = "${local.public_app_base_url}/api/auth/azure/callback"
    DATABASE_URL            = local.database_url
    FRONTEND_DIST_DIR       = "/app/frontend/dist"
    JWT_SECRET              = local.config["project-intake-portal_jwt-secret"]
    JWT_ISSUER              = local.config["project-intake-portal_jwt-issuer"]
    LOG_DIR                 = "/app/backend/logs"
    LOG_LEVEL               = local.config["project-intake-portal_log-level"]
    NODE_ENV                = "production"
    PGDATABASE              = local.database_name
    PGHOST                  = local.config["aws-rds-postgres_endpoint"]
    PGPASSWORD              = local.config["aws-rds-postgres_db-password"]
    PGPORT                  = local.config["aws-rds-postgres_db-port"]
    PGUSER                  = local.config["aws-rds-postgres_db-username"]
    PORT                    = tostring(local.container_port)
    PORTAL_BASE_URL         = local.public_app_base_url
    PORTAL_DATA_DIR         = "/app/backend/data"
    PROJECT_FILES_DIR       = local.project_files_dir
    RUN_DATABASE_MIGRATIONS = "true"
    SEED_DATABASE_ON_START  = local.config["project-intake-portal_seed-database-on-start"]
  }, local.optional_app_env)
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
      "scheduling.atlas/default-node-group" = local.config["project-intake-portal_node-group-name"]
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

resource "kubernetes_persistent_volume_claim_v1" "project_files" {
  metadata {
    name      = "${local.app_name}-project-files"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = local.storage_class

    resources {
      requests = {
        storage = local.project_files_volume_size
      }
    }
  }
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

          env_from {
            secret_ref {
              name = kubernetes_secret_v1.app_env.metadata[0].name
            }
          }

          volume_mount {
            name       = "project-files"
            mount_path = local.project_files_dir
          }

          readiness_probe {
            http_get {
              path = "/api/health"
              port = local.container_port
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }

          liveness_probe {
            http_get {
              path = "/api/health"
              port = local.container_port
            }
            initial_delay_seconds = 30
            period_seconds        = 20
          }
        }

        volume {
          name = "project-files"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.project_files.metadata[0].name
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
      "alb.ingress.kubernetes.io/healthcheck-path"   = "/api/health"
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

output "project_intake_portal_url" {
  value = local.public_app_base_url
}

output "project_intake_portal_instance" {
  value = local.deployment_instance
}
