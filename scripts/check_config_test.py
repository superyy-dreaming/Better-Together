"""Configuration parsing checks using temporary synthetic files only."""

import base64
from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import tempfile
import unittest

import check_config


class ConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='bt-config-test-')
        self.root = Path(self.temporary.name)
        self.previous_local = check_config.LOCAL
        check_config.LOCAL = self.root
        self.server = {
            'JOB_SECRET': 'synthetic-job-secret-only',
        }
        self.write('client.json', json.dumps({
            'SUPABASE_URL': 'https://synthetic.supabase.co',
            'SUPABASE_ANON_KEY': 'sb_publishable_synthetic_public_value',
            'DEMO_MODE': False,
        }))
        self.write_server()

    def tearDown(self):
        check_config.LOCAL = self.previous_local
        self.temporary.cleanup()

    def write(self, name, content):
        path = self.root / name
        path.write_text(content)
        path.chmod(0o600)

    def write_server(self):
        self.write('server.env', '\n'.join(f'{name}={value}' for name, value in self.server.items()))

    def run_check(self, *args):
        output = io.StringIO()
        with redirect_stdout(output):
            result = check_config.main(list(args))
        return result, output.getvalue()

    def test_simulator_does_not_require_signing_or_push(self):
        result, output = self.run_check('--simulator')
        self.assertEqual(result, 0)
        for unused in ('APNS', 'JPUSH', 'ios-signing', 'android-key', 'android-push'):
            self.assertNotIn(unused, output)
        self.assertNotIn('待补：生产图片模式', output)
        self.assertIn('无需 Image Transform', output)
        for value in self.server.values():
            if 'secret' in value:
                self.assertNotIn(value, output)

    def test_default_mode_still_requires_release_configuration(self):
        result, output = self.run_check()
        self.assertEqual(result, 1)
        self.assertIn('待补：APNS_PRIVATE_KEY', output)
        self.assertIn('待补：ios-signing.xcconfig 存在且格式可读', output)
        self.assertIn('待补：android-key.properties 存在且格式可读', output)

    def test_full_mode_accepts_complete_synthetic_configuration(self):
        self.server.update({
            'APNS_PRIVATE_KEY': 'synthetic-p8-secret-only',
            'APNS_KEY_ID': 'SYNTHETICKEY',
            'APNS_TEAM_ID': 'SYNTHETICTEAM',
            'APNS_BUNDLE_ID': 'com.example.synthetic',
            'APNS_ENVIRONMENT': 'production',
            'JPUSH_APP_KEY': 'synthetic-push-key',
            'JPUSH_MASTER_SECRET': 'synthetic-push-secret-only',
        })
        self.write_server()
        self.write('ios-signing.xcconfig', 'DEVELOPMENT_TEAM=SYNTHETICTEAM\nBETTER_TOGETHER_BUNDLE_ID=com.example.synthetic')
        self.write('synthetic.keystore', 'not-a-real-signing-file')
        self.write('android-key.properties', '\n'.join([
            f'storeFile={self.root / "synthetic.keystore"}',
            'storePassword=synthetic-store-secret-only', 'keyAlias=synthetic-alias',
            'keyPassword=synthetic-key-secret-only', 'applicationId=com.example.synthetic',
        ]))
        self.write('android-push.properties', 'appKey=synthetic-push-key')
        result, output = self.run_check()
        self.assertEqual(result, 0)
        self.assertNotIn('synthetic-p8-secret-only', output)
        self.assertNotIn('synthetic-store-secret-only', output)

    def test_server_ai_configuration_is_rejected_without_echo(self):
        for name in ('OPENAI_API_KEY', 'OPENAI_BASE_URL', 'AI_SETTINGS_ENCRYPTION_KEY'):
            self.server[name] = 'synthetic-residual-must-not-echo'
            self.write_server()
            result, output = self.run_check('--simulator')
            self.assertEqual(result, 1)
            self.assertNotIn(self.server[name], output)
            self.server.pop(name)

    def test_client_private_fields_and_readable_secret_permissions_still_fail(self):
        self.write('client.json', json.dumps({
            'SUPABASE_URL': 'https://synthetic.supabase.co',
            'SUPABASE_ANON_KEY': 'sb_publishable_synthetic',
            'DEMO_MODE': False, 'OPENAI_API_KEY': 'synthetic-client-secret-only',
        }))
        (self.root / 'server.env').chmod(0o644)
        result, output = self.run_check('--simulator')
        self.assertEqual(result, 1)
        self.assertIn('待补：客户端没有额外私密配置项', output)
        self.assertIn('待补：server.env 为权限 600 的常规文件', output)
        self.assertNotIn('synthetic-client-secret-only', output)
        self.root.chmod(0o755)
        result, output = self.run_check('--simulator')
        self.assertEqual(result, 1)
        self.assertIn('待补：.local 为权限 700 的常规目录', output)
        self.root.chmod(0o700)
        self.write('server.env', 'OPENAI_API_KEY=synthetic-one\nOPENAI_API_KEY=synthetic-two')
        result, output = self.run_check('--simulator')
        self.assertEqual(result, 1)
        self.assertIn('待补：server.env 存在且格式可读', output)
        self.assertNotIn('synthetic-one', output)
        self.assertNotIn('synthetic-two', output)


if __name__ == '__main__':
    unittest.main()
