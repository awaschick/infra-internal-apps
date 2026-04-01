terraform {
  required_version = ">= 1.5"
  backend "local" {
    path = "../_state/aws-eks-hello-world"
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


# set variables prefixed with `local.`
# These are defined by files in `config/{package}` and overridden by `_clusters/{selected cluster}/{package}
# variables defined in `options` are used with the format: local.config.{package}_{option}, and will contain
# the contents of the file in that config directory.

locals {
  cluster      = file("../../config/_clusters/selection")
  cluster_path = "../../config/_clusters/${trimspace(local.cluster)}"
  config = jsondecode(templatefile("../_helpers/config.tmpl", {
    options = [
      { package = "aws-eks-init", option = "cluster-name" },

      { package = "aws", option = "region" },
      { package = "aws", option = "aws-access-key" },
      { package = "aws", option = "aws-secret" },

      { package = "cluster", option = "site-domain" },
      { package = "cluster", option = "domain-aws-id" },

      { package = "aws-eks-hello-world", option = "app-name" },
      { package = "aws-eks-hello-world", option = "kubernetes-namespace" },
      { package = "aws-eks-hello-world", option = "node-group-name" },
      { package = "aws-eks-hello-world", option = "alb-name" },
      { package = "aws-eks-hello-world", option = "site-hostname" },
    ]
    cluster_selection = local.cluster
    cluster_path      = "../../config/_clusters/${local.cluster}"
    common_path       = "../../config/"
    }
  ))
}

# this is set to /opt/kubeconfigs/default, which is a symlink to whichever cluster's kubeconfig is currently selected
variable "kubeconfig" { type = string }

provider "kubernetes" {
  config_path = var.kubeconfig
}

provider "aws" {
  region     = local.config.aws_region
  access_key = local.config.aws_aws-access-key
  secret_key = local.config.aws_aws-secret
}


resource "kubernetes_namespace_v1" "ns" {
  metadata {
    name = local.config.aws-eks-hello-world_kubernetes-namespace
    labels = {
      "scheduling.atlas/default-node-group" = local.config.aws-eks-hello-world_node-group-name
    }
  }
}

# --- Hello World app ---
resource "kubernetes_deployment_v1" "hello" {
  metadata {
    name      = "${local.config.aws-eks-hello-world_app-name}-web"
    namespace = kubernetes_namespace_v1.ns.metadata[0].name
    labels    = { app = "${local.config.aws-eks-hello-world_app-name}-web" }
  }

  spec {
    replicas = 2
    selector {
      match_labels = { app = "${local.config.aws-eks-hello-world_app-name}-web" }
    }
    template {
      metadata {
        labels = { app = "${local.config.aws-eks-hello-world_app-name}-web" }
      }
      spec {
        # Rely on namespace default scheduling via Kyverno policy:
        # scheduling.atlas/default-node-group on the namespace drives
        # pod nodeSelector/toleration injection.
        # node_selector = {
        #   "workload.atlas/node-group" = local.config.aws-eks-hello-world_node-group-name
        # }
        #
        # affinity {
        #   node_affinity {
        #     required_during_scheduling_ignored_during_execution {
        #       node_selector_term {
        #         match_expressions {
        #           key      = "workload.atlas/node-group"
        #           operator = "In"
        #           values   = [local.config.aws-eks-hello-world_node-group-name]
        #         }
        #       }
        #     }
        #   }
        # }

        container {
          name  = "nginx"
          image = "nginx:1.27"
          port { container_port = 80 }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "hello" {
  metadata {
    name      = "${local.config.aws-eks-hello-world_app-name}-web"
    namespace = kubernetes_namespace_v1.ns.metadata[0].name
    labels    = { app = "${local.config.aws-eks-hello-world_app-name}-web" }
  }

  spec {
    selector = { app = "${local.config.aws-eks-hello-world_app-name}-web" }
    port {
      name        = "http"
      port        = 80
      target_port = 80
    }
    type = "ClusterIP"
  }
}

resource "aws_acm_certificate" "hello" {
  domain_name       = "${local.config.aws-eks-hello-world_site-hostname}.${local.config.cluster_site-domain}"
  validation_method = "DNS"
}

resource "aws_route53_record" "hello_validation" {
  for_each = {
    for dvo in aws_acm_certificate.hello.domain_validation_options :
    dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  }

  zone_id = local.config.cluster_domain-aws-id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "hello" {
  certificate_arn = aws_acm_certificate.hello.arn
  validation_record_fqdns = [
    for r in aws_route53_record.hello_validation : r.fqdn
  ]
}

# --- Public HTTPS via ALB Ingress ---
resource "kubernetes_ingress_v1" "hello_public" {
  metadata {
    name      = "${local.config.aws-eks-hello-world_app-name}-public"
    namespace = kubernetes_namespace_v1.ns.metadata[0].name

    annotations = {
      # Use AWS Load Balancer Controller (ALB)
      "kubernetes.io/ingress.class" = "alb"

      # Internet-facing ALB
      "alb.ingress.kubernetes.io/scheme" = "internet-facing"

      # Keep it deterministic so Terraform can find the ALB by name later
      "alb.ingress.kubernetes.io/load-balancer-name" = local.config.aws-eks-hello-world_alb-name

      # Listeners: 80 + 443
      "alb.ingress.kubernetes.io/listen-ports" = "[{\"HTTP\":80},{\"HTTPS\":443}]"

      # Redirect 80 -> 443
      "alb.ingress.kubernetes.io/ssl-redirect" = "443"

      # Attach ACM cert to 443 listener
      "alb.ingress.kubernetes.io/certificate-arn" = aws_acm_certificate.hello.arn

      # Target pods directly (common EKS pattern)
      "alb.ingress.kubernetes.io/target-type" = "ip"
    }
  }

  spec {
    rule {
      host = "${local.config.aws-eks-hello-world_site-hostname}.${local.config.cluster_site-domain}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.hello.metadata[0].name
              port { number = 80 }
            }
          }
        }
      }
    }
  }
}

# --- TCP endpoint examples (NLB) ---

# Pretend this is Doris' MySQL interface service inside cluster.
# In real life you'd point selector/ports at your Doris FE service.
resource "kubernetes_service_v1" "tcp_public" {
  metadata {
    name      = "${local.config.aws-eks-hello-world_app-name}-tcp-public"
    namespace = kubernetes_namespace_v1.ns.metadata[0].name

    annotations = {
      # Tell AWS Load Balancer Controller to provision an NLB
      "service.beta.kubernetes.io/aws-load-balancer-type"            = "external"
      "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"

      # Internet-facing NLB
      "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"

      # deterministic LB name
      "service.beta.kubernetes.io/aws-load-balancer-name" = "${local.config.aws-eks-hello-world_app-name}-lb-public-3306"
    }
  }

  spec {
    selector = { app = "${local.config.aws-eks-hello-world_app-name}-web" } # swap this for Doris FE selector
    port {
      name        = "tcp"
      port        = 3306 # Doris MySQL interface is often 9030; adapt as needed
      target_port = 80   # demo: forward to nginx; replace with Doris port
      protocol    = "TCP"
    }
    type = "LoadBalancer"
  }
}

# Internal (VPC-only) NLB, ideal for Tailscale-in-subnet access
# resource "kubernetes_service_v1" "tcp_internal" {
#   metadata {
#     name      = "${local.config.aws-eks-hello-world_app-name}-tcp-internal"
#     namespace = kubernetes_namespace_v1.ns.metadata[0].name
#
#     annotations = {
#       "service.beta.kubernetes.io/aws-load-balancer-type"            = "external"
#       "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
#
#       # Internal scheme makes it VPC-only
#       "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internal"
#
#       # deterministic LB name
#       "service.beta.kubernetes.io/aws-load-balancer-name" = "${local.config.aws-eks-hello-world_app-name}-lb-internal-3306"
#     }
#   }
#
#   spec {
#     selector = { app = "${local.config.aws-eks-hello-world_app-name}-web" } # swap for Doris FE selector
#     port {
#       name        = "tcp"
#       port        = 3306
#       target_port = 80
#       protocol    = "TCP"
#     }
#     type = "LoadBalancer"
#   }
# }

data "aws_lb" "hello_alb" {
  name       = local.config.aws-eks-hello-world_alb-name
  depends_on = [kubernetes_ingress_v1.hello_public]
}

resource "aws_route53_record" "hello_alias" {
  zone_id = local.config.cluster_domain-aws-id
  name    = "${local.config.aws-eks-hello-world_site-hostname}.${local.config.cluster_site-domain}"
  type    = "A"

  alias {
    name                   = data.aws_lb.hello_alb.dns_name
    zone_id                = data.aws_lb.hello_alb.zone_id
    evaluate_target_health = true
  }
}

data "aws_lb" "hello_nlb" {
  name       = "${local.config.aws-eks-hello-world_app-name}-lb-public-3306"
  depends_on = [kubernetes_service_v1.tcp_public]
}

resource "aws_route53_record" "hello_tcp_external_alias" {
  zone_id = local.config.cluster_domain-aws-id
  name    = "${local.config.aws-eks-hello-world_site-hostname}-svc.${local.config.cluster_site-domain}"
  type    = "A"

  alias {
    name                   = data.aws_lb.hello_nlb.dns_name
    zone_id                = data.aws_lb.hello_nlb.zone_id
    evaluate_target_health = true
  }
}

# data "aws_lb" "hello_nlb_internal" {
#   name       = "${local.config.aws-eks-hello-world_app-name}-lb-internal-3306"
#   depends_on = [kubernetes_service_v1.tcp_public]
# }

# resource "aws_route53_record" "hello_tcp_private_alias" {
#   zone_id = local.config.cluster_domain-aws-id
#   name    = "${local.config.aws-eks-hello-world_site-hostname}-svc.private.${local.config.cluster_site-domain}"
#   type    = "A"
#
#   alias {
#     name                   = data.aws_lb.hello_nlb_internal.dns_name
#     zone_id                = data.aws_lb.hello_nlb_internal.zone_id
#     evaluate_target_health = true
#   }
# }

resource "local_file" "capture_https_fqdn" {
  filename = "${local.cluster_path}/aws-eks-hello-world/https-fqdn"
  content  = "https://${local.config.aws-eks-hello-world_site-hostname}.${local.config.cluster_site-domain}"
}

resource "local_file" "capture_public_tcp_service" {
  filename = "${local.cluster_path}/aws-eks-hello-world/public-tcp-service"
  content  = kubernetes_service_v1.tcp_public.metadata[0].name
}

# resource "local_file" "capture_internal_tcp_service" {
#   filename = "${local.cluster_path}/aws-eks-hello-world/internal-tcp-service"
#   content  = kubernetes_service_v1.tcp_internal.metadata[0].name
# }
