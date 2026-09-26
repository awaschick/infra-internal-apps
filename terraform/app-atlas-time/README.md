# Atlas Time: dev and UAT deployments

This module follows app-change-control's workspace/config-instance, ALB, ACM,
Route 53 and state conventions, and Project Intake's single-port API/SPA image.
It uses the existing platform node group and shared RDS PostgreSQL endpoint.
Application packaging lives in `../atlas-time`, not this infrastructure repo.

- Package defaults: `config/app-atlas-time/`.
- Cluster workspace overrides:
  `config/_clusters/<selected-cluster>/app-atlas-time/_instances/<workspace>/`.
- Public Entra IDs: `entra-tenant-id`, `entra-client-id`; defaults are empty.
- Optional secret: `anthropic-api-key` in the ignored dev override.
- Intended URL: `https://dev.time.private.apps.atlasdigitalgroup.com`.
- Required separate databases: `atlas_time_dev` and `atlas_time_uat`.
- Image: release-tagged amd64 `atlas-time`, built with the same Entra IDs.

Run `make tf-plan app-atlas-time WORKSPACE=dev` from this repository. It fails
until Entra configuration is supplied. The module allows `dev` and `uat` with
matching database/namespace names and blocks public exposure. Create/verify the separate database
before deployment and review the full plan. `make tf-start app-atlas-time
WORKSPACE=dev` actually applies using the existing auto-approve launcher.

## Optional database refresh before deployment

The Atlas Time start hook uses the shared workspace database replica helper.
For UAT, set `_instances/uat/db-replica-source-workspace` to `dev` and
`_instances/uat/db-name` to `atlas_time_uat` under the selected cluster's
`app-atlas-time` config. The existing `k8s.apps.atlasdigitalcommerce.com` UAT
config selects `dev` as its source. Other named source workspaces can be selected
through the same config file; `db-replica-source-db`, if set, takes precedence.

Review `make tf-plan app-atlas-time WORKSPACE=uat`, then run
`make tf-start app-atlas-time WORKSPACE=uat`. The start hook asks whether to
refresh UAT from dev before Terraform apply. Enter `y` to copy; Enter or `n`
skips the copy and continues deployment. The plan command never copies a database.

An accepted refresh backs up an existing target to `db/backups/`, replaces it,
restores the source, verifies relation/row counts, and writes the target database
name into the instance config. A failed refresh stops deployment. This replaces
all UAT data with dev data, including users and application settings. Ensure an
existing UAT application is stopped before refreshing to prevent writes during
replacement. A skipped refresh requires the target database to exist already.
The deployment's migration init container then applies pending migrations.

An init container runs `prisma migrate deploy`; the image includes the CLI and
all migration SQL. Recreate prevents the previous app version from overlapping
with the migration. Catalog seeding is an explicit one-time administration step,
not an init hook. Sample hours and credentials are excluded from images.

Read `atlas-time/OPERATIONS.md` for first-owner seeding, browser validation and
schema-aware rollback. Application logs and audit events use JSON stdout;
verify cluster collector retention before authoritative use. No PVC is needed
for application data because it lives in RDS. State and database backups require
the existing protected operational storage.

Validation on 2026-09-11: Terraform init/validate passed. The provider-backed dev
plan stopped on the missing Entra precondition, with additions only and no
changes/deletions. Shared RDS query confirmed atlas_time_dev absent. No resources
were applied, no database was created or seeded, and no image was pushed.
