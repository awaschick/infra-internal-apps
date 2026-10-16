#!/usr/bin/env python3
"""Plan Construct with mocked providers and synthetic config; never reads credentials or contacts a cluster."""
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
terraform = repo / '.venv/bin/terraform'
source = repo / 'terraform/app-atlas-construct'
text = (source / 'main.tf').read_text()
options = re.findall(r'package = "([^"]+)", option = "([^"]+)"', text)
values = {
    'region': 'us-east-1', 'site-domain': 'example.com', 'domain-aws-id': 'Z123456',
    'app-name': 'construct-test', 'kubernetes-namespace': 'construct-test',
    'site-hostname': 'construct', 'private-deployment': 'false',
    'private-hostname-segment-enabled': 'false', 'replicas': '1',
    'container-port': '5174', 'server-port': '4001', 'service-port': '80',
    'port': '5432', 'image-uri': 'example.com/construct:test', 'image-pull-policy': 'IfNotPresent',
    'construct-data-volume-size': '10Gi', 'storage-class': 'gp3',
    'private-subnet-ids': 'subnet-12345', 'public-subnet-ids': 'subnet-12345',
    'core-shell-port': '4100', 'core-shell-env': 'uat', 'core-shell-reference-client': 'Ezee',
    'core-shell-site-hostname': '', 'construct-data-dir': '/app/backend/data',
    'clients-json-path': '', 'core-preview-urls-path': '', 'morpheus-data-dir': '', 'log-dir': '',
    'allowed-origin': '',
    'core-shell-mirror': '1',
    'css-design-render': 'on',
    'morpheus-slack-engine': 'agent',
    'cpu-request': '500m',
    'memory-request': '1Gi',
    'cpu-limit': '2',
    'memory-limit': '6Gi',

}
mock = '''
mock_provider "aws" {
  mock_resource "aws_acm_certificate" {
    defaults = {
      domain_validation_options = [{
        domain_name = "construct.example.com"
        resource_record_name = "_test.construct.example.com"
        resource_record_type = "CNAME"
        resource_record_value = "_test.acm-validations.aws"
      }]
    }
  }
}
mock_provider "kubernetes" {}
mock_provider "local" {}
variables { kubeconfig = "/unused/mock-kubeconfig" }
'''
for scenario in ['disabled', 'enabled', 'replicas', 'production', 'same-host', 'same-port']:
    with tempfile.TemporaryDirectory(prefix='construct-tf-') as tmp:
        root = Path(tmp)
        module = root / 'terraform/app-atlas-construct'
        module.mkdir(parents=True)
        shutil.copy(source / 'main.tf', module)
        shutil.copy(source / '.terraform.lock.hcl', module)
        (module / '.terraform').mkdir()
        (module / '.terraform/providers').symlink_to(source / '.terraform/providers', target_is_directory=True)
        (root / 'terraform/_helpers').mkdir()
        shutil.copy(repo / 'terraform/_helpers/config-instance.tmpl', root / 'terraform/_helpers')
        config = root / 'config'
        (config / '_clusters').mkdir(parents=True)
        (config / '_clusters/selection').write_text('test')
        actual = values | {'core-shell-enabled': 'false' if scenario == 'disabled' else 'true'}
        if scenario == 'replicas': actual['replicas'] = '2'
        if scenario == 'production': actual['core-shell-env'] = 'prd'
        if scenario == 'same-host': actual['core-shell-site-hostname'] = 'construct'
        if scenario == 'same-port': actual['core-shell-port'] = '4001'
        for package, option in options:
            folder = config / package
            folder.mkdir(exist_ok=True)
            (folder / option).write_text(actual.get(option, 'test'))
        if scenario in ['disabled', 'enabled']:
            enabled = scenario == 'enabled'
            assertions = f'''
  assert {{
    condition = kubernetes_deployment_v1.app.spec[0].strategy[0].type == "Recreate" && tonumber(kubernetes_deployment_v1.app.spec[0].replicas) == 1
    error_message = "Single-writer rollout is not enforced"
  }}
  assert {{
    condition = length(kubernetes_service_v1.app.spec[0].port) == {2 if enabled else 1} && length(kubernetes_ingress_v1.app_public.spec[0].rule) == {2 if enabled else 1}
    error_message = "Wrong listener/routing count"
  }}
  assert {{
    condition = length(aws_acm_certificate.app.subject_alternative_names) == {1 if enabled else 0} && length(aws_route53_record.core_shell_cname) == {1 if enabled else 0}
    error_message = "Wrong preview DNS/TLS configuration"
  }}
'''
            assertions += '''
  assert {
    condition = kubernetes_secret_v1.app_env.data["CSS_DESIGN_CHROMIUM_PATH"] == "/usr/bin/chromium" && kubernetes_secret_v1.app_env.data["CSS_DESIGN_RENDER"] == "on" && kubernetes_secret_v1.app_env.data["MORPHEUS_SLACK_ENGINE"] == "agent"
    error_message = "Release renderer/agent configuration is missing"
  }
  assert {
    condition = kubernetes_deployment_v1.app.spec[0].template[0].spec[0].container[0].resources[0].limits["memory"] == "6Gi" && kubernetes_deployment_v1.app.spec[0].template[0].spec[0].container[0].resources[0].requests["memory"] == "1Gi"
    error_message = "Browser and agent resource budget is missing"
  }
'''
            if enabled:
                assertions += '''
  assert {
    condition = kubernetes_secret_v1.app_env.data["CORE_SHELL_ENV"] == "uat" && kubernetes_secret_v1.app_env.data["CORE_SHELL_MIRROR"] == "1" && kubernetes_secret_v1.app_env.data["CORE_SHELL_PUBLIC_ORIGIN"] == "https://preview.construct.example.com" && kubernetes_secret_v1.app_env.data["CORE_SHELL_EDITOR_ORIGIN"] == "https://construct.example.com"
    error_message = "Preview/editor origins differ from ingress"
  }
  assert {
    condition = kubernetes_deployment_v1.app.spec[0].template[0].spec[0].container[0].readiness_probe[0].exec[0].command == tolist(["node", "/app/healthcheck.cjs"])
    error_message = "Enabled shell is absent from readiness"
  }
'''
        else:
            assertions = '  expect_failures = [kubernetes_deployment_v1.app]\n'
        (module / 'deployment.tftest.hcl').write_text(mock + '\nrun "' + scenario.replace('-', '_') + '" {\n  command = plan\n' + assertions + '}\n')
        for args in [('init', '-backend=false', '-input=false'), ('test', '-no-color')]:
            result = subprocess.run([str(terraform), *args], cwd=module, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            if result.returncode:
                print(result.stdout)
                raise SystemExit(result.returncode)
        print(f'{scenario}: mocked Terraform plan passed')
