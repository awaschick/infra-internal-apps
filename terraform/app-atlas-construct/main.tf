terraform {
  required_version = ">= 1.5"
  backend "local" {
    path          = "../_state/app-atlas-construct"
    workspace_dir = "../_state/app-atlas-construct-workspaces"
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
  module_name          = "app-atlas-construct"
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

      { package = "app-atlas-construct", option = "app-name" },
      { package = "app-atlas-construct", option = "kubernetes-namespace" },
      { package = "app-atlas-construct", option = "node-group-name" },
      { package = "app-atlas-construct", option = "alb-name" },
      { package = "app-atlas-construct", option = "site-hostname" },
      { package = "app-atlas-construct", option = "image-uri" },
      { package = "app-atlas-construct", option = "image-pull-policy" },
      { package = "app-atlas-construct", option = "container-port" },
      { package = "app-atlas-construct", option = "server-port" },
      { package = "app-atlas-construct", option = "service-port" },
      { package = "app-atlas-construct", option = "replicas" },
      { package = "app-atlas-construct", option = "storage-class" },
      { package = "app-atlas-construct", option = "construct-data-volume-size" },
      { package = "app-atlas-construct", option = "log-level" },
      { package = "app-atlas-construct", option = "allowed-origin" },
      { package = "app-atlas-construct", option = "construct-data-dir" },
      { package = "app-atlas-construct", option = "clients-json-path" },
      { package = "app-atlas-construct", option = "core-preview-urls-path" },
      { package = "app-atlas-construct", option = "log-dir" },
      { package = "app-atlas-construct", option = "morpheus-data-dir" },
      { package = "app-atlas-construct", option = "architect-token" },
      { package = "app-atlas-construct", option = "entra-client-id" },
      { package = "app-atlas-construct", option = "entra-tenant-id" },
      { package = "app-atlas-construct", option = "vite-entra-client-id" },
      { package = "app-atlas-construct", option = "vite-entra-tenant-id" },
      { package = "app-atlas-construct", option = "anthropic-api-key" },
      { package = "app-atlas-construct", option = "openai-api-key" },
      { package = "app-atlas-construct", option = "bigquery-project-id" },
      { package = "app-atlas-construct", option = "bigquery-dataset" },
      { package = "app-atlas-construct", option = "bigquery-key-json" },
      { package = "app-atlas-construct", option = "bigquery-max-rows" },
      { package = "app-atlas-construct", option = "bigquery-timeout-ms" },
      { package = "app-atlas-construct", option = "slack-bot-token" },
      { package = "app-atlas-construct", option = "slack-app-token" },
      { package = "app-atlas-construct", option = "morpheus-channel-id" },
    ]
    cluster_selection = local.cluster
    cluster_path      = local.cluster_path
    common_path       = "../../config/"
    module_name       = local.module_name
    instance_name     = local.instance_name
  }))

  app_name                   = local.config["app-atlas-construct_app-name"]
  namespace_name             = local.config["app-atlas-construct_kubernetes-namespace"]
  app_hostname               = local.config["app-atlas-construct_site-hostname"]
  app_fqdn                   = "${local.app_hostname}.${local.config["cluster_site-domain"]}"
  alb_name                   = local.config["app-atlas-construct_alb-name"]
  image_uri                  = local.config["app-atlas-construct_image-uri"]
  image_pull_policy          = local.config["app-atlas-construct_image-pull-policy"]
  container_port             = tonumber(local.config["app-atlas-construct_container-port"])
  server_port                = tonumber(local.config["app-atlas-construct_server-port"])
  service_port               = tonumber(local.config["app-atlas-construct_service-port"])
  replicas                   = tonumber(local.config["app-atlas-construct_replicas"])
  storage_class              = local.config["app-atlas-construct_storage-class"]
  construct_data_volume_size = local.config["app-atlas-construct_construct-data-volume-size"]
  public_app_base_url        = "https://${local.app_fqdn}"
  allowed_origin             = trimspace(local.config["app-atlas-construct_allowed-origin"]) != "" ? local.config["app-atlas-construct_allowed-origin"] : local.public_app_base_url
  construct_data_dir         = trimspace(local.config["app-atlas-construct_construct-data-dir"]) != "" ? local.config["app-atlas-construct_construct-data-dir"] : "/app/backend/data"
  clients_json_path          = trimspace(local.config["app-atlas-construct_clients-json-path"]) != "" ? local.config["app-atlas-construct_clients-json-path"] : "${local.construct_data_dir}/clients.json"
  core_preview_urls_path     = trimspace(local.config["app-atlas-construct_core-preview-urls-path"]) != "" ? local.config["app-atlas-construct_core-preview-urls-path"] : "${local.construct_data_dir}/corePreviewUrls.json"
  log_dir                    = trimspace(local.config["app-atlas-construct_log-dir"]) != "" ? local.config["app-atlas-construct_log-dir"] : "${local.construct_data_dir}/logs"
  morpheus_data_dir          = trimspace(local.config["app-atlas-construct_morpheus-data-dir"]) != "" ? local.config["app-atlas-construct_morpheus-data-dir"] : "${local.construct_data_dir}/morpheus"
  vite_entra_client_id       = trimspace(local.config["app-atlas-construct_vite-entra-client-id"]) != "" ? local.config["app-atlas-construct_vite-entra-client-id"] : local.config["app-atlas-construct_entra-client-id"]
  vite_entra_tenant_id       = trimspace(local.config["app-atlas-construct_vite-entra-tenant-id"]) != "" ? local.config["app-atlas-construct_vite-entra-tenant-id"] : local.config["app-atlas-construct_entra-tenant-id"]
  app_labels = {
    app = "${local.app_name}-web"
  }
  optional_app_env = {
    for key, value in {
      ENTRA_CLIENT_ID      = local.config["app-atlas-construct_entra-client-id"]
      ENTRA_TENANT_ID      = local.config["app-atlas-construct_entra-tenant-id"]
      VITE_ENTRA_CLIENT_ID = local.vite_entra_client_id
      VITE_ENTRA_TENANT_ID = local.vite_entra_tenant_id
      ARCHITECT_TOKEN      = local.config["app-atlas-construct_architect-token"]
      ANTHROPIC_API_KEY    = local.config["app-atlas-construct_anthropic-api-key"]
      OPENAI_API_KEY       = local.config["app-atlas-construct_openai-api-key"]
      BIGQUERY_PROJECT_ID  = local.config["app-atlas-construct_bigquery-project-id"]
      BIGQUERY_DATASET     = local.config["app-atlas-construct_bigquery-dataset"]
      BIGQUERY_KEY_JSON    = local.config["app-atlas-construct_bigquery-key-json"]
      BIGQUERY_MAX_ROWS    = local.config["app-atlas-construct_bigquery-max-rows"]
      BIGQUERY_TIMEOUT_MS  = local.config["app-atlas-construct_bigquery-timeout-ms"]
      SLACK_BOT_TOKEN      = local.config["app-atlas-construct_slack-bot-token"]
      SLACK_APP_TOKEN      = local.config["app-atlas-construct_slack-app-token"]
      MORPHEUS_CHANNEL_ID  = local.config["app-atlas-construct_morpheus-channel-id"]
    } : key => value if trimspace(value) != ""
  }
  app_env = merge({
    ALLOWED_ORIGIN         = local.allowed_origin
    API_TARGET             = "http://127.0.0.1:${local.server_port}"
    CLIENT_PORT            = tostring(local.container_port)
    CLIENTS_JSON_PATH      = local.clients_json_path
    CONSTRUCT_DATA_DIR     = local.construct_data_dir
    CONSTRUCT_URL          = local.public_app_base_url
    CORE_PREVIEW_URLS_PATH = local.core_preview_urls_path
    LOG_DIR                = local.log_dir
    LOG_LEVEL              = local.config["app-atlas-construct_log-level"]
    MORPHEUS_DATA_DIR      = local.morpheus_data_dir
    NODE_ENV               = "production"
    PORT                   = tostring(local.server_port)
    PREVIEW_ALLOWED_HOSTS  = local.app_fqdn
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
      "scheduling.atlas/default-node-group" = local.config["app-atlas-construct_node-group-name"]
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

resource "kubernetes_persistent_volume_claim_v1" "construct_data" {
  wait_until_bound = false

  metadata {
    name      = "${local.app_name}-data"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = local.storage_class

    resources {
      requests = {
        storage = local.construct_data_volume_size
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
        node_selector = {
          "workload.atlas/node-group" = local.config["app-atlas-construct_node-group-name"]
        }

        toleration {
          key      = "workload.atlas/node-group"
          operator = "Equal"
          value    = local.config["app-atlas-construct_node-group-name"]
          effect   = "NoSchedule"
        }

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

          volume_mount {
            name       = "construct-data"
            mount_path = local.construct_data_dir
          }

          readiness_probe {
            exec {
              command = [
                "sh",
                "-c",
                "wget -q -O /dev/null http://127.0.0.1:${local.container_port}/ && node -e \"const net=require('net');const s=net.createConnection(${local.server_port},'127.0.0.1');s.setTimeout(2000);s.on('connect',()=>process.exit(0));s.on('timeout',()=>process.exit(1));s.on('error',()=>process.exit(1));\"",
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
                "wget -q -O /dev/null http://127.0.0.1:${local.container_port}/ && node -e \"const net=require('net');const s=net.createConnection(${local.server_port},'127.0.0.1');s.setTimeout(2000);s.on('connect',()=>process.exit(0));s.on('timeout',()=>process.exit(1));s.on('error',()=>process.exit(1));\"",
              ]
            }
            initial_delay_seconds = 30
            period_seconds        = 20
          }
        }

        volume {
          name = "construct-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.construct_data.metadata[0].name
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

output "app_atlas_construct_url" {
  value = local.public_app_base_url
}

output "app_atlas_construct_instance" {
  value = local.deployment_instance
}
