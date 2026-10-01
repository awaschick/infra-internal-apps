# Atlas Time: dev, UAT and production deployments

This module follows the sibling internal apps' workspace/config-instance, ALB,
ACM, Route 53 and local state conventions. It uses the existing platform node
group and shared RDS PostgreSQL endpoint. Application packaging lives in the
sibling `atlas-time` repository.

## Environments and release

| Environment | Terraform workspace | Namespace / deployment | Database | HTTPS hostname |
| --- | --- | --- | --- | --- |
| Dev | `dev` | `atlas-time-dev` / `atlas-time-dev-web` | `atlas_time_dev` | `dev.time.apps.atlasdigitalgroup.com` |
| UAT | `uat` | `atlas-time-uat` / `atlas-time-uat-web` | `atlas_time_uat` | `uat.time.apps.atlasdigitalgroup.com` |
| Production | `default` | `atlas-time` / `atlas-time-web` | `atlas_time` | `time.apps.atlasdigitalgroup.com` |

These hostnames use the selected cluster's domain. All three deployments remain
private (internal ALB), even though the hostname omits a `private` segment.
Production uses package defaults plus cluster overrides; dev/UAT use
`config/_clusters/<selected-cluster>/app-atlas-time/_instances/<workspace>/`.
The module rejects other workspaces, mismatched databases/namespaces, public
exposure, missing Entra IDs and the `latest` image tag.

All three configurations select
`010279360435.dkr.ecr.us-east-1.amazonaws.com/atlas-time:2026100101`.
The `develop` checkout reviewed for this release includes `e3f335f` (1 October),
after the handoff's `6ce9ab4`. The compiled Clockify importer is now included in
the image, but real CSV fixtures and the sample seed remain excluded. Importing
is still an explicit administration action. No new runtime variables, secrets,
ports or volumes are required.

Both the migration init container and application use the same image. The
`Recreate` strategy stops the previous app before the init container runs
`npm run db:deploy`. Migration `20260923120000_entry_source_import` only adds
`IMPORT` to the PostgreSQL `EntrySource` enum. Do not apply it manually ahead
of rollout. Once IMPORT rows exist, the old Prisma client cannot read them;
rolling back the image alone is not a safe recovery plan.

## Deploy only: preserve existing data

Normal deployment has no seed, import, reset or database-replication hook.
The former Atlas Time start hook and UAT dev-copy setting have been removed.
The shared replication helper remains available to other applications.
Do not run `db:seed:deploy` on dev or UAT for this release. The product owner
and Brian own all data work there, including clearing/reseeding UAT later.
Neither a database copy nor seeding is a prerequisite for an image upgrade.

From the repository root, review each plan separately:

```bash
make tf-plan app-atlas-time WORKSPACE=dev
make tf-plan app-atlas-time WORKSPACE=uat
make tf-plan app-atlas-time WORKSPACE=default
```

After reviewing the corresponding plan, the actual deployment commands are:

```bash
make tf-start app-atlas-time WORKSPACE=dev
make tf-start app-atlas-time WORKSPACE=uat
# Production: only after completing its first-deployment prerequisites below.
make tf-start app-atlas-time WORKSPACE=default
```

The start launcher uses `terraform apply -auto-approve`; it is an actual apply,
not a preview. Plan commands never run administration commands. Retain protected
backups and an appropriate recovery path before deploying schema changes.

## Production preparation and subsequent data administration

Before the first production apply, provision/verify the separate `atlas_time`
database on shared RDS and verify the runtime account's access. Terraform does
not create PostgreSQL databases. Verify the Entra SPA redirect
`https://time.apps.atlasdigitalgroup.com` and intended staff access. Runtime
`entra-client-id` and `entra-tenant-id` must match the IDs built into this image;
the selected cluster's existing IDs are inherited by all three environments.
Optional `anthropic-api-key` values stay in ignored local overrides.

Use UAT's **directory seed scope**, not UAT's database contents, as the production
pattern. Data administration is separate from deployment and is not executed
by this module. For a verified empty production database, after migrations,
the designated data owner can explicitly run:

```bash
kubectl --kubeconfig "$KUBECONFIG" -n atlas-time exec deployment/atlas-time-web \
  -c atlas-time -- env SEED_SCOPE=directory \
  npm run db:seed:deploy --workspace @atlas-time/server
```

Do not add `SEED_SCOPE` to the persistent application environment. Directory
scope creates clients, users, teams and tags, plus the signed Wyyerd Intuition
agreement, phases and five quarterly commitment periods with the contract band.
Other commercial contracts/projects/tasks come from the separately managed
Clockify import. Follow the application's `OPERATIONS.md` for external read-only
CSV input, dry-run review, controlled import and reconciliation. Do not place
real fixtures in images, this repository or Terraform state.

Current seeding preserves the roles of existing users, but can reconcile names,
memberships and commercial settings. Clearing users first means recreated users
receive seeded roles; any manually granted OWNER access must then be restored
by the data owners. Never run sample seeds or `db:reset` on shared environments.

## Acceptance and recovery

Set `KUBECONFIG` to the selected cluster's `_k8s/kubeconfig`. For each deployed
environment, use its namespace and deployment from the table above:

```bash
kubectl --kubeconfig "$KUBECONFIG" -n atlas-time-dev rollout status deployment/atlas-time-dev-web
kubectl --kubeconfig "$KUBECONFIG" -n atlas-time-dev logs deployment/atlas-time-dev-web -c migrate
curl --fail --silent --show-error https://dev.time.apps.atlasdigitalgroup.com/api/ready
```

Repeat with the UAT and production names/URLs when each is deployed. Capture
migration logs showing `20260923120000_entry_source_import` applied on the first
rollout (a later restart can correctly report no pending migrations). Verify
HTTPS and readiness from the internal network. Sign in and open Manage →
Projects: status offers Active, Archived and All, the Client filter is present,
and archived projects/clients are reachable. Confirm persistence after a pod
restart and verify expected user access. A Ready pod alone does not prove
browser sign-in or business acceptance.

Record configuration validation, registry verification, plan, apply, migration,
seed/import and browser checks separately. Preparation is not deployment.
Consult the application's `OPERATIONS.md` for schema-aware recovery; an image
rollback does not undo migrations. Durable data lives in RDS, so no application
PVC is required. Keep state/backups protected and verify cluster log retention
before relying on stdout audit events as a durable record.

## Preparation verification: 1 October 2026

- Terraform formatting, validation and whitespace checks passed.
- ECR tag `2026100101` resolves to
  `sha256:2baf8f87466f204df38ce18e83d6da321bcd12dcda8a48515e655f0d00751dc6`.
- Live dev/UAT deployments still run `2026091801`.
- Provider-backed plans succeeded: dev and UAT each have 0 adds, 3 updates,
  0 destroys; production/default has 10 adds, 0 updates, 0 destroys.
- Dev/UAT updates comprise the app/init image changes plus removal of existing
  Rancher annotations: ingress `field.cattle.io/publicEndpoints`, and namespace
  `cattle.io/status` / `lifecycle.cattle.io/create.namespace-auth`. These are
  existing controller metadata drift; no ingress routing or namespace identity
  changes are planned. Review this drift alongside the release before apply.
- Read-only inspection through the existing runtime credentials confirmed
  `atlas_time` exists and has no public tables. Production Entra redirect and
  browser sign-in remain unverified.
- No apply, migration, seed, import, reset or database copy was executed.
  Rollout, readiness and browser acceptance for the new image remain pending.
