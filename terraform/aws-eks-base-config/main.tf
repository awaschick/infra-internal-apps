terraform {
  required_version = ">= 1.5"
  backend "local" {
    path = "../_state/aws-eks-base-config"
  }
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1.1"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.28.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0.1"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.1.3"
    }
  }
}


# set variables prefixed with `local.`
# These are defined by files in `config/{package}` and overridden by `_clusters/{selected cluster}/{package}
# variables defined in `options` are used with the format: local.config.{package}_{option}, and will contain
# the contents of the file in that config directory.

locals {
  cluster = file("../../config/_clusters/selection")
  config = jsondecode(templatefile("../_helpers/config.tmpl", {
    options = [
      { package = "aws-vpc", option = "vpc-id" },
      { package = "aws-vpc", option = "private-subnet-ids" },

      { package = "aws-eks-init", option = "cluster-name" },
      { package = "aws-eks-init", option = "cluster-endpoint" },
      { package = "aws-eks-init", option = "oidc-provider-arn" },
      { package = "aws-eks-init", option = "ca-certificate" },

      { package = "aws-eks-base-config", option = "ebs-csi-chart-version" }, ##
      { package = "aws-eks-base-config", option = "kyverno-chart-version" },
      { package = "aws-eks-base-config", option = "lb-controller-chart-version" },
      { package = "aws-eks-base-config", option = "k8s-storage-default-iops" },
      { package = "aws-eks-base-config", option = "k8s-storage-default-throughput" },
      { package = "aws-eks-base-config", option = "k8s-storage-high-performance-iops" },
      { package = "aws-eks-base-config", option = "k8s-storage-high-performance-throughput" },
      { package = "aws-eks-base-config", option = "s3-csi-addon-enabled" },

      { package = "aws", option = "region" },
      { package = "aws", option = "aws-access-key" },
      { package = "aws", option = "aws-secret" },
    ]
    cluster_selection = local.cluster
    cluster_path      = "../../config/_clusters/${local.cluster}"
    common_path       = "../../config/"
    }
  ))
}

# this is set to /opt/kubeconfigs/default, which is a symlink to whichever cluster's kubeconfig is currently selected
variable "kubeconfig" { type = string }

# provider "kubernetes" {
#     config_path    = var.kubeconfig
# }

provider "kubernetes" {
  host                   = local.config.aws-eks-init_cluster-endpoint
  cluster_ca_certificate = base64decode(local.config.aws-eks-init_ca-certificate)
  token                  = data.aws_eks_cluster_auth.this.token
}

# provider "helm" {
#     kubernetes = {
#         config_path = var.kubeconfig
#     }
# }

provider "helm" {
  kubernetes = {
    host                   = local.config.aws-eks-init_cluster-endpoint
    cluster_ca_certificate = base64decode(local.config.aws-eks-init_ca-certificate)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

provider "kubectl" {
  host                   = local.config.aws-eks-init_cluster-endpoint
  cluster_ca_certificate = base64decode(local.config.aws-eks-init_ca-certificate)
  token                  = data.aws_eks_cluster_auth.this.token
  load_config_file       = false
}

provider "aws" {
  region     = local.config.aws_region
  access_key = local.config.aws_aws-access-key
  secret_key = local.config.aws_aws-secret
}

data "aws_eks_cluster_auth" "this" {
  name = local.config.aws-eks-init_cluster-name
}

resource "kubernetes_namespace_v1" "mount_s3" {
  count = tobool(trimspace(local.config.aws-eks-base-config_s3-csi-addon-enabled)) ? 1 : 0

  metadata {
    name = "mount-s3"
    labels = {
      "scheduling.atlas/default-node-group" = "platform"
    }
  }
}

resource "aws_eks_addon" "s3_csi_driver" {
  count = tobool(trimspace(local.config.aws-eks-base-config_s3-csi-addon-enabled)) ? 1 : 0

  cluster_name = local.config.aws-eks-init_cluster-name
  addon_name   = "aws-mountpoint-s3-csi-driver"
  configuration_values = jsonencode({
    controller = {
      nodeSelector = {
        "workload.atlas/node-group" = "platform"
      }
      tolerations = [
        {
          key      = "workload.atlas/node-group"
          operator = "Equal"
          value    = "platform"
          effect   = "NoSchedule"
        }
      ]
    }
  })

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [kubernetes_namespace_v1.mount_s3]
}

resource "kubernetes_role_v1" "s3_csi_mount_s3_pod_manager" {
  count = tobool(trimspace(local.config.aws-eks-base-config_s3-csi-addon-enabled)) ? 1 : 0

  metadata {
    name      = "s3-csi-driver-controller-mount-s3"
    namespace = "mount-s3"
  }

  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["create", "patch", "update"]
  }

  depends_on = [kubernetes_namespace_v1.mount_s3]
}

resource "kubernetes_role_binding_v1" "s3_csi_mount_s3_pod_manager" {
  count = tobool(trimspace(local.config.aws-eks-base-config_s3-csi-addon-enabled)) ? 1 : 0

  metadata {
    name      = "s3-csi-driver-controller-mount-s3"
    namespace = "mount-s3"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.s3_csi_mount_s3_pod_manager[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "s3-csi-driver-controller-sa"
    namespace = "kube-system"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "s3-csi-driver-sa"
    namespace = "kube-system"
  }

  depends_on = [aws_eks_addon.s3_csi_driver]
}

module "ebs_csi_irsa" {
  source                = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version               = "~> 6.0"
  name                  = "${local.config.aws-eks-init_cluster-name}-ebs-csi"
  attach_ebs_csi_policy = true
  oidc_providers = {
    main = {
      provider_arn               = local.config.aws-eks-init_oidc-provider-arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

resource "helm_release" "aws-ebs-csi-driver" {
  name            = "aws-ebs-csi-driver"
  namespace       = "kube-system"
  repository      = "https://kubernetes-sigs.github.io/aws-ebs-csi-driver"
  chart           = "aws-ebs-csi-driver"
  version         = local.config.aws-eks-base-config_ebs-csi-chart-version
  atomic          = true
  cleanup_on_fail = true
  wait            = true
  timeout         = 600
  values = [
    <<-EOT
controller:
  nodeSelector:
    workload.atlas/node-group: platform
  tolerations:
    - key: workload.atlas/node-group
      operator: Equal
      value: platform
      effect: NoSchedule
EOT
  ]

  set = [
    {
      name  = "controller.serviceAccount.create"
      value = "true"
    },
    {
      name  = "controller.serviceAccount.name"
      value = "ebs-csi-controller-sa"
    },
    {
      name  = "controller.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = module.ebs_csi_irsa.arn
    }
  ]
}

module "lbc_irsa" {
  source                                 = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version                                = "~> 6.0"
  name                                   = "${local.config.aws-eks-init_cluster-name}-aws-lb-controller"
  attach_load_balancer_controller_policy = true
  oidc_providers = {
    main = {
      provider_arn               = local.config.aws-eks-init_oidc-provider-arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "helm_release" "aws-load-balancer-controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = local.config.aws-eks-base-config_lb-controller-chart-version
  # atomic          = true
  cleanup_on_fail = true
  wait            = true
  timeout         = 600
  values = [
    <<-EOT
nodeSelector:
  workload.atlas/node-group: platform
tolerations:
  - key: workload.atlas/node-group
    operator: Equal
    value: platform
    effect: NoSchedule
EOT
  ]

  set = [
    {
      name  = "clusterName"
      value = local.config.aws-eks-init_cluster-name
    },
    {
      name  = "region"
      value = local.config.aws_region
    },
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = "aws-load-balancer-controller"
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = module.lbc_irsa.arn
    }
  ]
}

resource "helm_release" "kyverno" {
  name             = "kyverno"
  namespace        = "kyverno"
  repository       = "https://kyverno.github.io/kyverno/"
  chart            = "kyverno"
  version          = local.config.aws-eks-base-config_kyverno-chart-version
  atomic           = true
  create_namespace = true
  cleanup_on_fail  = true
  wait             = true
  timeout          = 600
  values = [
    <<-EOT
global:
  nodeSelector:
    workload.atlas/node-group: platform
  tolerations:
    - key: workload.atlas/node-group
      operator: Equal
      value: platform
      effect: NoSchedule
policyReportsCleanup:
  enabled: false
webhooksCleanup:
  enabled: false
  nodeSelector:
    workload.atlas/node-group: platform
  tolerations:
    - key: workload.atlas/node-group
      operator: Equal
      value: platform
      effect: NoSchedule
EOT
  ]

  depends_on = [helm_release.aws-load-balancer-controller]
}

resource "kubectl_manifest" "default_node_selector_from_namespace" {
  yaml_body = <<YAML
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: default-node-selector-from-namespace
spec:
  background: false
  rules:
    - name: add-default-node-selector
      match:
        any:
          - resources:
              kinds:
                - Pod
      exclude:
        any:
          - resources:
              namespaces:
                - kube-system
                - kyverno
                - mount-s3
      preconditions:
        all:
          - key: "{{ request.operation }}"
            operator: Equals
            value: CREATE
          - key: "{{ request.object.metadata.labels.\"scheduling.atlas/skip-default-scheduling\" || 'false' }}"
            operator: Equals
            value: "false"
          - key: "{{ request.object.spec.nodeSelector.\"workload.atlas/node-group\" || '' }}"
            operator: Equals
            value: ""
      context:
        - name: nsDefaultNodeGroup
          apiCall:
            urlPath: "/api/v1/namespaces/{{ request.namespace }}"
            jmesPath: "metadata.labels.\"scheduling.atlas/default-node-group\" || ''"
      mutate:
        patchStrategicMerge:
          spec:
            nodeSelector:
              workload.atlas/node-group: "{{ nsDefaultNodeGroup }}"
YAML

  depends_on = [helm_release.kyverno]
}

resource "kubectl_manifest" "default_nodegroup_toleration_from_namespace" {
  yaml_body = <<YAML
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: default-nodegroup-toleration-from-namespace
spec:
  background: false
  rules:
    - name: add-default-toleration
      match:
        any:
          - resources:
              kinds:
                - Pod
      exclude:
        any:
          - resources:
              namespaces:
                - kube-system
                - kyverno
                - mount-s3
      preconditions:
        all:
          - key: "{{ request.operation }}"
            operator: Equals
            value: CREATE
          - key: "{{ request.object.metadata.labels.\"scheduling.atlas/skip-default-scheduling\" || 'false' }}"
            operator: Equals
            value: "false"
      context:
        - name: nsDefaultNodeGroup
          apiCall:
            urlPath: "/api/v1/namespaces/{{ request.namespace }}"
            jmesPath: "metadata.labels.\"scheduling.atlas/default-node-group\" || ''"
      mutate:
        patchStrategicMerge:
          spec:
            tolerations:
              - key: workload.atlas/node-group
                operator: Equal
                value: "{{ nsDefaultNodeGroup }}"
                effect: NoSchedule
YAML

  depends_on = [helm_release.kyverno]
}

resource "kubectl_manifest" "require_namespace_default_node_group" {
  yaml_body = <<YAML
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-namespace-default-node-group
spec:
  validationFailureAction: Enforce
  background: true
  rules:
    - name: require-ns-label
      match:
        any:
          - resources:
              kinds:
                - Namespace
      exclude:
        any:
          - resources:
              names:
                - kube-system
                - kube-public
                - kube-node-lease
                - kyverno
                - default
                - mount-s3
      validate:
        message: Namespace must define scheduling.atlas/default-node-group.
        pattern:
          metadata:
            labels:
              scheduling.atlas/default-node-group: "?*"
YAML

  depends_on = [helm_release.kyverno]
}

resource "kubernetes_storage_class_v1" "gp3_fast" {
  metadata {
    name = "gp3-fast"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
    fsType    = "ext4"
  }
  depends_on = [helm_release.aws-ebs-csi-driver]
}

resource "kubernetes_storage_class_v1" "gp3_high_performance" {
  metadata {
    name = "gp3-high-performance"
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type       = "gp3"
    encrypted  = "true"
    fsType     = "ext4"
    iops       = tostring(local.config.aws-eks-base-config_k8s-storage-high-performance-iops)
    throughput = tostring(local.config.aws-eks-base-config_k8s-storage-high-performance-throughput)
  }

  depends_on = [helm_release.aws-ebs-csi-driver]
}
