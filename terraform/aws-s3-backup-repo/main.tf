terraform {
  required_version = ">= 1.5"
  backend "local" {
    path = "../_state/aws-s3-backup-repo"
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.28.0"
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

      { package = "aws-eks-init", option = "kms-key-arn" },
      { package = "aws-eks-init", option = "oidc-provider-arn" },
      { package = "aws-eks-init", option = "oidc-provider" },

      { package = "aws-s3-backup-repo", option = "bucket-name" },
      { package = "aws-s3-backup-repo", option = "bucket-force-destroy" },
      { package = "aws-s3-backup-repo", option = "bucket-tags" },
      { package = "aws-s3-backup-repo", option = "bucket-versioning-enabled" },
      { package = "aws-s3-backup-repo", option = "incomplete-multipart-upload-abort-days" },
      { package = "aws-s3-backup-repo", option = "bucket-expire-noncurrent-days" },
      { package = "aws-s3-backup-repo", option = "backups-path-prefix" },

      { package = "doris", option = "kubernetes-namespace" },
      { package = "doris", option = "service-account-name" },

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

provider "aws" {
  region     = local.config.aws_region
  access_key = local.config.aws_aws-access-key
  secret_key = local.config.aws_aws-secret
}

resource "aws_s3_bucket" "this" {
  bucket        = local.config.aws-s3-backup-repo_bucket-name
  force_destroy = local.config.aws-s3-backup-repo_bucket-force-destroy
  tags          = { for item in split(",", local.config.aws-s3-backup-repo_bucket-tags) : item => "" }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status = tobool(local.config.aws-s3-backup-repo_bucket-versioning-enabled) ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = local.config.aws-eks-init_kms-key-arn == null ? "AES256" : "aws:kms"
      kms_master_key_id = var.local.config.aws-eks-init_kms-key-arn
    }
    bucket_key_enabled = var.local.config.aws-eks-init_kms-key-arn != null
  }
}
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "abort-incomplete-mpu"
    status = "Enabled"
    abort_incomplete_multipart_upload {
      days_after_initiation = local.config.local.config.aws-s3-backup-repo_incomplete-multipart-upload-abort-days
    }
  }

  dynamic "rule" {
    for_each = local.config.aws-s3-backup-repo_bucket-expire-noncurrent-days == null ? [] : [1]
    content {
      id     = "expire-noncurrent"
      status = "Enabled"
      noncurrent_version_expiration {
        noncurrent_days = local.config.aws-s3-backup-repo_bucket-expire-noncurrent-days
      }
    }
  }
}

data "aws_iam_policy_document" "bucket_policy" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*"
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket_policy.json
}

data "aws_iam_policy_document" "doris_s3" {
  statement {
    sid       = "ListBucketOnPrefix"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.this.arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${local.config.aws-s3-backup-repo_backups-path-prefix}/*", "${local.config.aws-s3-backup-repo_backups-path-prefix}/"]
    }
  }

  statement {
    sid = "RWObjectsUnderPrefix"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts"
    ]
    resources = ["${aws_s3_bucket.this.arn}/${local.config.aws-s3-backup-repo_backups-path-prefix}/*"]
  }

  dynamic "statement" {
    for_each = local.config.aws-eks-init_kms-key-arn == null ? [] : [1]
    content {
      sid = "UseKmsKeyForS3"
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey"
      ]
      resources = [local.config.aws-eks-init_kms-key-arn]
    }
  }
}

resource "aws_iam_policy" "doris_s3" {
  name   = "${local.config.aws-s3-backup-repo_bucket-name}-doris-backup-s3"
  policy = data.aws_iam_policy_document.doris_s3.json
  tags   = { for item in split(",", local.config.aws-s3-backup-repo_bucket-tags) : item => "" }
}

data "aws_iam_policy_document" "irsa_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.config.aws-eks-init_oidc-provider-arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(local.config.aws-eks-init_oidc-provider, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(local.config.aws-eks-init_oidc-provider, "https://", "")}:sub"
      values   = ["system:serviceaccount:${local.config.doris_kubernetes-namespace}:${local.config.doris_service-account-name}"]
    }
  }
}

resource "aws_iam_role" "irsa" {
  name               = "${local.config.aws-s3-backup-repo_bucket-name}-doris-backup-irsa"
  assume_role_policy = data.aws_iam_policy_document.irsa_trust.json
  tags               = { for item in split(",", local.config.aws-s3-backup-repo_bucket-tags) : item => "" }
}

resource "aws_iam_role_policy_attachment" "attach" {
  role       = aws_iam_role.irsa.name
  policy_arn = aws_iam_policy.doris_s3.arn
}

resource "local_file" "capture_s3_backup_bucket_id" {
  filename = "${local.config.cluster_path}/aws-s3-backup-repo/bucket-id"
  content  = aws_s3_bucket.this.id
}

resource "local_file" "capture_s3_backup_bucket_arn" {
  filename = "${local.config.cluster_path}/aws-s3-backup-repo/bucket-arn"
  content  = aws_s3_bucket.this.arn
}
