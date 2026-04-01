terraform {
  required_version = ">= 1.5"
  backend "local" {
    path = "../_state/aws-rds-postgres"
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.31.0"
    }
  }
}

# set variables prefixed with `local.`
# These are defined by files in `config/{package}` and overridden by `_clusters/{selected cluster}/{package}
# variables defined in `options` are used with the format: local.config.{package}_{option}, and will contain
# the contents of the file in that config directory.

locals {
  cluster      = trimspace(file("../../config/_clusters/selection"))
  cluster_path = "../../config/_clusters/${local.cluster}"
  config = jsondecode(templatefile("../_helpers/config.tmpl", {
    options = [
      { package = "aws-vpc", option = "vpc-id" },
      { package = "aws-vpc", option = "vpc-cidr" },
      { package = "aws-vpc", option = "private-subnet-ids" },

      { package = "cluster", option = "site-domain" },
      { package = "cluster", option = "domain-aws-id" },

      { package = "aws-rds-postgres", option = "db-instance-identifier" },
      { package = "aws-rds-postgres", option = "hostname" },
      { package = "aws-rds-postgres", option = "db-name" },
      { package = "aws-rds-postgres", option = "db-username" },
      { package = "aws-rds-postgres", option = "db-password" },
      { package = "aws-rds-postgres", option = "manage-master-user-pw" },
      { package = "aws-rds-postgres", option = "db-port" },
      { package = "aws-rds-postgres", option = "engine-version" },
      { package = "aws-rds-postgres", option = "instance-class" },
      { package = "aws-rds-postgres", option = "allocated-storage-gb" },
      { package = "aws-rds-postgres", option = "max-allocated-storage-gb" },
      { package = "aws-rds-postgres", option = "storage-type" },
      { package = "aws-rds-postgres", option = "storage-encrypted" },
      { package = "aws-rds-postgres", option = "multi-az" },
      { package = "aws-rds-postgres", option = "backup-retention-days" },
      { package = "aws-rds-postgres", option = "backup-window" },
      { package = "aws-rds-postgres", option = "maintenance-window" },
      { package = "aws-rds-postgres", option = "deletion-protection" },
      { package = "aws-rds-postgres", option = "skip-final-snapshot" },
      { package = "aws-rds-postgres", option = "apply-immediately" },
      { package = "aws-rds-postgres", option = "cloudwatch-log-exports" },
      { package = "aws-rds-postgres", option = "cloudwatch-log-retention-days" },
      { package = "aws-rds-postgres", option = "performance-insights-enabled" },
      { package = "aws-rds-postgres", option = "ingress-cidr-blocks" },
      { package = "aws-rds-postgres", option = "resource-tags" },

      { package = "aws", option = "region" },
      { package = "aws", option = "aws-access-key" },
      { package = "aws", option = "aws-secret" },
    ]
    cluster_selection = local.cluster
    cluster_path      = local.cluster_path
    common_path       = "../../config/"
    }
  ))

  private_subnet_ids = [
    for subnet_id in split(",", trimspace(local.config.aws-vpc_private-subnet-ids)) : trimspace(subnet_id)
    if trimspace(subnet_id) != ""
  ]

  ingress_cidr_blocks_raw = trimspace(local.config.aws-rds-postgres_ingress-cidr-blocks)
  ingress_cidr_blocks = (
    local.ingress_cidr_blocks_raw == ""
    ? [trimspace(local.config.aws-vpc_vpc-cidr)]
    : [for cidr in split(",", local.ingress_cidr_blocks_raw) : trimspace(cidr) if trimspace(cidr) != ""]
  )

  cloudwatch_log_exports = [
    for log_name in split(",", trimspace(local.config.aws-rds-postgres_cloudwatch-log-exports)) : trimspace(log_name)
    if trimspace(log_name) != ""
  ]

  resource_tags = {
    for tag in split(",", trimspace(local.config.aws-rds-postgres_resource-tags)) : trimspace(tag) => ""
    if trimspace(tag) != ""
  }

  skip_final_snapshot         = tobool(trimspace(local.config.aws-rds-postgres_skip-final-snapshot))
  deletion_protection         = tobool(trimspace(local.config.aws-rds-postgres_deletion-protection))
  apply_immediately           = tobool(trimspace(local.config.aws-rds-postgres_apply-immediately))
  storage_encrypted           = tobool(trimspace(local.config.aws-rds-postgres_storage-encrypted))
  performance_insights        = tobool(trimspace(local.config.aws-rds-postgres_performance-insights-enabled))
  multi_az                    = tobool(trimspace(local.config.aws-rds-postgres_multi-az))
  manage_master_user_password = tobool(trimspace(local.config.aws-rds-postgres_manage-master-user-pw))

  common_tags = merge(local.resource_tags, {
    "service"    = "aws-rds-postgres"
    "managed-by" = "terraform"
  })

  cluster_rds_config_dir_exists = can(fileset("${local.cluster_path}/aws-rds-postgres", "*"))
  route53_hostname              = trimspace(local.config.aws-rds-postgres_hostname)
  route53_record_fqdn           = local.route53_hostname == "" ? null : "${local.route53_hostname}.${local.config.cluster_site-domain}"
}

# this is set to /opt/kubeconfigs/default, which is a symlink to whichever cluster's kubeconfig is currently selected
variable "kubeconfig" { type = string }

provider "aws" {
  region     = local.config.aws_region
  access_key = local.config.aws_aws-access-key
  secret_key = local.config.aws_aws-secret
}

resource "aws_db_subnet_group" "this" {
  name       = "${local.config.aws-rds-postgres_db-instance-identifier}-subnets"
  subnet_ids = local.private_subnet_ids

  tags = merge(local.common_tags, {
    Name = "${local.config.aws-rds-postgres_db-instance-identifier}-subnets"
  })
}

resource "aws_security_group" "this" {
  name        = "${local.config.aws-rds-postgres_db-instance-identifier}-sg"
  description = "PostgreSQL ingress for ${local.config.aws-rds-postgres_db-instance-identifier}"
  vpc_id      = local.config.aws-vpc_vpc-id

  ingress {
    description = "PostgreSQL"
    from_port   = tonumber(local.config.aws-rds-postgres_db-port)
    to_port     = tonumber(local.config.aws-rds-postgres_db-port)
    protocol    = "tcp"
    cidr_blocks = local.ingress_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.config.aws-rds-postgres_db-instance-identifier}-sg"
  })
}

resource "aws_cloudwatch_log_group" "postgres" {
  for_each = toset(local.cloudwatch_log_exports)

  name              = "/aws/rds/instance/${local.config.aws-rds-postgres_db-instance-identifier}/${each.value}"
  retention_in_days = tonumber(local.config.aws-rds-postgres_cloudwatch-log-retention-days)

  tags = local.common_tags
}

resource "aws_db_instance" "managed" {
  count                           = local.manage_master_user_password ? 1 : 0
  identifier                      = local.config.aws-rds-postgres_db-instance-identifier
  engine                          = "postgres"
  engine_version                  = local.config.aws-rds-postgres_engine-version
  instance_class                  = local.config.aws-rds-postgres_instance-class
  allocated_storage               = tonumber(local.config.aws-rds-postgres_allocated-storage-gb)
  max_allocated_storage           = tonumber(local.config.aws-rds-postgres_max-allocated-storage-gb)
  storage_type                    = local.config.aws-rds-postgres_storage-type
  storage_encrypted               = local.storage_encrypted
  port                            = tonumber(local.config.aws-rds-postgres_db-port)
  db_name                         = local.config.aws-rds-postgres_db-name
  username                        = local.config.aws-rds-postgres_db-username
  manage_master_user_password     = true
  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [aws_security_group.this.id]
  publicly_accessible             = false
  multi_az                        = local.multi_az
  backup_retention_period         = tonumber(local.config.aws-rds-postgres_backup-retention-days)
  backup_window                   = trimspace(local.config.aws-rds-postgres_backup-window) == "" ? null : trimspace(local.config.aws-rds-postgres_backup-window)
  maintenance_window              = trimspace(local.config.aws-rds-postgres_maintenance-window) == "" ? null : trimspace(local.config.aws-rds-postgres_maintenance-window)
  copy_tags_to_snapshot           = true
  auto_minor_version_upgrade      = true
  allow_major_version_upgrade     = false
  deletion_protection             = local.deletion_protection
  apply_immediately               = local.apply_immediately
  skip_final_snapshot             = local.skip_final_snapshot
  final_snapshot_identifier       = local.skip_final_snapshot ? null : "${local.config.aws-rds-postgres_db-instance-identifier}-final"
  enabled_cloudwatch_logs_exports = local.cloudwatch_log_exports
  performance_insights_enabled    = local.performance_insights

  tags = merge(local.common_tags, {
    Name = local.config.aws-rds-postgres_db-instance-identifier
  })

  depends_on = [aws_cloudwatch_log_group.postgres]
}

resource "aws_db_instance" "password" {
  count                           = local.manage_master_user_password ? 0 : 1
  identifier                      = local.config.aws-rds-postgres_db-instance-identifier
  engine                          = "postgres"
  engine_version                  = local.config.aws-rds-postgres_engine-version
  instance_class                  = local.config.aws-rds-postgres_instance-class
  allocated_storage               = tonumber(local.config.aws-rds-postgres_allocated-storage-gb)
  max_allocated_storage           = tonumber(local.config.aws-rds-postgres_max-allocated-storage-gb)
  storage_type                    = local.config.aws-rds-postgres_storage-type
  storage_encrypted               = local.storage_encrypted
  port                            = tonumber(local.config.aws-rds-postgres_db-port)
  db_name                         = local.config.aws-rds-postgres_db-name
  username                        = local.config.aws-rds-postgres_db-username
  password                        = local.config.aws-rds-postgres_db-password
  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [aws_security_group.this.id]
  publicly_accessible             = false
  multi_az                        = local.multi_az
  backup_retention_period         = tonumber(local.config.aws-rds-postgres_backup-retention-days)
  backup_window                   = trimspace(local.config.aws-rds-postgres_backup-window) == "" ? null : trimspace(local.config.aws-rds-postgres_backup-window)
  maintenance_window              = trimspace(local.config.aws-rds-postgres_maintenance-window) == "" ? null : trimspace(local.config.aws-rds-postgres_maintenance-window)
  copy_tags_to_snapshot           = true
  auto_minor_version_upgrade      = true
  allow_major_version_upgrade     = false
  deletion_protection             = local.deletion_protection
  apply_immediately               = local.apply_immediately
  skip_final_snapshot             = local.skip_final_snapshot
  final_snapshot_identifier       = local.skip_final_snapshot ? null : "${local.config.aws-rds-postgres_db-instance-identifier}-final"
  enabled_cloudwatch_logs_exports = local.cloudwatch_log_exports
  performance_insights_enabled    = local.performance_insights

  tags = merge(local.common_tags, {
    Name = local.config.aws-rds-postgres_db-instance-identifier
  })

  lifecycle {
    precondition {
      condition     = trimspace(local.config.aws-rds-postgres_db-password) != ""
      error_message = "config/aws-rds-postgres/db-password must be set when manage-master-user-pw is false."
    }
  }

  depends_on = [aws_cloudwatch_log_group.postgres]
}

locals {
  rds_instance_endpoint   = local.manage_master_user_password ? aws_db_instance.managed[0].address : aws_db_instance.password[0].address
  rds_instance_port       = local.manage_master_user_password ? aws_db_instance.managed[0].port : aws_db_instance.password[0].port
  rds_instance_identifier = local.manage_master_user_password ? aws_db_instance.managed[0].identifier : aws_db_instance.password[0].identifier
  rds_master_secret_arn   = local.manage_master_user_password ? aws_db_instance.managed[0].master_user_secret[0].secret_arn : null
  rds_access_endpoint     = local.route53_record_fqdn != null ? local.route53_record_fqdn : local.rds_instance_endpoint
}

resource "aws_route53_record" "postgres_endpoint" {
  count = local.route53_record_fqdn == null ? 0 : 1

  zone_id = local.config.cluster_domain-aws-id
  name    = local.route53_record_fqdn
  type    = "CNAME"
  ttl     = 60
  records = [local.rds_instance_endpoint]
}

resource "local_file" "capture_rds_endpoint" {
  count    = local.cluster_rds_config_dir_exists ? 1 : 0
  filename = "${local.cluster_path}/aws-rds-postgres/endpoint"
  content  = local.rds_access_endpoint
}

resource "local_file" "capture_rds_port" {
  count    = local.cluster_rds_config_dir_exists ? 1 : 0
  filename = "${local.cluster_path}/aws-rds-postgres/port"
  content  = tostring(local.rds_instance_port)
}

resource "local_file" "capture_rds_database_name" {
  count    = local.cluster_rds_config_dir_exists ? 1 : 0
  filename = "${local.cluster_path}/aws-rds-postgres/db-name"
  content  = local.config.aws-rds-postgres_db-name
}

resource "local_file" "capture_rds_db_username" {
  count    = local.cluster_rds_config_dir_exists ? 1 : 0
  filename = "${local.cluster_path}/aws-rds-postgres/db-username"
  content  = local.config.aws-rds-postgres_db-username
}

resource "local_file" "capture_rds_master_secret_arn" {
  count    = local.cluster_rds_config_dir_exists && local.manage_master_user_password ? 1 : 0
  filename = "${local.cluster_path}/aws-rds-postgres/master-user-secret-arn"
  content  = try(aws_db_instance.managed[0].master_user_secret[0].secret_arn, "")
}

resource "local_file" "capture_rds_security_group_id" {
  count    = local.cluster_rds_config_dir_exists ? 1 : 0
  filename = "${local.cluster_path}/aws-rds-postgres/security-group-id"
  content  = aws_security_group.this.id
}

resource "local_file" "capture_rds_instance_id" {
  count    = local.cluster_rds_config_dir_exists ? 1 : 0
  filename = "${local.cluster_path}/aws-rds-postgres/instance-id"
  content  = local.rds_instance_identifier
}

output "aws_rds_postgres_endpoint" {
  value = local.rds_access_endpoint
}

output "aws_rds_postgres_upstream_endpoint" {
  value = local.rds_instance_endpoint
}

output "aws_rds_postgres_port" {
  value = local.rds_instance_port
}

output "aws_rds_postgres_db_name" {
  value = local.config.aws-rds-postgres_db-name
}

output "aws_rds_postgres_db_username" {
  value = local.config.aws-rds-postgres_db-username
}

output "aws_rds_postgres_master_user_secret_arn" {
  value = local.rds_master_secret_arn
}

output "aws_rds_postgres_security_group_id" {
  value = aws_security_group.this.id
}
