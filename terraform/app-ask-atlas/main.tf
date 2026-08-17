terraform {
  required_version = ">= 1.5"
  backend "local" {
    path          = "../_state/app-ask-atlas"
    workspace_dir = "../_state/app-ask-atlas-workspaces"
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
  module_name          = "app-ask-atlas"
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
      { package = "app-ask-atlas", option = "app-name" },
      { package = "app-ask-atlas", option = "kubernetes-namespace" },
      { package = "app-ask-atlas", option = "node-group-name" },
      { package = "app-ask-atlas", option = "alb-name" },
      { package = "app-ask-atlas", option = "site-hostname" },
      { package = "app-ask-atlas", option = "private-deployment" },
      { package = "app-ask-atlas", option = "private-hostname-segment-enabled" },
      { package = "app-ask-atlas", option = "image-uri" },
      { package = "app-ask-atlas", option = "image-pull-policy" },
      { package = "app-ask-atlas", option = "container-port" },
      { package = "app-ask-atlas", option = "service-port" },
      { package = "app-ask-atlas", option = "replicas" },
      { package = "app-ask-atlas", option = "storage-class" },
      { package = "app-ask-atlas", option = "data-volume-size" },
      { package = "app-ask-atlas", option = "log-level" },
      { package = "app-ask-atlas", option = "anthropic-api-key" },
      { package = "app-ask-atlas", option = "anthropic-model" },
      { package = "app-ask-atlas", option = "auth-secret" },
      { package = "app-ask-atlas", option = "entra-tenant-id" },
      { package = "app-ask-atlas", option = "entra-client-id" },
      { package = "app-ask-atlas", option = "entra-admin-group-id" },
      { package = "app-ask-atlas", option = "dropbox-app-key" },
      { package = "app-ask-atlas", option = "dropbox-app-secret" },
      { package = "app-ask-atlas", option = "dropbox-refresh-token" },
      { package = "app-ask-atlas", option = "dropbox-root-namespace-id" },
      { package = "app-ask-atlas", option = "dropbox-base-path" },
      { package = "app-ask-atlas", option = "dropbox-environment" },
      { package = "app-ask-atlas", option = "dropbox-poll-seconds" },
      { package = "app-ask-atlas", option = "dropbox-stable-scans" },
      { package = "app-ask-atlas", option = "dropbox-max-file-bytes" },
      { package = "app-ask-atlas", option = "dropbox-max-package-bytes" },
    ]
    cluster_selection = local.cluster
    cluster_path      = local.cluster_path
    common_path       = "../../config/"
    module_name       = local.module_name
    instance_name     = local.instance_name
  }))

  app_name            = local.config["app-ask-atlas_app-name"]
  namespace_name      = local.config["app-ask-atlas_kubernetes-namespace"]
  base_app_hostname   = local.config["app-ask-atlas_site-hostname"]
  private_deployment  = tobool(local.config["app-ask-atlas_private-deployment"])
  private_hostname    = local.private_deployment && tobool(local.config["app-ask-atlas_private-hostname-segment-enabled"])
  app_hostname        = local.private_hostname ? "${local.base_app_hostname}.private" : local.base_app_hostname
  app_fqdn            = "${local.app_hostname}.${local.config["cluster_site-domain"]}"
  public_app_base_url = "https://${local.app_fqdn}"
  alb_name            = local.config["app-ask-atlas_alb-name"]
  alb_scheme          = local.private_deployment ? "internal" : "internet-facing"
  alb_exposure_name   = local.private_deployment ? "private" : "public"
  alb_subnet_ids      = [for subnet_id in split(",", local.private_deployment ? local.config["aws-vpc_private-subnet-ids"] : local.config["aws-vpc_public-subnet-ids"]) : trimspace(subnet_id)]
  container_port      = tonumber(local.config["app-ask-atlas_container-port"])
  service_port        = tonumber(local.config["app-ask-atlas_service-port"])
  replicas            = tonumber(local.config["app-ask-atlas_replicas"])
  data_dir            = "/app/data"
  import_dir          = "/app/imports"
  dropbox_environment = local.config["app-ask-atlas_dropbox-environment"]
  dropbox_base_path   = trimsuffix(local.config["app-ask-atlas_dropbox-base-path"], "/")
  dropbox_remote_path = "${local.dropbox_base_path}/${local.dropbox_environment}"
  app_labels = {
    app = "${local.app_name}-web"
  }
  app_env = {
    ANTHROPIC_API_KEY           = local.config["app-ask-atlas_anthropic-api-key"]
    ANTHROPIC_MODEL             = local.config["app-ask-atlas_anthropic-model"]
    ASK_ATLAS_DATA_DIR          = local.data_dir
    ASK_ATLAS_IMPORT_DIR        = local.import_dir
    ASK_ATLAS_ENVIRONMENT       = local.dropbox_environment
    AUTH_SECRET                 = local.config["app-ask-atlas_auth-secret"]
    ENTRA_ADMIN_GROUP_ID        = local.config["app-ask-atlas_entra-admin-group-id"]
    ENTRA_CLIENT_ID             = local.config["app-ask-atlas_entra-client-id"]
    ENTRA_TENANT_ID             = local.config["app-ask-atlas_entra-tenant-id"]
    LOG_DIR                     = "${local.data_dir}/logs"
    LOG_LEVEL                   = local.config["app-ask-atlas_log-level"]
    NEXT_PUBLIC_ENTRA_CLIENT_ID = local.config["app-ask-atlas_entra-client-id"]
    NEXT_PUBLIC_ENTRA_TENANT_ID = local.config["app-ask-atlas_entra-tenant-id"]
    NODE_ENV                    = "production"
    PORT                        = tostring(local.container_port)
  }
  app_env_checksum = sha256(jsonencode(local.app_env))
  dropbox_env = {
    DROPBOX_APP_KEY           = local.config["app-ask-atlas_dropbox-app-key"]
    DROPBOX_APP_SECRET        = local.config["app-ask-atlas_dropbox-app-secret"]
    DROPBOX_REFRESH_TOKEN     = local.config["app-ask-atlas_dropbox-refresh-token"]
    DROPBOX_ROOT_NAMESPACE_ID = local.config["app-ask-atlas_dropbox-root-namespace-id"]
    DROPBOX_REMOTE_PATH       = local.dropbox_remote_path
    DROPBOX_LOCAL_DIR         = "/inbox"
    DROPBOX_POLL_SECONDS      = local.config["app-ask-atlas_dropbox-poll-seconds"]
    DROPBOX_STABLE_SCANS      = local.config["app-ask-atlas_dropbox-stable-scans"]
    DROPBOX_MAX_FILE_BYTES    = local.config["app-ask-atlas_dropbox-max-file-bytes"]
    DROPBOX_MAX_PACKAGE_BYTES = local.config["app-ask-atlas_dropbox-max-package-bytes"]
  }
  dropbox_env_checksum = sha256(jsonencode(local.dropbox_env))
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
      "scheduling.atlas/default-node-group" = local.config["app-ask-atlas_node-group-name"]
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

  lifecycle {
    precondition {
      condition = alltrue([
        for value in [
          local.config["app-ask-atlas_anthropic-api-key"],
          local.config["app-ask-atlas_entra-tenant-id"],
          local.config["app-ask-atlas_entra-client-id"],
          local.config["app-ask-atlas_entra-admin-group-id"],
        ] : trimspace(value) != ""
      ]) && length(trimspace(local.config["app-ask-atlas_auth-secret"])) >= 32
      error_message = "Ask Atlas Anthropic, Entra, and admin-group settings must be populated, and auth-secret must contain at least 32 characters."
    }
  }
}

resource "kubernetes_secret_v1" "dropbox_env" {
  metadata {
    name      = "${local.app_name}-dropbox-env"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }

  data = local.dropbox_env
  type = "Opaque"

  lifecycle {
    precondition {
      condition = alltrue([
        for value in [
          local.config["app-ask-atlas_dropbox-app-key"],
          local.config["app-ask-atlas_dropbox-app-secret"],
          local.config["app-ask-atlas_dropbox-refresh-token"],
        ] : trimspace(value) != ""
      ]) && contains(["Production", "Dev", "Test", "UAT"], local.dropbox_environment) && startswith(local.dropbox_base_path, "/")
      error_message = "Ask Atlas Dropbox credentials must be populated; dropbox-environment must be Production, Dev, Test, or UAT; and dropbox-base-path must be absolute."
    }
  }
}

resource "kubernetes_persistent_volume_claim_v1" "app_data" {
  wait_until_bound = false

  metadata {
    name      = "${local.app_name}-data"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = local.config["app-ask-atlas_storage-class"]
    resources {
      requests = {
        storage = local.config["app-ask-atlas_data-volume-size"]
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

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = local.app_labels
    }

    template {
      metadata {
        labels = local.app_labels
        annotations = {
          "checksum/app-env"     = local.app_env_checksum
          "checksum/dropbox-env" = local.dropbox_env_checksum
        }
      }

      spec {
        node_selector = {
          "workload.atlas/node-group" = local.config["app-ask-atlas_node-group-name"]
        }

        toleration {
          key      = "workload.atlas/node-group"
          operator = "Equal"
          value    = local.config["app-ask-atlas_node-group-name"]
          effect   = "NoSchedule"
        }

        container {
          name              = local.app_name
          image             = local.config["app-ask-atlas_image-uri"]
          image_pull_policy = local.config["app-ask-atlas_image-pull-policy"]

          port {
            container_port = local.container_port
          }

          env_from {
            secret_ref {
              name = kubernetes_secret_v1.app_env.metadata[0].name
            }
          }

          volume_mount {
            name       = "app-data"
            mount_path = local.data_dir
          }

          volume_mount {
            name       = "import-inbox"
            mount_path = local.import_dir
            read_only  = true
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

        container {
          name              = "dropbox-materializer"
          image             = local.config["app-ask-atlas_image-uri"]
          image_pull_policy = local.config["app-ask-atlas_image-pull-policy"]
          args              = ["node", "/app/scripts/dropbox-materializer.mjs"]

          env_from {
            secret_ref {
              name = kubernetes_secret_v1.dropbox_env.metadata[0].name
            }
          }

          volume_mount {
            name       = "import-inbox"
            mount_path = "/inbox"
          }
        }

        volume {
          name = "app-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.app_data.metadata[0].name
          }
        }

        volume {
          name = "import-inbox"
          empty_dir {}
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

resource "kubernetes_ingress_v1" "app" {
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
      "alb.ingress.kubernetes.io/healthcheck-path"   = "/api/health"
      "alb.ingress.kubernetes.io/success-codes"      = "200"
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
  records = [kubernetes_ingress_v1.app.status[0].load_balancer[0].ingress[0].hostname]
}

resource "local_file" "capture_https_fqdn" {
  filename = "${local.instance_config_path}/https-fqdn"
  content  = local.public_app_base_url
}

output "app_ask_atlas_url" {
  value = local.public_app_base_url
}

output "app_ask_atlas_instance" {
  value = local.deployment_instance
}
