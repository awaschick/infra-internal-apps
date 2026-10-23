# October 23 users and CORE source configuration

Deployment configuration is prepared for Construct develop `7448f5f3`; no rollout
is implied. Image rebuild, publication and version selection remain separate.

The cluster-level `construct-admin-emails` grants admin access to
`andywaschick@atlasdigitalgroup.com`, `mm@atlasdigitalgroup.com`, and
`brianmay@atlasdigitalgroup.com` across default/prod, dev and UAT. Workspace overrides
use the existing `_instances/<workspace>/construct-admin-emails` precedence.
`CONSTRUCT_ADMIN_EMAILS` is an ongoing admin override, not only a migration seed;
remove an email from configuration to stop forcing that person's admin access.
Other users initially receive viewer access; assign editors through the Admin page.
Entra remains the sign-in provider; Construct stores roles in PostgreSQL.

Startup migrations are already enabled by the image. The new migration creates
`app_user`, `user_activity` and `admin_audit` in each instance's existing Construct
database. Verify migration completion and administrator sign-in after rollout.

The in-app Update piece map feature requires `core-source-github-token`, mapped to
`CORE_SOURCE_GITHUB_TOKEN` in the existing Kubernetes environment Secret. Supply a
dedicated read-only CORE repository token in the ignored cluster-level file or an
ignored `_instances/<workspace>/core-source-github-token` override. The committed
default is empty: no credential is included, and the feature stays unavailable
until supplied. The default repository is `atlas-digital-group/core` and ref is
`origin/tg/vue3`, configurable with `core-source-github-repo` and `core-source-ref`.
The backend needs HTTPS access to `api.github.com`. Stored maps use the existing
PVC under `piece-maps`; no new volume or inbound port is needed.

All four settings participate in the existing environment checksum and rollout.
Use the existing protected Terraform state handling because the environment Secret
contains the token. Refresh the packaged CORE UI artifact for the new map pin
(`7ad4026f056ebfe4fd5fbeafdbe8268f963cec7f`, `index-DS3QMazj.js`) during image build.

# October 16 release configuration

Prepared image target: `2026101601` for dev, UAT and production. Build/push it
before applying these changes; the existing `2026101501` image does not include
the new environment selector. No deployment is implied by the configuration edit.

`core-shell-env=uat` now supplies the fallback for all Atlas Construct instances.
The application resolves per-client database override → Construct-wide database
setting → `CORE_SHELL_ENV` → historical `tst` default. Terraform already wires
this variable into the environment Secret and rollout checksum; no new resource,
port, permission or database migration is required. Saved database overrides win
and can affect multiple instances sharing a Construct database. Verify the resolved
source on the Environments page after deployment; do not overwrite operator settings
as part of deployment. Keep the shell enabled and mirroring on.

Older catalog-only imports need their CORE settings imported to render card layouts,
as confirmed by the lead developer. That data prerequisite is separate from bundle
compatibility and is not a build blocker. Use Check builds for each preview client.

The dated sections below retain prior preparation and validation evidence.

# Atlas Construct deployment

This is the existing Construct workload owner. It uses config-instance precedence
(global, cluster, then workspace) and the existing `make tf-plan app-atlas-construct
WORKSPACE=uat` workflow. The default workspace is the default/prod configuration.

The October 2026 preparation adds an **opt-in** CORE preview origin. See the companion
Construct repository's `docs/deploy-core-preview-shell.md` for artifact preparation,
Entra build settings, state conversion, rollout validation and rollback.

New options under `config/app-atlas-construct`:

| File | Default |
| --- | --- |
| core-shell-enabled | false |
| core-shell-port | 4100 |
| core-shell-site-hostname | empty; derives preview.<app FQDN> |
| core-shell-env | uat |
| core-shell-reference-client | Ezee |

Enable the shell **together with an image containing the verified UI artifact and
/app/healthcheck.cjs**. Old images remain compatible while the shell is disabled.
The module adds a Service port, ALB host rule, ACM SAN and DNS CNAME only when enabled.
The shell editor origin is the frontend origin. Hostnames share the configured site
domain. ALB idle timeout is 900 seconds to accommodate existing import requests.

Construct always requires one replica and Recreate updates because its catalog is a
single-writer JSON file. A restart invalidates preview sessions. Back up the whole PVC
before the ContextVariants upgrade; old images need the old data shape for rollback.

Local validation, without contacting AWS/Kubernetes or reading real credentials:

```bash
.venv/bin/terraform -chdir=terraform/app-atlas-construct validate
python3 script/test_construct_deployment.py
```

The test requires Terraform >=1.7 and initialized providers (tested with 1.14.8).
It makes disposable synthetic config trees and uses mocked providers to check enabled/
disabled plans and rejection of multiple replicas, production pairing, duplicate
hostnames and duplicate ports. It does not replace a real UAT plan or browser test.

## October 2, 2026 — dev/UAT release ready, not applied

Reviewed the complete **Prepare reliable deployment tooling** chat in the Construct
project and the current companion deployment guide. At the user's direction, this
chat leaves validated changes ready; it does not deploy them.

Both instance configurations now select
`010279360435.dkr.ecr.us-east-1.amazonaws.com/atlas-construct:2026100201`, enable the
preview shell, and explicitly pair with `tst`. This CORE pairing is independent of
the Construct workspace name. Existing application origins stay the same.

| Workspace | Current running image tag | Planned preview URL |
| --- | --- | --- |
| dev | 2026071501 | https://dev.construct-preview.apps.atlasdigitalgroup.com |
| uat | 2026090201 | https://uat.construct-preview.apps.atlasdigitalgroup.com |

The default/prod instance still selects `2026090201` and inherits shell disabled.
The shared module's Recreate/probe/ALB timeout changes will affect that instance
when it is eventually applied; no default/prod plan or apply was run here.

### Verified evidence

* ECR and the local linux/amd64 image agree on digest
  `sha256:e516eaf855028089304135a035ef7ede9f51379d4027b22a0fec899a762bfa02`.
* The image contains the 17-file CORE artifact manifest for UI commit
  `377a0be2eb5c68e4f39a373508857b2a9f9fc29c` and entry `index-DAVXsKRg.js`.
  Both workspaces' runtime Entra client and tenant IDs are present in the built
  frontend assets. Credentials were not printed or changed.
* Terraform format/validate, six mocked-provider scenarios, and both live plans
  passed. Each live plan has **5 additions, 4 updates, 3 destructions**. The
  destructions are certificate/validation replacements; neither namespace nor
  PVC changes. Existing private ALBs remain in use. Rancher-managed namespace
  annotations are explicitly preserved.
* Read-only copies of each full data directory were obtained for rehearsal.
  All **7 dev clients (3,938 variants)** and **2 UAT clients (63 variants)** loaded
  with the release image. Every client's compiled output hash matched the
  compiler in its currently running image. Saving/reloading with the new image
  preserved compiled output, and the second save produced identical bytes.
  Existing audit/import histories were checked through the round trip.
* Both databases were reachable, and all four packaged migrations were already
  recorded. No database migration or database mutation was performed.

Local evidence is under the Git-ignored `db/backups/atlas-construct-2026100201-preflight/`
directory: saved plans, plan summaries, logs, rehearsal script, original data
archives, converted copies, and compiler digests. Access is restricted to the local
user. **These are unquiesced rehearsal copies, not consistent rollback backups.**
No new draft change sets, uploaded logos, browser previews, or snapshot restores
were authored/tested against the deployed applications in this preflight.

### Deploy when authorized

1. Reconfirm ECR tag/digest and the selected cluster. Quiesce dev writers, then
   make consistent backups of its **entire PVC** and matching PostgreSQL database.
   Verify the archives and record restore locations before enabling new writers.
2. Refresh/review `make tf-plan app-atlas-construct WORKSPACE=dev` after any
   quiescing changes, then apply with the existing deployment tooling. Saved plans
   are evidence of this preflight, not a substitute for a fresh plan after state
   changes. Do not refresh/replace either workspace database from another instance.
3. Check TLS/DNS, ALB target health and controller-managed access to port 4100;
   authenticated shell status must report running/local/tst with the expected
   origins and bundle. Verify shell `/` is public and data endpoints reject
   anonymous access. Inspect ALB logging/retention for bearer-link query exposure.
4. Complete the guide's authenticated visual-editor, pop-up, draft, upload,
   restart/persistence, and release-bundle checks on dev before repeating for UAT.
   Network readiness alone does not establish these workflows.
5. For rollback, preserve the failed/new data, then restore the matching pre-upgrade
   full-volume backup and old image/config. Never run the old image against data
   saved in the new ContextVariants format. Restore PostgreSQL if required by the
   changes actually made, and reconcile edits since the backup explicitly.

Infrastructure revision inspected: `13768fa92f53cb4f0eb12c29850cde61fb11984c`, plus
the existing uncommitted preparation and this chat's changes. Construct checkout
revision inspected: `79569662e7512088a20d4d7e1a4ffc0f67189704`; the release image
identity above is verified independently of the current checkout revision.

## October 15, 2026 — container support

The companion image now supplies Chromium/Noto fonts and Agent SDK documentation.
New global defaults follow the existing cluster/workspace override precedence:

| Option | Default | Purpose |
| --- | --- | --- |
| core-shell-mirror | 1 | Mirror the paired nonproduction CORE UI; 0 opts out |
| css-design-render | on | Enable screenshot/style verification and image generation |
| morpheus-slack-engine | agent | Select agent or classic for Slack |
| cpu-request | 500m | Scheduler reservation |
| memory-request | 1Gi | Scheduler reservation |
| cpu-limit | 2 | CPU cap |
| memory-limit | 6Gi | Node 4 GiB heap plus Chromium and Agent subprocess headroom |

`CSS_DESIGN_CHROMIUM_PATH` is `/usr/bin/chromium`, matching the image. The existing
persistent volume covers mirror files, undo journals, custom styles, and Morpheus
agent sessions/docs. Resource defaults are starting budgets, not a load-test result;
watch memory and CPU after rollout. No PVC or database migration is needed here.
Rancher-owned `field.cattle.io/publicEndpoints` annotations are preserved on the
Deployment and Ingress, as namespace controller annotations already were.

Production/default already has preview enabled and pairs with `tst`; the existing
local image URI changes select `2026101501` for production, dev and UAT. These edits
were preserved. This preparation does not push an image or apply Terraform.

Validation on October 15: Terraform validate and all six mocked-provider scenarios
passed, including new renderer/agent/resource assertions. A read-only production
plan showed **0 additions, 2 in-place updates, 0 destructions** (Deployment and
application environment Secret). No ingress, certificate, namespace or PVC change.
The plan log is local under `db/backups/atlas-construct-2026101501-preflight/production-plan.log`
and is not committed because plans may contain deployment configuration.
Repeat the production plan immediately before deployment. Publish only the tested
image, take consistent full-volume/database backups, and verify authenticated
preview, generated images and Morpheus workflows after rollout.

Companion image validation: `atlas-construct:2026101501-validation` (linux/amd64)
built successfully with production Entra build inputs. Application startup, all
three listeners, Agent SDK import/native executable, packaged agent docs and
restart persistence passed. The local Mac's Rosetta Chromium run crashed with a
translation-layer SIGTRAP; **native amd64 rendering remains a rollout acceptance
check**. The same Dockerfile built as
`atlas-construct:2026101501-validation-arm64` passed the full smoke test, including
Chromium SVG-to-PNG rendering under the 2 CPU / 6 GiB limits. No external model call
was made. The build also caught and fixed a compiled CommonJS import-order crash in
Construct's release-bundle upload route. Independent scoped code review found no
actionable issues. Neither image was pushed and Terraform was not applied.

### Dev preview pairing validation (October 15, 2026)

Dev now sets `core-shell-env=uat`. Ezee DEV/TST/STG bundles lack required
preview actions; UAT (`uat.shop.ezeefiber.com`, `index-DcVP9cI_.js`) passed
compatibility, isolated mirroring and bundle-pin checks. The saved dev-only plan
changed the environment Secret and Deployment checksum (2 updates, no additions
or destruction). Apply succeeded; replacement pod
`atlas-construct-dev-web-54d86ffd9f-nbv5v` is ready with zero restarts and
`CORE_SHELL_ENV=uat`. The post-apply dev plan returned no changes. Production
and Construct UAT were not applied.

Authenticated Chrome validation opens Ezee and Midsouth previews, but end-to-end
acceptance is **not passed**: package cards are empty and Customize stops with
“no plan button to press on the offers page.” Read-only hydration returned four
Ezee packages and nine Midsouth packages successfully. Both client records have
empty `uiConfig`; their `packagePieces` Config rows refer to
`@packagePiecesPresale` and `@packagePieces3MF`, respectively. Missing referenced
layout configuration is the next issue to resolve; no client catalogs were edited.

Earlier live native-amd64 validation passed Chromium rendering/capture and the
Agent SDK model call, resolving the local Rosetta-only Chromium limitation.
