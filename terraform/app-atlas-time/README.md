# Atlas Time: initial dev deployment

This module follows app-change-control's workspace/config-instance, ALB, ACM,
Route 53 and state conventions, and Project Intake's single-port API/SPA image.
It uses the existing platform node group and shared RDS PostgreSQL endpoint.
Application packaging lives in `../atlas-time`, not this infrastructure repo.

- Package defaults: `config/app-atlas-time/`.
- Cluster dev overrides:
  `config/_clusters/<selected-cluster>/app-atlas-time/_instances/dev/`.
- Public Entra IDs: `entra-tenant-id`, `entra-client-id`; defaults are empty.
- Optional secret: `anthropic-api-key` in the ignored dev override.
- Intended URL: `https://dev.time.private.apps.atlasdigitalgroup.com`.
- Required separate database: `atlas_time_dev`. No cross-app replica hook is used.
- Image: release-tagged amd64 `atlas-time`, built with the same Entra IDs.

Run `make tf-plan app-atlas-time WORKSPACE=dev` from this repository. It fails
until Entra configuration is supplied. The module blocks other workspaces and
public exposure for this initial release. Create/verify the separate database
before deployment and review the full plan. `make tf-start app-atlas-time
WORKSPACE=dev` actually applies using the existing auto-approve launcher.

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
