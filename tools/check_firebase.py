"""Server-side FCM HTTP v1 dry run. Never sends a notification or prints a token."""
import base64
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

os.umask(0o077)
environment=dict(x.split('=',1) for x in json.loads(subprocess.check_output(['docker','inspect','supabase-edge-functions','--format','{{json .Config.Env}}'],text=True)))
account=json.loads(base64.b64decode(environment['FIREBASE_SERVICE_ACCOUNT_B64']))
def encode(value):return base64.urlsafe_b64encode(value).rstrip(b'=')
stamp=int(time.time())
header=encode(json.dumps({'alg':'RS256','typ':'JWT'},separators=(',',':')).encode())
claim=encode(json.dumps({'iss':account['client_email'],'scope':'https://www.googleapis.com/auth/firebase.messaging','aud':'https://oauth2.googleapis.com/token','iat':stamp,'exp':stamp+3600},separators=(',',':')).encode())
unsigned=header+b'.'+claim
with tempfile.TemporaryDirectory(prefix='adoetz-fcm-') as directory:
    key=Path(directory)/'key.pem';key.write_text(account['private_key'])
    signature=subprocess.run(['openssl','dgst','-sha256','-sign',str(key)],input=unsigned,capture_output=True,check=True).stdout
assertion=unsigned+b'.'+encode(signature)
request=urllib.request.Request('https://oauth2.googleapis.com/token',data=urllib.parse.urlencode({'grant_type':'urn:ietf:params:oauth:grant-type:jwt-bearer','assertion':assertion.decode()}).encode(),headers={'Content-Type':'application/x-www-form-urlencoded'})
with urllib.request.urlopen(request,timeout=15) as response:access=json.load(response)['access_token']
token=subprocess.run(['docker','exec','supabase-db','psql','-X','-q','-At','-U','postgres','-d','postgres','-c','select token from private.device_push_tokens order by updated_at desc limit 1'],capture_output=True,text=True,check=True).stdout.strip()
has_token=bool(token)
payload={'validate_only':True,'message':{'token':token or 'not-a-real-fcm-registration-token','data':{'kind':'diagnostic'}}}
request=urllib.request.Request('https://fcm.googleapis.com/v1/projects/'+account['project_id']+'/messages:send',data=json.dumps(payload).encode(),headers={'Authorization':'Bearer '+access,'Content-Type':'application/json'})
try:
    with urllib.request.urlopen(request,timeout=15) as response:
        print('FCM dry-run='+str(response.status)+' registered_token='+str(has_token))
except urllib.error.HTTPError as error:
    result=json.load(error)
    print('FCM dry-run='+str(error.code)+' error='+str(result.get('error',{}).get('status'))+' registered_token='+str(has_token))
    if error.code not in (400,404):raise SystemExit(1)
