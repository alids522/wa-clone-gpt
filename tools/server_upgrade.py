"""SSH-side upgrade runner. Read the release payload from stdin; never log it.

Run as the existing Docker operator. Unrelated containers are not modified.
The caller must have tested the migrations in a separate database first.
"""
import base64
import datetime
import hashlib
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys

os.umask(0o077)
payload = json.load(sys.stdin)
firebase = base64.b64decode(payload['firebase'])
account = json.loads(firebase)
if account.get('type') != 'service_account' or account.get('project_id') != payload['firebase_project']:
    raise ValueError('Firebase project mismatch')
home = Path.home() / '.cache' / 'adoetz-deploy'
home.mkdir(parents=True, exist_ok=True)

def command(args, data=None):
    result = subprocess.run(args, input=data, capture_output=True)
    if result.returncode:
        # Command output can contain credentials. Report only the operation.
        raise RuntimeError('Server operation failed: ' + ' '.join(args[:3]))
    return result.stdout

def sql(query):
    return command(['docker', 'exec', '-i', 'supabase-db', 'psql', '-X', '-q', '-At', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1'], query.encode()).decode().strip()

def function_file(relative, data):
    if '..' in Path(relative).parts or relative.startswith('/'):
        raise ValueError('Invalid release path')
    path = '/home/deno/functions/' + relative
    import shlex
    command(['docker', 'exec', '-i', 'supabase-edge-functions', 'sh', '-c',
             'umask 077; mkdir -p ' + shlex.quote(str(Path(path).parent)) + '; cat > ' + shlex.quote(path)], data)

before_users = int(sql('select count(*) from auth.users'))
before_ids = sql("select coalesce(jsonb_object_agg(user_id,bundle->>'identity_key'),'{}') from public.devices")
if not before_users or not sql("select to_regclass('private.accounts')"):
    raise RuntimeError('The foundation must already be installed')

backup = home / ('before-rich-chat-' + datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '.dump')
with backup.open('wb') as stream:
    subprocess.run(['docker', 'exec', 'supabase-db', 'pg_dump', '-U', 'postgres', '-d', 'postgres', '-Fc', '-n', 'auth', '-n', 'public', '-n', 'private', '-n', 'storage'], stdout=stream, stderr=subprocess.PIPE, check=True)
print('Backup created', flush=True)
sql('create table if not exists private.deployment_versions(version text primary key, sha256 text not null, installed_at timestamptz default now()); alter table private.deployment_versions enable row level security; revoke all on private.deployment_versions from public,anon,authenticated;')
for migration in payload['migrations']:
    version = migration['name']
    if not version.replace('_', '').replace('.', '').isalnum():
        raise ValueError('Invalid migration name')
    content = base64.b64decode(migration['content']).replace(b'\r\n',b'\n')
    digest = hashlib.sha256(content).hexdigest()
    installed = sql("select sha256 from private.deployment_versions where version='" + version + "'")
    if installed and installed != digest:
        raise RuntimeError('An installed migration was modified')
    if not installed:
        sql('begin;\n' + content.decode() + "\ninsert into private.deployment_versions(version,sha256) values('" + version + "','" + digest + "'); commit;")
        print('Installed ' + version, flush=True)

for file in payload['functions']:
    function_file(file['path'], base64.b64decode(file['content']))
function_file('_secrets/firebase-service-account.json', firebase)

turn_path = home / 'turn.json'
turn = json.loads(turn_path.read_text()) if turn_path.exists() else {'secret': secrets.token_urlsafe(48)}
public_ip = payload['public_ip']
import ipaddress
ipaddress.IPv4Address(public_ip)
turn['urls'] = ['turn:' + public_ip + ':3478?transport=udp', 'turn:' + public_ip + ':3478?transport=tcp']
turn_path.write_text(json.dumps(turn))
function_file('_secrets/turn.json', json.dumps(turn).encode())
# Detect the host's outbound IPv4 without relying on DNS.
import socket
probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
probe.connect(('1.1.1.1', 53))
private_ip = probe.getsockname()[0]
probe.close()
config = '\n'.join([
    'listening-port=3478', 'listening-ip=0.0.0.0', 'relay-ip=' + private_ip,
    'external-ip=' + public_ip + '/' + private_ip, 'min-port=49160', 'max-port=49259',
    'fingerprint', 'use-auth-secret', 'static-auth-secret=' + turn['secret'],
    'realm=adoetzchat', 'no-cli', 'no-tls', 'no-dtls', 'no-multicast-peers',
    'denied-peer-ip=0.0.0.0-0.255.255.255', 'denied-peer-ip=10.0.0.0-10.255.255.255',
    'denied-peer-ip=127.0.0.0-127.255.255.255', 'denied-peer-ip=169.254.0.0-169.254.255.255',
    'denied-peer-ip=172.16.0.0-172.31.255.255', 'denied-peer-ip=192.168.0.0-192.168.255.255',
    'user-quota=8', 'total-quota=200', 'max-bps=2000000', 'no-tcp-relay',
    'log-file=stdout', 'simple-log', 'pidfile=/tmp/turnserver.pid',
]) + '\n'
(home / 'turnserver.conf').write_text(config)

environment = dict(item.split('=', 1) for item in json.loads(command(['docker', 'inspect', 'supabase-edge-functions', '--format', '{{json .Config.Env}}'])))
(home / 'worker.env').write_text('SUPABASE_SERVICE_ROLE_KEY=' + environment['SUPABASE_SERVICE_ROLE_KEY'] + '\n')
(home / 'push_worker.py').write_bytes(base64.b64decode(payload['worker']))
command(['docker', 'restart', 'supabase-edge-functions'])
print('Edge Functions and private Firebase configuration installed', flush=True)
for name, image, args in [
    ('adoetz-turn', 'coturn/coturn:4.18.0-r0', ['--user', str(os.getuid()) + ':' + str(os.getgid()), '-v', str(home / 'turnserver.conf') + ':/etc/coturn/turnserver.conf:ro', '--entrypoint', 'turnserver']),
    ('adoetz-push-worker', 'python:3.12-slim', ['--env-file', str(home / 'worker.env'), '-v', str(home / 'push_worker.py') + ':/app/push_worker.py:ro']),
]:
    command(['docker', 'pull', image])
    existing = command(['docker', 'ps', '-a', '--filter', 'name=^/' + name + '$', '--format', '{{.Names}}']).decode().strip()
    if existing == name:
        command(['docker', 'rm', '-f', name])
    tail = ['-c', '/etc/coturn/turnserver.conf'] if name == 'adoetz-turn' else ['python', '/app/push_worker.py']
    command(['docker', 'run', '-d', '--name', name, '--restart', 'unless-stopped', '--network', 'host', '--log-opt', 'max-size=10m', '--log-opt', 'max-file=3', *args, image, *tail])
    print('Started ' + name, flush=True)
if int(sql('select count(*) from auth.users')) < before_users:
    raise RuntimeError('Unexpected user count change')
after_ids = sql("select coalesce(jsonb_object_agg(user_id,bundle->>'identity_key'),'{}') from public.devices")
if before_ids != after_ids:
    raise RuntimeError('A legacy identity changed during deployment')
print('Existing accounts and legacy identities preserved', flush=True)
