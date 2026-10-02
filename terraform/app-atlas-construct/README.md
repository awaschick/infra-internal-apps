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
| core-shell-env | tst |
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
