# Configured PostgreSQL read-only accounts

`make tf-start aws-rds-postgres` validates the optional account manifest before
Terraform apply and synchronizes accounts after a successful apply. No manifest
means no account changes. Direct `terraform apply` does **not** run shell hooks.
Use the default Terraform workspace for this shared server.

## Configure

Copy `config/aws-rds-postgres/read-only-users.example.json` to:

```text
config/_clusters/<selected-cluster>/aws-rds-postgres/read-only-users.json
```

The selected cluster comes from `config/_clusters/selection`. A cluster manifest
replaces the common `config/aws-rds-postgres/read-only-users.json` entirely; they
are not merged. Both real filenames are Git-ignored. Set mode `0600`, keep a
secure backup, and never put real passwords in the tracked example.

```json
{
  "users": [
    {
      "username": "report_reader",
      "password": "REPLACE_WITH_A_UNIQUE_PASSWORD",
      "access": [
        {
          "database": "example_app",
          "schemas": ["public"],
          "owners": ["example_migration_role"]
        }
      ]
    }
  ]
}
```

Add as many users or database entries as needed. Names must be simple ASCII SQL
identifiers, at most 63 characters. `owners` lists **all roles that create tables**
in those schemas, including migration roles. It is not a list of reader accounts.
Databases, schemas, and owner roles must already exist. The deployment
administrator must be able to create/alter these roles, grant access to existing
tables, alter each owner's default privileges, inspect every application database,
and terminate reader sessions.

Readers receive `CONNECT`, schema `USAGE`, and table/view `SELECT`. Default
privileges grant `SELECT` on future tables created by the configured owners in
those schemas. New schemas, databases, or table-creating roles require deliberate
configuration. Row-level security remains enforced; no sequence mutation,
write privileges, role memberships, or ownership is granted.

## Validate and apply

Requirements: Python 3, `psql` on PATH (Homebrew libpq is also detected), and
network access to the private PostgreSQL endpoint. AWS CLI is additionally
required if `manage-master-user-pw=true`; the configured AWS profile needs
`secretsmanager:GetSecretValue` on `master-user-secret-arn`.

```bash
# Offline validation; never contacts PostgreSQL or AWS.
python3 script/sync_postgres_read_only_users.py --check

# Normal deployment: apply infrastructure, then synchronize users.
make tf-start aws-rds-postgres

# Explicit account-only synchronization, without Terraform infrastructure changes.
python3 script/sync_postgres_read_only_users.py --apply
```

`--config /path/to/users.json` overrides manifest lookup. `--check` validates
structure only; `tf-plan` does not preview database role changes. Credentials are
passed to `psql` through its environment/stdin, not command arguments, Terraform
state, or script output. SQL error text is suppressed because it can include
password statements. Server-side SQL logging must also protect credentials.
Connections require TLS (`sslmode=require`, encryption without CA/hostname
verification), matching the private endpoint usage.

## Rotation, disablement, and scope changes

- Change a password in the manifest and rerun synchronization to rotate it.
- To disable a managed user, retain `{"username":"report_reader","enabled":false}`.
  Password and access fields are optional when disabled. This prevents new logins
  and terminates existing sessions. It retains grants and the role for recovery.
- Removing a user from the file, supplying an empty users list, or removing the
  file **does not revoke** its existing access. Disable accounts explicitly first.
- Edit `access` in place to add or remove databases, schemas, or future-table
  creator roles while retaining the same username. Re-enabling a disabled account
  also reconciles its access to the current manifest.
- Each enabled managed reader is authoritative: sync discovers and removes its
  direct database `CONNECT`, schema `USAGE`, table/column `SELECT`, and future-table
  `SELECT` defaults across audited databases, then applies the requested scope.
  This also replaces manually added read grants to that dedicated account.
  Other users and PUBLIC grants remain unchanged. Existing tables in the retained
  schemas remain readable regardless of creator; changing `owners` changes only
  which creators automatically grant access to future tables.
- Existing v1 managed accounts are supported without renaming or recreating them.
  Catalog discovery works even when the old comment contains only a scope hash,
  or a previous attempt partially applied. The comment is updated with the new
  digest when audits succeed and login is enabled. Unmanaged accounts are never
  adopted; managed readers that own objects or depend on excluded/offline
  databases require manual review. No objects are dropped.
- Revocation uses `RESTRICT`, never cascading into grants made to other users.
  Missing authority or grants that cannot be removed cause failure with the reader
  disabled. The administrator needs revocation authority for old scopes and default
  privileges as well as grant authority for new scopes. Do not remove that authority
  before transitioning accounts away from an old creator role.

Sync temporarily disables each enabled managed account and terminates its
sessions while changing grants/passwords. Run during a suitable reconnect window;
do not run concurrent synchronizations. It is repeatable, but not one transaction
across the entire server. On failure, already-applied changes remain, affected
accounts stay disabled, and the command exits nonzero. Correct the cause and rerun.
Terraform resources may have applied successfully even when the account hook fails.

## Effective access and PUBLIC grants

`default_transaction_read_only=on` is a convenience guard, not the security
boundary: clients can override it. Object privileges enforce the restrictions.
Before enabling accounts the script audits all connectable non-template databases
(except the RDS internal `rdsadmin` database). It refuses effective writes, reads
outside the listed schemas, and executable application security-definer routines.
Existing unsafe `PUBLIC` grants require an administrator's separate review; this
script never revokes shared privileges from other applications.

PostgreSQL's usual `PUBLIC CONNECT`, temporary-table, catalog visibility, and
invoker-function privileges remain. This is application-data read access control,
not database-name hiding or a sandbox for hostile SQL. Audits reflect the state at
sync time: future out-of-band shared grants or security-definer routines can
change effective access. Rerun after database privilege changes. Future-table
defaults are specific to the creating role, as documented in
[PostgreSQL ALTER DEFAULT PRIVILEGES](https://www.postgresql.org/docs/16/sql-alterdefaultprivileges.html).

## Local tests

```bash
python3 -m unittest discover -s script -p 'test_postgres*.py' -v
RUN_POSTGRES_INTEGRATION=1 python3 -m unittest discover -s script -p 'test_postgres*.py' -v
```

The second command requires Docker and `postgres:16-alpine`. It starts and removes
a disposable local server with synthetic credentials; it never uses cluster
credentials or reaches the Internal Apps server.
