"""SSH operator: deploy only tested call/history migrations, functions and worker.

Read the allowlisted, base64 release files from stdin. No signing/Firebase/server
credentials are included in the payload. Existing TURN configuration is preserved.
"""
import base64
import datetime
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys

os.umask(0o077)
payload=json.load(sys.stdin)
home=Path.home()/'.cache/adoetz-deploy'
home.mkdir(parents=True,exist_ok=True)

def run(args,data=None):
    result=subprocess.run(args,input=data,capture_output=True)
    if result.returncode: raise RuntimeError('Deployment operation failed: '+' '.join(args[:3]))
    return result.stdout

def sql(query):
    return run(['docker','exec','-i','supabase-db','psql','-X','-q','-At','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1'],query.encode()).decode().strip()

users_before=sql('select count(*) from auth.users')
identity_before=sql("select coalesce(jsonb_object_agg(id,bundle->>'identity_key'),'{}') from public.account_devices")
backup=home/('before-history-calls-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')+'.dump')
with backup.open('wb') as stream:
    subprocess.run(['docker','exec','supabase-db','pg_dump','-U','postgres','-d','postgres','-Fc','-n','auth','-n','public','-n','private','-n','storage'],stdout=stream,stderr=subprocess.PIPE,check=True)
print('Database backup created',flush=True)
for item in payload['migrations']:
    name=item['name']
    if not name.endswith('_call_alerts_and_encrypted_history.sql') or not name.replace('_','').replace('.','').isalnum(): raise ValueError('Migration not allowed')
    content=base64.b64decode(item['content']).replace(b'\r\n',b'\n')
    digest=hashlib.sha256(content).hexdigest()
    previous=sql("select sha256 from private.deployment_versions where version='"+name+"'")
    if previous and previous!=digest: raise RuntimeError('Installed migration changed')
    if not previous:
        sql('begin;\n'+content.decode()+"\ninsert into private.deployment_versions(version,sha256) values('"+name+"','"+digest+"'); commit;")
        print('Installed '+name,flush=True)
for item in payload['functions']:
    relative=item['path']
    if relative not in ('push-dispatch/index.ts','login-identifier/index.ts'): raise ValueError('Function not allowed')
    destination='/home/deno/functions/'+relative
    # Keep the previous function files beside the encrypted database backup.
    previous=run(['docker','exec','supabase-edge-functions','cat',destination])
    (home/(backup.stem+'-'+relative.replace('/','-'))).write_bytes(previous)
    run(['docker','exec','-i','supabase-edge-functions','sh','-c','cat > '+shlex.quote(destination)],base64.b64decode(item['content']))
(home/'push_worker.py').write_bytes(base64.b64decode(payload['worker']))
run(['docker','restart','supabase-edge-functions'])
run(['docker','restart','adoetz-push-worker'])
run(['docker','exec','supabase-kong','kong','reload'])
if sql('select count(*) from auth.users')!=users_before: raise RuntimeError('Account count changed')
if sql("select coalesce(jsonb_object_agg(id,bundle->>'identity_key'),'{}') from public.account_devices")!=identity_before: raise RuntimeError('Device identities changed')
print('Functions and push worker updated; existing users and device keys preserved',flush=True)
