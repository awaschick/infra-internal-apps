#!/usr/bin/env python3
"""Sync dedicated PostgreSQL readers. SQL and credentials never go to stdout/argv."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
MARKER = 'infra-internal-apps:readonly:v1:'


def name(value):
    if not isinstance(value, str) or not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]{0,62}', value):
        raise ValueError('Names must be PostgreSQL identifiers of 1–63 ASCII characters.')
    return value


def load_users(path):
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError):
        raise ValueError('Cannot read valid JSON from the reader configuration.') from None
    if not isinstance(data, dict) or set(data) != {'users'} or not isinstance(data['users'], list):
        raise ValueError('Configuration must contain a users array only.')
    seen = set()
    for user in data['users']:
        if not isinstance(user, dict) or set(user) - {'username', 'password', 'enabled', 'access'}:
            raise ValueError('Invalid account fields.')
        username = name(user.get('username'))
        if username.lower() in {'postgres', 'public', 'rdsadmin'} or username.lower().startswith(('pg_', 'rds_')):
            raise ValueError('Reserved account name.')
        if username in seen:
            raise ValueError('Duplicate account name.')
        seen.add(username)
        if not isinstance(user.get('enabled', True), bool):
            raise ValueError('enabled must be a boolean.')
        if not user.get('enabled', True):
            continue
        password = user.get('password')
        if not isinstance(password, str) or not password or any(ord(c) < 32 or ord(c) == 127 for c in password):
            raise ValueError('Enabled accounts require a nonempty password without control characters.')
        access = user.get('access')
        if not isinstance(access, list) or not access:
            raise ValueError('Enabled accounts require explicit access entries.')
        databases = set()
        for grant in access:
            if not isinstance(grant, dict) or set(grant) != {'database', 'schemas', 'owners'}:
                raise ValueError('Each access entry requires database, schemas, and owners.')
            database = name(grant['database'])
            if database in databases or database in {'template0', 'template1'}:
                raise ValueError('Duplicate or template database.')
            databases.add(database)
            for field in ('schemas', 'owners'):
                values = grant[field]
                if not isinstance(values, list) or not values:
                    raise ValueError('schemas and owners must be nonempty arrays.')
                for value in values:
                    name(value)
                if len(set(values)) != len(values):
                    raise ValueError('Duplicate schema or owner.')
            if any(s.startswith('pg_') or s == 'information_schema' for s in grant['schemas']):
                raise ValueError('System schemas cannot be configured.')
    return data['users']


def literal(value):
    return "'" + value.replace("'", "''") + "'"


def identifier(value):
    return '"' + name(value) + '"'


def scope_marker(user):
    scope = sorted((g['database'], sorted(g['schemas']), sorted(g['owners'])) for g in user['access'])
    return MARKER + hashlib.sha256(json.dumps(scope).encode()).hexdigest()


class Config:
    def __init__(self, root):
        self.root = root
        selection = (root / '_clusters/selection').read_text().strip()
        if not selection or '/' in selection or selection in {'.', '..'}:
            raise ValueError('Invalid cluster selection.')
        self.cluster = root / '_clusters' / selection

    def path(self, package, option):
        override = self.cluster / package / option
        return override if override.exists() else self.root / package / option

    def get(self, package, option):
        return self.path(package, option).read_text().strip()


class Postgres:
    def __init__(self, config):
        self.psql = shutil.which('psql') or '/opt/homebrew/opt/libpq/bin/psql'
        self.admin = config.get('aws-rds-postgres', 'db-username')
        password = config.get('aws-rds-postgres', 'db-password') if config.get('aws-rds-postgres', 'manage-master-user-pw') != 'true' else self.managed_password(config)
        # Do not inherit connection/service overrides or client SQL initialization.
        self.env = {k: v for k, v in os.environ.items() if not k.startswith('PG')}
        self.env.update(PGHOST=config.get('aws-rds-postgres', 'endpoint'),
                        PGPORT=config.get('aws-rds-postgres', 'db-port'), PGUSER=self.admin,
                        PGPASSWORD=password, PGSSLMODE='require', PGCONNECT_TIMEOUT='15',
                        PGOPTIONS='-c standard_conforming_strings=on -c statement_timeout=60000 -c lock_timeout=10000')

    @staticmethod
    def managed_password(config):
        result = subprocess.run(['aws', '--profile', config.get('aws', 'cli_profile'),
                                 '--region', config.get('aws', 'region'), 'secretsmanager',
                                 'get-secret-value', '--secret-id',
                                 config.get('aws-rds-postgres', 'master-user-secret-arn'),
                                 '--output', 'json'], capture_output=True, text=True)
        if result.returncode:
            raise ValueError('Could not retrieve the RDS master secret.')
        try:
            return json.loads(json.loads(result.stdout)['SecretString'])['password']
        except (ValueError, KeyError, TypeError):
            raise ValueError('Invalid RDS master secret response.') from None

    def run(self, database, sql):
        result = subprocess.run([self.psql, '-X', '-w', '-qAt', '-v', 'ON_ERROR_STOP=1'],
                                input=sql, env=dict(self.env, PGDATABASE=database),
                                capture_output=True, text=True)
        if result.returncode:
            # psql error context may contain the complete ALTER ROLE password statement.
            raise ValueError('PostgreSQL operation failed; SQL/error output suppressed to protect credentials.')
        return result.stdout.strip()

    def query(self, database, sql):
        output = self.run(database, f'SELECT coalesce(json_agg(t),\'[]\'::json) FROM ({sql}) t;')
        return json.loads(output)


def audit(db, database, user, allowed):
    """Reject effective access beyond the configured ordinary table/schema grants."""
    role = literal(user['username'])
    schemas = ','.join(literal(s) for s in allowed) or "''"
    unsafe = db.query(database, f"""
        SELECT 'database create' AS reason WHERE has_database_privilege({role}, current_database(), 'CREATE')
        UNION ALL
        SELECT 'schema create' FROM pg_namespace n
          WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'
          AND has_schema_privilege({role}, n.oid, 'CREATE')
        UNION ALL
        SELECT 'table write or unlisted read' FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
          WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'
          AND c.relkind IN ('r','p','v','m','f')
          AND (has_table_privilege({role}, c.oid, 'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
            OR has_any_column_privilege({role}, c.oid, 'INSERT,UPDATE,REFERENCES')
            OR (n.nspname NOT IN ({schemas}) AND
                (has_table_privilege({role}, c.oid, 'SELECT') OR has_any_column_privilege({role}, c.oid, 'SELECT'))))
        UNION ALL
        SELECT 'sequence write' FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
          WHERE c.relkind='S' AND n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'
          AND CASE WHEN c.relkind='S' THEN has_sequence_privilege({role}, c.oid, 'USAGE,UPDATE') ELSE false END
        UNION ALL
        SELECT 'security definer routine' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
          WHERE p.prosecdef AND n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'
          AND has_function_privilege({role}, p.oid, 'EXECUTE')
        UNION ALL
        SELECT 'unsafe future object privileges' FROM pg_default_acl d
          CROSS JOIN LATERAL aclexplode(d.defaclacl) a
          LEFT JOIN pg_namespace n ON n.oid=d.defaclnamespace
          WHERE a.grantee IN (0, (SELECT oid FROM pg_roles WHERE rolname={role}))
          AND ((d.defaclobjtype='r' AND (a.privilege_type <> 'SELECT'
                OR coalesce(n.nspname, '') NOT IN ({schemas})))
            OR (d.defaclobjtype='S' AND a.privilege_type IN ('USAGE','UPDATE')))
    """)
    if unsafe:
        raise ValueError(f'Unsafe effective privileges in {database}; account remains disabled. Review PUBLIC grants and existing ACLs.')
    if allowed:
        missing = db.query(database, f"""
            SELECT 'schema usage' AS reason FROM pg_namespace n
              WHERE n.nspname IN ({schemas}) AND NOT has_schema_privilege({role}, n.oid, 'USAGE')
            UNION ALL
            SELECT 'table select' FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
              WHERE n.nspname IN ({schemas}) AND c.relkind IN ('r','p','v','m','f')
              AND NOT has_table_privilege({role}, c.oid, 'SELECT')
            UNION ALL
            SELECT 'database connect' WHERE NOT has_database_privilege({role}, current_database(), 'CONNECT')
        """)
        if missing:
            raise ValueError(f'Required read grants are missing in {database}; account remains disabled. Check administrator grant authority.')


def sync(db, users):
    databases = [r['datname'] for r in db.query('postgres',
        "SELECT datname FROM pg_database WHERE datallowconn AND NOT datistemplate AND datname <> 'rdsadmin'")]
    # Validate the entire manifest before creating accounts or rotating passwords.
    for user in users:
        username = user['username']
        if username == db.admin:
            raise ValueError('Cannot manage the deployment administrator as a reader.')
        roles = db.query('postgres', f"""SELECT oid, rolname, rolsuper, rolcreaterole, rolcreatedb,
            rolreplication, rolbypassrls, shobj_description(oid,'pg_authid') AS marker,
            EXISTS(SELECT 1 FROM pg_auth_members WHERE member=pg_roles.oid) AS memberships
            FROM pg_roles WHERE rolname={literal(username)}""")
        if roles:
            role = roles[0]
            if not (role['marker'] or '').startswith(MARKER):
                raise ValueError('Refusing to modify an existing unmanaged account.')
            if any(role[k] for k in ('rolsuper', 'rolcreaterole', 'rolcreatedb', 'rolreplication', 'rolbypassrls', 'memberships')):
                raise ValueError('Managed account has unexpected elevated privileges or role memberships.')
            if user.get('enabled', True) and role['marker'] != scope_marker(user):
                raise ValueError('Account scope changed. Disable the old account and configure a new username for the new scope.')
        if not user.get('enabled', True):
            continue
        for grant in user['access']:
            database = grant['database']
            if database not in databases:
                raise ValueError('A configured database does not exist or does not allow connections.')
            existing = db.query(database, 'SELECT nspname FROM pg_namespace')
            if not set(grant['schemas']) <= {r['nspname'] for r in existing}:
                raise ValueError('A configured schema does not exist.')
            existing = db.query(database, 'SELECT rolname FROM pg_roles')
            if not set(grant['owners']) <= {r['rolname'] for r in existing}:
                raise ValueError('A configured table-creating role does not exist.')

    for user in users:
        role = identifier(user['username'])
        exists = db.query('postgres', f'SELECT 1 FROM pg_roles WHERE rolname={literal(user["username"])}')
        if exists:
            db.run('postgres', f'ALTER ROLE {role} NOLOGIN;')
            # Disable current sessions as well as future connections before reconciling ACLs.
            db.run('postgres', f'SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE usename={literal(user["username"])} AND pid <> pg_backend_pid();')
        if not user.get('enabled', True):
            continue
        if not exists:
            db.run('postgres', f'BEGIN; CREATE ROLE {role} NOLOGIN; COMMENT ON ROLE {role} IS {literal(scope_marker(user))}; COMMIT;')
        # CREATE ROLE defaults are unprivileged; preflight rejects elevated roles.
        # RDS administrators cannot ALTER SUPERUSER/REPLICATION/BYPASSRLS flags.
        db.run('postgres', f"""ALTER ROLE {role} NOINHERIT
            PASSWORD {literal(user['password'])};
            ALTER ROLE {role} SET default_transaction_read_only = on;""")
        for grant in user['access']:
            commands = [f'GRANT CONNECT ON DATABASE {identifier(grant["database"])} TO {role};']
            for schema in grant['schemas']:
                schema = identifier(schema)
                commands.extend([f'GRANT USAGE ON SCHEMA {schema} TO {role};',
                                 f'GRANT SELECT ON ALL TABLES IN SCHEMA {schema} TO {role};'])
                for owner in grant['owners']:
                    commands.append(f'ALTER DEFAULT PRIVILEGES FOR ROLE {identifier(owner)} IN SCHEMA {schema} GRANT SELECT ON TABLES TO {role};')
            db.run(grant['database'], 'BEGIN;\n' + '\n'.join(commands) + '\nCOMMIT;')
        scope = {g['database']: g['schemas'] for g in user['access']}
        for database in databases:
            audit(db, database, user, scope.get(database, []))

    # No account is enabled unless every requested reconciliation and audit succeeded.
    for user in users:
        if user.get('enabled', True):
            db.run('postgres', f'ALTER ROLE {identifier(user["username"])} LOGIN;')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, help='Override the credentials JSON path')
    parser.add_argument('--config-root', type=Path, default=ROOT / 'config')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--check', action='store_true', help='Offline validation only (default)')
    mode.add_argument('--apply', action='store_true', help='Create/update/disable live accounts')
    args = parser.parse_args()
    try:
        config = None
        path = args.config
        if path is None:
            config = Config(args.config_root)
            path = config.path('aws-rds-postgres', 'read-only-users.json')
            if not path.exists():
                print('No read-only account configuration; skipping.')
                return 0
        users = load_users(path)
        if args.apply and users:
            config = config or Config(args.config_root)
            sync(Postgres(config), users)
        print(f'Read-only accounts: {len(users)} entries ' + ('synchronized.' if args.apply else 'validated (offline).'))
        return 0
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        # Never include raw OS errors, file contents, subprocess output or SQL.
        message = str(error) if isinstance(error, ValueError) and not isinstance(error, json.JSONDecodeError) else 'Could not complete account synchronization; check configuration and dependencies.'
        print(message, file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
