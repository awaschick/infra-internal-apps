terraform {
  required_version = ">= 1.5"
  backend "local" {
    path          = "../_state/app-atlas-time"
    workspace_dir = "../_state/app-atlas-time-workspaces"
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
  module_name          = "app-atlas-time"
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

      { package = "app-atlas-time", option = "app-name" },
      { package = "app-atlas-time", option = "kubernetes-namespace" },
      { package = "app-atlas-time", option = "node-group-name" },
      { package = "app-atlas-time", option = "alb-name" },
      { package = "app-atlas-time", option = "site-hostname" },
      { package = "app-atlas-time", option = "private-deployment" },
      { package = "app-atlas-time", option = "private-hostname-segment-enabled" },
      { package = "app-atlas-time", option = "image-uri" },
      { package = "app-atlas-time", option = "image-pull-policy" },
      { package = "app-atlas-time", option = "container-port" },
      { package = "app-atlas-time", option = "service-port" },
      { package = "app-atlas-time", option = "replicas" },
      { package = "app-atlas-time", option = "db-name" },
      { package = "app-atlas-time", option = "anthropic-api-key" },
      { package = "app-atlas-time", option = "chronos-model" },
      { package = "app-atlas-time", option = "entra-client-id" },
      { package = "app-atlas-time", option = "entra-tenant-id" },
    ]
    cluster_selection = local.cluster
    cluster_path      = local.cluster_path
    common_path       = "../../config/"
    module_name       = local.module_name
    instance_name     = local.instance_name
  }))

  app_name            = local.config["app-atlas-time_app-name"]
  namespace_name      = local.config["app-atlas-time_kubernetes-namespace"]
  base_app_hostname   = local.config["app-atlas-time_site-hostname"]
  private_deployment  = tobool(local.config["app-atlas-time_private-deployment"])
  private_hostname    = local.private_deployment && tobool(local.config["app-atlas-time_private-hostname-segment-enabled"])
  app_hostname        = local.private_hostname ? "${local.base_app_hostname}.private" : local.base_app_hostname
  app_fqdn            = "${local.app_hostname}.${local.config["cluster_site-domain"]}"
  alb_name            = local.config["app-atlas-time_alb-name"]
  alb_scheme          = local.private_deployment ? "internal" : "internet-facing"
  alb_exposure_name   = local.private_deployment ? "private" : "public"
  alb_subnet_ids      = [for subnet_id in split(",", local.private_deployment ? local.config["aws-vpc_private-subnet-ids"] : local.config["aws-vpc_public-subnet-ids"]) : trimspace(subnet_id)]
  image_uri           = local.config["app-atlas-time_image-uri"]
  image_pull_policy   = local.config["app-atlas-time_image-pull-policy"]
  container_port      = tonumber(local.config["app-atlas-time_container-port"])
  service_port        = tonumber(local.config["app-atlas-time_service-port"])
  replicas            = tonumber(local.config["app-atlas-time_replicas"])
  database_name       = local.config["app-atlas-time_db-name"]
  entra_client_id     = local.config["app-atlas-time_entra-client-id"]
  entra_tenant_id     = local.config["app-atlas-time_entra-tenant-id"]
  database_url        = "postgresql://${urlencode(local.config["aws-rds-postgres_db-username"])}:${urlencode(local.config["aws-rds-postgres_db-password"])}@${local.config["aws-rds-postgres_endpoint"]}:${local.config["aws-rds-postgres_db-port"]}/${local.database_name}?sslmode=require&connect_timeout=5&pool_timeout=5"
  public_app_base_url = "https://${local.app_fqdn}"
  app_labels = {
    app = "${local.app_name}-web"
  }
  app_env = {
    APP_URL           = local.public_app_base_url
    DATABASE_URL      = local.database_url
    NODE_ENV          = "production"
    PORT              = tostring(local.container_port)
    FRONTEND_DIST_DIR = "/app/client/dist"
    LOG_TO_FILE       = "false"
    LOG_TO_CONSOLE    = "true"
    ENTRA_CLIENT_ID   = local.entra_client_id
    ENTRA_TENANT_ID   = local.entra_tenant_id
    ANTHROPIC_API_KEY = local.config["app-atlas-time_anthropic-api-key"]
    CHRONOS_MODEL     = local.config["app-atlas-time_chronos-model"]
  }

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
      "scheduling.atlas/default-node-group" = local.config["app-atlas-time_node-group-name"]
    }
  }
}

resource "kubernetes_secret_v1" "app_env" {
  metadata {
    name      = "${local.app_name}-env"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }

  data = sensitive(local.app_env)

  type = "Opaque"
}

resource "kubernetes_deployment_v1" "app" {
  lifecycle {
    precondition {
      condition     = terraform.workspace == "dev" && local.database_name == "atlas_time_dev" && local.namespace_name == "atlas-time-dev" && local.private_deployment
      error_message = "This initial release is restricted to the private dev namespace and atlas_time_dev database."
    }
    precondition {
      condition     = alltrue([for id in [local.entra_client_id, local.entra_tenant_id] : can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id)) && id != "00000000-0000-0000-0000-000000000000"])
      error_message = "Configure the Atlas Time Entra registration before deployment; use identical IDs at image build time."
    }
    precondition {
      condition     = !endswith(local.image_uri, ":latest")
      error_message = "Use an immutable release tag or digest."
    }
  }
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
          "checksum/app-env" = sensitive(local.app_env_checksum)
        }
      }

      spec {
        node_selector = {
          "workload.atlas/node-group" = local.config["app-atlas-time_node-group-name"]
        }
        toleration {
          key      = "workload.atlas/node-group"
          operator = "Equal"
          value    = local.config["app-atlas-time_node-group-name"]
          effect   = "NoSchedule"
        }
        security_context {
          run_as_non_root = true
          run_as_user     = 1000
          run_as_group    = 1000
        }
        init_container {
          name              = "migrate"
          image             = local.image_uri
          image_pull_policy = local.image_pull_policy
          command           = ["npm", "run", "db:deploy"]
          env_from {
            secret_ref {
              name = kubernetes_secret_v1.app_env.metadata[0].name
            }
          }
        }
        container {
          name              = local.app_name
          image             = local.image_uri
          image_pull_policy = local.image_pull_policy

          port {
            container_port = local.container_port
          }

          resources {
            requests = { cpu = "100m", memory = "256Mi" }
            limits   = { cpu = "1000m", memory = "1Gi" }
          }
          security_context {
            allow_privilege_escalation = false
            capabilities { drop = ["ALL"] }
          }

          env_from {
            secret_ref {
              name = kubernetes_secret_v1.app_env.metadata[0].name
            }
          }

          startup_probe {
            http_get {
              path = "/api/health"
              port = local.container_port
            }
            period_seconds    = 5
            failure_threshold = 30
          }
          readiness_probe {
            http_get {
              path = "/api/ready"
              port = local.container_port
            }
            period_seconds  = 10
            timeout_seconds = 6
          }
          liveness_probe {
            http_get {
              path = "/api/health"
              port = local.container_port
            }
            period_seconds  = 20
            timeout_seconds = 5
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
      "alb.ingress.kubernetes.io/healthcheck-path"   = "/api/ready"
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
  records = [kubernetes_ingress_v1.app_public.status[0].load_balancer[0].ingress[0].hostname]
}

resource "local_file" "capture_https_fqdn" {
  filename = "${local.instance_config_path}/https-fqdn"
  content  = local.public_app_base_url
}

output "app_atlas_time_url" {
  value = local.public_app_base_url
}

output "app_atlas_time_instance" {
  value = local.deployment_instance
}
