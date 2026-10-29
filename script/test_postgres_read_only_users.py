"""Local-only tests: python3 -m unittest discover -s script -p 'test_postgres*.py'."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import time
import copy

import sync_postgres_read_only_users as readers

SCRIPT = Path(__file__).with_name('sync_postgres_read_only_users.py')


class HookTests(unittest.TestCase):
    def test_failed_apply_never_runs_completion_hook(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'script').mkdir()
            (root / '.venv/bin').mkdir(parents=True)
            (root / '.venv/bin/activate').touch()
            (root / 'terraform/example/_init').mkdir(parents=True)
            (root / 'state').mkdir()
            (root / 'script/terraform_launcher.sh').write_text(SCRIPT.with_name('terraform_launcher.sh').read_text())
            (root / 'script/common.sh').write_text(f'''base_path='{root}'
terraform_path='{root}/terraform'
cluster_state_path='{root}/state'
alias_cluster_state_path='{root}/terraform/_state'
cluster_config_path='{root}/config'
''')
            (root / 'terraform/example/_init/start_complete.sh').write_text(f'touch "{root}/hook-ran"\n')
            executable = root / '.venv/bin/terraform'
            executable.write_text('#!/bin/bash\nif [ "$1" = apply ]; then exit 42; fi\n')
            executable.chmod(0o755)
            result = subprocess.run(['bash', '-c', 'mode=start; source script/terraform_launcher.sh example'],
                                    cwd=root, env=dict(os.environ, PATH=f'{root}/.venv/bin:' + os.environ['PATH']),
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((root / 'hook-ran').exists())


class ConfigTests(unittest.TestCase):
    def run_config(self, data):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'users.json'
            path.write_text(json.dumps(data))
            return subprocess.run(['python3', str(SCRIPT), '--config', str(path), '--check'],
                                  capture_output=True, text=True)

    def account(self):
        return {'username': 'report_reader', 'password': "secret'with\\quotes",
                'access': [{'database': 'example', 'schemas': ['public'],
                            'owners': ['app_owner']}]}

    def test_valid_configuration(self):
        result = self.run_config({'users': [self.account()]})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("secret", result.stdout + result.stderr)

    def test_invalid_configuration_never_echoes_passwords(self):
        for field, value in [('username', 'postgres'), ('password', ''),
                             ('access', []), ('enabled', 'false'),
                             ('username', 'unsafe;sql'), ('password', 'secret\n\\q')]:
            account = self.account()
            account[field] = value
            result = self.run_config({'users': [account]})
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn('secret', result.stdout + result.stderr)

    def test_duplicate_accounts_rejected(self):
        result = self.run_config({'users': [self.account(), self.account()]})
        self.assertNotEqual(result.returncode, 0)

    def test_missing_owners_rejected(self):
        account = self.account()
        del account['access'][0]['owners']
        self.assertNotEqual(self.run_config({'users': [account]}).returncode, 0)

    def test_disabled_account_requires_no_credentials(self):
        result = self.run_config({'users': [{'username': 'report_reader', 'enabled': False}]})
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_optional_file_and_cluster_override(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / '_clusters/test/aws-rds-postgres').mkdir(parents=True)
            (root / '_clusters/selection').write_text('test')
            command = ['python3', str(SCRIPT), '--config-root', str(root), '--check']
            absent = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(absent.returncode, 0, absent.stderr)
            self.assertIn('skipping', absent.stdout)
            (root / 'aws-rds-postgres').mkdir()
            (root / 'aws-rds-postgres/read-only-users.json').write_text('invalid')
            fallback = subprocess.run(command, capture_output=True, text=True)
            self.assertNotEqual(fallback.returncode, 0)
            (root / '_clusters/test/aws-rds-postgres/read-only-users.json').write_text('{"users":[]}')
            override = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(override.returncode, 0, override.stderr)


@unittest.skipUnless(os.environ.get('RUN_POSTGRES_INTEGRATION') == '1', 'Opt in to disposable Docker PostgreSQL')
class IntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.container = subprocess.check_output([
            'docker', 'run', '--rm', '-d', '-e', 'POSTGRES_PASSWORD=test_admin_password',
            '-p', '127.0.0.1::5432', 'postgres:16-alpine'], text=True).strip()
        cls.addClassCleanup(subprocess.run, ['docker', 'rm', '-f', cls.container], capture_output=True)
        port = subprocess.check_output(['docker', 'port', cls.container, '5432'], text=True).strip().rsplit(':', 1)[1]
        cls.directory = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.directory.cleanup)
        root = Path(cls.directory.name)
        (root / '_clusters').mkdir()
        (root / '_clusters/selection').write_text('test')
        package = root / 'aws-rds-postgres'
        package.mkdir()
        for key, value in {'endpoint': '127.0.0.1', 'db-port': port, 'db-username': 'postgres',
                           'db-password': 'test_admin_password', 'manage-master-user-pw': 'false'}.items():
            (package / key).write_text(value)
        cls.db = readers.Postgres(readers.Config(root))
        # Only this disposable server lacks TLS. Production always requires TLS.
        cls.db.env['PGSSLMODE'] = 'disable'
        for _ in range(60):
            try:
                cls.db.run('postgres', 'SELECT 1;')
                break
            except ValueError:
                time.sleep(0.25)
        else:
            raise RuntimeError('Disposable PostgreSQL did not become ready.')
        cls.db.run('postgres', 'CREATE ROLE app_owner; CREATE DATABASE example OWNER app_owner;')
        cls.db.run('example', '''SET ROLE app_owner;
            CREATE SCHEMA reporting; CREATE SCHEMA private;
            CREATE TABLE reporting.existing (id int); INSERT INTO reporting.existing VALUES (7);
            CREATE TABLE private.hidden (id int);''')

    def account(self, username):
        return {'username': username, 'password': "test'password\\literal",
                'access': [{'database': 'example', 'schemas': ['reporting'], 'owners': ['app_owner']}]}

    def as_reader(self, user, sql):
        connection = copy.copy(self.db)
        connection.env = dict(self.db.env, PGUSER=user['username'], PGPASSWORD=user['password'])
        return connection.run('example', sql)

    def test_grants_rotation_future_tables_and_disable(self):
        user = self.account('test_reader')
        readers.sync(self.db, [user])
        self.assertEqual(self.as_reader(user, 'SELECT id FROM reporting.existing;'), '7')
        for sql in ['INSERT INTO reporting.existing VALUES (8);',
                    'UPDATE reporting.existing SET id=8;', 'DELETE FROM reporting.existing;',
                    'TRUNCATE reporting.existing;', 'CREATE TABLE reporting.bad(id int);',
                    'SELECT * FROM private.hidden;']:
            with self.assertRaises(ValueError):
                self.as_reader(user, 'SET default_transaction_read_only=off; ' + sql)
        self.db.run('example', 'SET ROLE app_owner; CREATE TABLE reporting.future(id int); INSERT INTO reporting.future VALUES (9);')
        self.assertEqual(self.as_reader(user, 'SELECT id FROM reporting.future;'), '9')
        readers.sync(self.db, [user])
        changed = dict(user, password='rotated_password')
        readers.sync(self.db, [changed])
        self.assertEqual(self.as_reader(changed, 'SELECT id FROM reporting.existing;'), '7')
        with self.assertRaises(ValueError):
            self.as_reader(user, 'SELECT 1;')
        readers.sync(self.db, [{'username': user['username'], 'enabled': False}])
        with self.assertRaises(ValueError):
            self.as_reader(changed, 'SELECT 1;')

    def test_unmanaged_scope_changes_and_missing_schema_rejected(self):
        self.db.run('postgres', 'CREATE ROLE unrelated LOGIN;')
        with self.assertRaisesRegex(ValueError, 'unmanaged'):
            readers.sync(self.db, [self.account('unrelated')])
        user = self.account('scoped_reader')
        readers.sync(self.db, [user])
        changed = copy.deepcopy(user)
        changed['access'][0]['schemas'] = ['private']
        with self.assertRaisesRegex(ValueError, 'scope changed'):
            readers.sync(self.db, [changed])
        missing = self.account('missing_schema_reader')
        missing['access'][0]['schemas'] = ['absent']
        with self.assertRaisesRegex(ValueError, 'schema does not exist'):
            readers.sync(self.db, [missing])
        self.assertEqual(self.db.query('postgres', "SELECT 1 FROM pg_roles WHERE rolname='missing_schema_reader'"), [])

    def test_public_write_grants_fail_closed(self):
        self.db.run('example', 'GRANT INSERT ON reporting.existing TO PUBLIC;')
        try:
            with self.assertRaisesRegex(ValueError, 'Unsafe effective privileges'):
                readers.sync(self.db, [self.account('unsafe_reader')])
            self.assertFalse(self.db.query('postgres', "SELECT rolcanlogin FROM pg_roles WHERE rolname='unsafe_reader'")[0]['rolcanlogin'])
        finally:
            self.db.run('example', 'REVOKE INSERT ON reporting.existing FROM PUBLIC;')

    def test_future_public_write_defaults_fail_closed(self):
        self.db.run('example', 'ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA reporting GRANT INSERT ON TABLES TO PUBLIC;')
        try:
            with self.assertRaisesRegex(ValueError, 'Unsafe effective privileges'):
                readers.sync(self.db, [self.account('unsafe_defaults_reader')])
        finally:
            self.db.run('example', 'ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA reporting REVOKE INSERT ON TABLES FROM PUBLIC;')

    def test_public_read_in_unlisted_schema_fail_closed(self):
        self.db.run('example', 'GRANT SELECT ON private.hidden TO PUBLIC;')
        try:
            with self.assertRaisesRegex(ValueError, 'Unsafe effective privileges'):
                readers.sync(self.db, [self.account('unlisted_reader')])
        finally:
            self.db.run('example', 'REVOKE SELECT ON private.hidden FROM PUBLIC;')

    def test_security_definer_fail_closed(self):
        self.db.run('example', "CREATE FUNCTION public.danger() RETURNS integer LANGUAGE sql SECURITY DEFINER AS 'SELECT 1';")
        try:
            with self.assertRaisesRegex(ValueError, 'Unsafe effective privileges'):
                readers.sync(self.db, [self.account('routine_reader')])
        finally:
            self.db.run('example', 'DROP FUNCTION public.danger();')

    def test_non_superuser_deployment_admin(self):
        self.db.run('postgres', "CREATE ROLE deploy_admin LOGIN CREATEROLE PASSWORD 'test_deploy_password'; GRANT app_owner TO deploy_admin;")
        admin = copy.copy(self.db)
        admin.admin = 'deploy_admin'
        admin.env = dict(self.db.env, PGUSER='deploy_admin', PGPASSWORD='test_deploy_password')
        user = self.account('limited_admin_reader')
        readers.sync(admin, [user])
        self.assertEqual(self.as_reader(user, 'SELECT id FROM reporting.existing;'), '7')
        readers.sync(admin, [user])


if __name__ == '__main__':
    unittest.main()
