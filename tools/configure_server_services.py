"""Self-hosted operator helper: persist private worker env and media size limit.

Run on the server after server_upgrade.py. Secrets stay on that server. Only the
existing functions and storage Compose services are recreated.
"""
import base64
import datetime
import json
from pathlib import Path
import subprocess

def run(args, data=None):
    result = subprocess.run(args, input=data, capture_output=True)
    if result.returncode:
        raise RuntimeError('Server configuration operation failed: ' + ' '.join(args[:3]))
    return result.stdout

info=json.loads(run(['docker','inspect','supabase-edge-functions']))[0]
labels=info['Config']['Labels']
root=labels['com.docker.compose.project.working_dir']
files=labels['com.docker.compose.project.config_files'].split(',')
if root!='/root/supabase-project' or files!=[root+'/docker-compose.yml']:
    raise RuntimeError('Review the changed Compose location before configuring it')
firebase=run(['docker','exec','supabase-edge-functions','cat','/home/deno/functions/_secrets/firebase-service-account.json'])
turn=(Path.home()/'.cache/adoetz-deploy/turn.json').read_bytes()
values={'ADOETZ_FIREBASE_SERVICE_ACCOUNT_B64':base64.b64encode(firebase).decode(),'ADOETZ_TURN_CONFIG_B64':base64.b64encode(turn).decode()}
script=r'''
import datetime,json,re,shutil,sys
from pathlib import Path
values=json.load(sys.stdin)
root=Path('/root/supabase-project')
compose=root/'docker-compose.yml'
envfile=root/'.env'
lines=compose.read_text().splitlines()
start=next(i for i,s in enumerate(lines) if re.fullmatch(r'  functions:\s*',s))
end=next((i for i in range(start+1,len(lines)) if re.match(r'  [a-zA-Z0-9_-]+:',lines[i])),len(lines))
environment=next(i for i in range(start+1,end) if re.fullmatch(r'    environment:\s*',lines[i]))
for name,source in [('FIREBASE_SERVICE_ACCOUNT_B64','ADOETZ_FIREBASE_SERVICE_ACCOUNT_B64'),('ADOETZ_TURN_CONFIG_B64','ADOETZ_TURN_CONFIG_B64')]:
    existing=next((i for i in range(environment+1,end) if re.match(r'      '+name+r':',lines[i])),None)
    replacement='      '+name+': ${'+source+'}'
    if existing is None: lines.insert(environment+1,replacement);end+=1
    else: lines[existing]=replacement
found=False
for i,line in enumerate(lines):
    if re.match(r'\s+FILE_SIZE_LIMIT:',line):
        lines[i]=re.sub(r'(FILE_SIZE_LIMIT:\s*).*',r'\g<1>110000000',line);found=True
if not found: raise RuntimeError('Storage limit configuration not found')
env=envfile.read_text()
for name,value in values.items():
    if not re.fullmatch(r'[A-Za-z0-9+/=]+',value):raise ValueError('Invalid secret encoding')
    pattern=r'(?m)^'+name+r'=.*$'
    if re.search(pattern,env):env=re.sub(pattern,name+'='+value,env)
    else:env=env.rstrip()+'\n'+name+'='+value+'\n'
stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
for path in [compose,envfile]:shutil.copy2(path,path.with_name(path.name+'.before-adoetz-'+stamp))
compose.write_text('\n'.join(lines)+'\n');envfile.write_text(env)
envfile.chmod(0o600)
print('Private environment and 110 MB ciphertext upload limit configured')
'''
run(['docker','pull','python:3.12-slim'])
print(run(['docker','run','--rm','-i','--network','none','-v',root+':'+root,'python:3.12-slim','python','-c',script],json.dumps(values).encode()).decode().strip())
run(['docker','pull','docker:27.5-cli'])
run(['docker','run','--rm','-v','/var/run/docker.sock:/var/run/docker.sock','-v',root+':'+root,'-w',root,'docker:27.5-cli','compose','-p',labels['com.docker.compose.project'],'-f',files[0],'up','-d','--no-deps','functions','storage'])
print('Recreated only Supabase functions and storage services')
