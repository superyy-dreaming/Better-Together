#!/usr/bin/env python3
"""Read local configuration without printing credentials or making requests."""

import base64
import argparse
import ipaddress
import json
from pathlib import Path
import re
import stat
import sys
from urllib.parse import urlparse


ROOT = Path(__file__).resolve().parent.parent
LOCAL = ROOT / '.local'
issues = []


def check(label, condition):
    print(f'{"就绪" if condition else "待补"}：{label}')
    if not condition:
        issues.append(label)


def filled(value):
    text = str(value or '').strip()
    return bool(text) and not any(
        marker in text for marker in ('YOUR_', 'REPLACE_', '/absolute/secure/', '<project')
    )


def private_file(path):
    """Require a regular, owner-readable/writable 0600 file, not a symlink."""
    try:
        info = path.lstat()
        return stat.S_ISREG(info.st_mode) and stat.S_IMODE(info.st_mode) == 0o600
    except OSError:
        return False


def parse_values(content):
    """Parse our simple local key/value format and reject ambiguous duplicates."""
    values = {}
    for line in content.splitlines():
        line = line.strip()
        if not line or line.startswith(('#', '//')):
            continue
        if '=' not in line:
            raise ValueError('invalid configuration line')
        key, value = (part.strip() for part in line.split('=', 1))
        if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', key) or key in values:
            raise ValueError('invalid or repeated configuration key')
        if value.startswith(('"', "'")):
            if len(value) < 2 or value[-1] != value[0]:
                raise ValueError('unclosed configuration value')
            value = value[1:-1]
        values[key] = value
    return values


def read(name, structured=False):
    path = LOCAL / name
    try:
        check(f'{name} 为权限 600 的常规文件', private_file(path))
        if not stat.S_ISREG(path.lstat().st_mode):
            return {}
        content = path.read_text()
        if structured:
            value = json.loads(content)
            return value if isinstance(value, dict) else {}
        return parse_values(content)
    except (OSError, ValueError):
        check(f'{name} 存在且格式可读', False)
        return {}


def public_key(value):
    if not filled(value):
        return False
    if value.startswith('sb_publishable_'):
        return re.fullmatch(r'sb_publishable_[A-Za-z0-9_-]+', value) is not None
    try:
        payload = value.split('.')[1]
        decoded = json.loads(base64.urlsafe_b64decode(payload + '=' * (-len(payload) % 4)))
        return isinstance(decoded, dict) and decoded.get('role') == 'anon'
    except (ValueError, IndexError, TypeError):
        return False


def https_endpoint(value):
    text = str(value or '').strip()
    if not text or any(ord(char) <= 32 or ord(char) == 127 for char in text):
        return False
    try:
        url = urlparse(text)
        # Validate port syntax too; this checker intentionally performs no DNS.
        url.port
        if (url.scheme != 'https' or not url.hostname or url.username
                or url.password or any(char in text for char in '\\?#')
                or '@' in url.netloc):
            return False
        host = url.hostname.lower().rstrip('.')
        if host in ('localhost', 'metadata') or host.endswith(
                ('.localhost', '.local', '.internal', '.lan', '.home', '.invalid', '.test')):
            return False
        try:
            address = ipaddress.ip_address(host)
        except ValueError:
            # Reject alternate numeric-IP spellings that URL clients may resolve
            # as localhost, instead of treating them as ordinary DNS names.
            if ':' in host or all(re.fullmatch(r'(?:0x[0-9a-f]+|[0-9]+)', label)
                                  for label in host.split('.')):
                return False
            hostname = host.encode('idna').decode('ascii')
            return ('.' in hostname and len(hostname) <= 253
                    and not hostname.split('.')[-1].isdigit() and all(
                re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', label)
                for label in hostname.split('.')))
        reserved = ('2001::/23', '2001:db8::/32', '2002::/16', '3fff::/20')
        if address.version == 6 and (not address in ipaddress.ip_network('2000::/3')
                                    or any(address in ipaddress.ip_network(net) for net in reserved)):
            return False
        return (address.is_global and not address.is_multicast
                and not address.is_reserved
                and not getattr(address, 'ipv4_mapped', None))
    except (ValueError, UnicodeError):
        return False


def encryption_key(value):
    if not isinstance(value, str):
        return False
    try:
        return len(base64.b64decode(value, validate=True)) == 32
    except (ValueError, TypeError):
        return False


def validate_configuration(simulator=False):
    issues.clear()
    try:
        directory = LOCAL.lstat()
        local_private = stat.S_ISDIR(directory.st_mode) and stat.S_IMODE(directory.st_mode) == 0o700
    except OSError:
        local_private = False
    check('.local 为权限 700 的常规目录', local_private)
    client = read('client.json', structured=True)
    check('Supabase HTTPS 项目地址', https_endpoint(client.get('SUPABASE_URL')))
    check('Supabase 客户端公开 key', public_key(str(client.get('SUPABASE_ANON_KEY', ''))))
    check('正式配置关闭演示', client.get('DEMO_MODE') is False)
    allowed = {'SUPABASE_URL', 'SUPABASE_ANON_KEY', 'APP_LINK_HOST', 'JPUSH_APP_KEY', 'DEMO_MODE'}
    check('客户端没有额外私密配置项', not (client.keys() - allowed))

    server = read('server.env')
    check('服务端没有 AI 配置或密钥', not any(name.startswith('OPENAI_') or name.startswith('AI_SETTINGS_') for name in server))
    job = server.get('JOB_SECRET', '')
    check('JOB_SECRET 已填写且无空白或控制字符', filled(job) and not any(char.isspace() or ord(char) < 32 or ord(char) == 127 for char in job))

    if not simulator:
        for key in ('APNS_PRIVATE_KEY', 'APNS_KEY_ID', 'APNS_TEAM_ID', 'APNS_BUNDLE_ID',
                    'JPUSH_APP_KEY', 'JPUSH_MASTER_SECRET'):
            check(key, filled(server.get(key)))
        check('TestFlight 使用 APNs production', server.get('APNS_ENVIRONMENT') == 'production')

        ios = read('ios-signing.xcconfig')
        for key in ('DEVELOPMENT_TEAM', 'BETTER_TOGETHER_BUNDLE_ID'):
            check(f'iOS {key}', filled(ios.get(key)))
        if filled(ios.get('BETTER_TOGETHER_BUNDLE_ID')) and filled(server.get('APNS_BUNDLE_ID')):
            check('APNs 与 iOS 包标识一致', ios['BETTER_TOGETHER_BUNDLE_ID'] == server['APNS_BUNDLE_ID'])

        android = read('android-key.properties')
        for key in ('storeFile', 'storePassword', 'keyAlias', 'keyPassword', 'applicationId'):
            check(f'Android {key}', filled(android.get(key)))
        if filled(android.get('storeFile')):
            store = Path(android['storeFile']).expanduser()
            if not store.is_absolute():
                store = ROOT / 'app/android' / store
            check('Android 已有签名文件存在', store.is_file())
        push = read('android-push.properties')
        check('Android 极光 appKey', filled(push.get('appKey')))
        if filled(push.get('appKey')) and filled(server.get('JPUSH_APP_KEY')):
            check('极光客户端与服务端 appKey 一致', push['appKey'] == server['JPUSH_APP_KEY'])

    print('\n仅检查本地配置结构及已知非公网地址，不解析 DNS、不发请求、不验证密钥有效性。')
    print('打卡采用 App 直连用户自带 AI、确认后原图私有归档；无需 Image Transform，仍需验证完整链路。')
    return 1 if issues else 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--simulator', action='store_true',
                        help='只检查模拟器接入和 AI 必需项，不检查发布签名与真机推送')
    options = parser.parse_args(argv)
    return validate_configuration(simulator=options.simulator)


if __name__ == '__main__':
    sys.exit(main())
