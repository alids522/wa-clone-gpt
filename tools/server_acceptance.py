"""Operator-only live acceptance fixtures. Never uses an existing user's password.

Modes: prepare, finish, cleanup. The private fixture JSON stays outside the repo;
temporary test accounts are removed, while their security audit records remain.
"""
import base64
import hashlib
import hmac
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid

os.umask(0o077)
directory=Path.home()/'.cache/adoetz-deploy'
fixture_path=directory/'acceptance-fixture.json'
environment=dict(x.split('=',1) for x in json.loads(subprocess.check_output(['docker','inspect','supabase-edge-functions','--format','{{json .Config.Env}}'],text=True)))
role_key=environment['SUPABASE_SERVICE_ROLE_KEY']
anon_key=environment['SUPABASE_ANON_KEY']

def sql(query):
    result=subprocess.run(['docker','exec','-i','supabase-db','psql','-X','-q','-At','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1'],input=query,capture_output=True,text=True)
    if result.returncode:raise RuntimeError('Acceptance SQL failed')
    return result.stdout.strip()

def api(path,data=None,token=None,method='POST',expected=(200,201)):
    token=token or anon_key
    headers={'apikey':role_key if token==role_key else anon_key,'Authorization':'Bearer '+token,'Content-Type':'application/json'}
    request=urllib.request.Request('http://127.0.0.1:8000/'+path,data=None if data is None else json.dumps(data).encode(),headers=headers,method=method)
    try:
        with urllib.request.urlopen(request,timeout=25) as response:
            status=response.status;raw=response.read()
    except urllib.error.HTTPError as error:
        status=error.code;raw=error.read()
    if status not in expected:raise RuntimeError('Acceptance request failed: '+path.split('?')[0]+' status='+str(status))
    return json.loads(raw) if raw else {}

def signin(user,password=None):
    return api('auth/v1/token?grant_type=password',{'email':user['email'],'password':password or user['password']})

def admin(fixture,token,action,target=None,**extra):
    return api('functions/v1/admin',{'action':action,'target':target,'reason':'Automated acceptance fixture','password':fixture['users'][0]['password'],'request_id':str(uuid.uuid4()),**extra},token)

def prepare():
    if fixture_path.exists():raise RuntimeError('Clean up the previous acceptance fixture first')
    run=secrets.token_hex(4)
    fixture={'url':'https://supabase.adoetz52.my.id','key':anon_key,'run':run,'users':[]}
    fixture_path.write_text(json.dumps(fixture))
    for suffix in ['a','b','e']:
        code=secrets.token_hex(24)
        sql("insert into private.invitations(token_hash,expires_at) values('"+hashlib.sha256(code.encode()).hexdigest()+"',now()+interval '1 hour')")
        username='qa_'+run+suffix
        user={'email':username+'@example.test','username':username,'password':secrets.token_urlsafe(24)}
        result=api('auth/v1/admin/users',{'email':user['email'],'password':user['password'],'email_confirm':True,'user_metadata':{'username':username,'invite_code':code,'role':'admin'}},role_key)
        user['id']=result['id'];fixture['users'].append(user);fixture_path.write_text(json.dumps(fixture))
        if sql("select role from private.accounts where id='"+user['id']+"'")!='user':raise RuntimeError('User metadata elevated a fixture role')
        sql("update public.profiles set discoverable=false where id='"+user['id']+"'")
    sql("update private.accounts set role='admin' where id='"+fixture['users'][0]['id']+"'")
    turn=json.loads((directory/'turn.json').read_text())
    username=str(int(time.time())+600)+':acceptance'
    fixture['turn']={'server':'129.225.32.137','username':username,'credential':base64.b64encode(hmac.new(turn['secret'].encode(),username.encode(),hashlib.sha1).digest()).decode()}
    fixture_path.write_text(json.dumps(fixture))
    print('Created three isolated acceptance accounts; no existing account was changed')

def finish():
    fixture=json.loads(fixture_path.read_text());a,b,e=fixture['users']
    a_session=signin(a);token=a_session['access_token']
    old_b=signin(b)['access_token']
    invite=admin(fixture,token,'create-invite')['invite_code']
    digest=hashlib.sha256(invite.encode()).hexdigest()
    invitation=sql("select id from private.invitations where token_hash='"+digest+"'")
    admin(fixture,token,'revoke-invite',invitation)
    temporary=secrets.token_urlsafe(24)
    admin(fixture,token,'force-reset',b['id'],temporary_password=temporary)
    b['password']=temporary;fixture_path.write_text(json.dumps(fixture))
    if api('rest/v1/rpc/my_account',{},old_b)['status']!='session_revoked':raise RuntimeError('Reset did not invalidate the old access JWT')
    temporary_session=signin(b)['access_token']
    if api('rest/v1/rpc/my_account',{},temporary_session)['status']!='reset_required':raise RuntimeError('Temporary password skipped mandatory replacement')
    username_login=api('functions/v1/login-identifier',{'identifier':b['username'],'password':temporary})
    if not username_login.get('refresh_token'):raise RuntimeError('Username login failed')
    new_password=secrets.token_urlsafe(24)
    api('functions/v1/account-password',{'new_password':new_password},temporary_session)
    b['password']=new_password;fixture_path.write_text(json.dumps(fixture))
    if api('rest/v1/rpc/my_account',{},temporary_session)['status']!='active':raise RuntimeError('Password replacement did not reactivate the account')
    signin(b)
    admin(fixture,token,'promote',b['id'])
    if api('rest/v1/rpc/my_account',{},temporary_session)['role']!='admin':raise RuntimeError('Role update did not use live database authorization')
    admin(fixture,token,'demote',b['id'])
    api('functions/v1/admin',{'action':'list-users'},temporary_session,expected=(403,))
    admin(fixture,token,'list-invites');admin(fixture,token,'audit');admin(fixture,token,'list-reports')
    admin(fixture,token,'soft-delete',b['id'])
    if api('rest/v1/rpc/my_account',{},temporary_session)['status']!='session_revoked':raise RuntimeError('Deletion left the old session authorized')
    print('Verified real Auth: invite revocation, username login, forced reset, password replacement, role guards and revoked JWTs')

def cleanup():
    fixture=json.loads(fixture_path.read_text());users=fixture['users']
    for user in users:
        uuid.UUID(user['id'])
        if not user['username'].startswith('qa_'+fixture['run']):raise RuntimeError('Refusing to clean a nonfixture account')
    ids=','.join("'"+u['id']+"'" for u in users)
    if not ids:return
    if int(sql("select count(*) from private.accounts where role='admin' and status='active' and id not in("+ids+")"))<1:raise RuntimeError('Preserve the last administrator')
    objects=json.loads(sql("select coalesce(jsonb_agg(jsonb_build_object('bucket',bucket_id,'name',name)),'[]') from storage.objects where (bucket_id='chat-media' and split_part(name,'/',2) in("+ids+")) or(bucket_id='avatars' and split_part(name,'/',1) in("+ids+"))"))
    for bucket in {o['bucket'] for o in objects}:
        api('storage/v1/object/'+bucket,{'prefixes':[o['name'] for o in objects if o['bucket']==bucket]},role_key,method='DELETE')
    sql("begin; delete from private.reports where reporter_id in("+ids+") or target_id in("+ids+"); delete from public.calls where conversation_id in(select id from public.conversations where member_a in("+ids+") or member_b in("+ids+")); delete from public.messages where conversation_id in(select id from public.conversations where member_a in("+ids+") or member_b in("+ids+")); delete from public.conversations where member_a in("+ids+") or member_b in("+ids+"); delete from private.invitations where used_by in("+ids+") or created_by in("+ids+"); commit;")
    # This server also has a legacy profile signup trigger. Remove only rows
    # that trigger created for these exact temporary fixture IDs.
    if sql("select to_regclass('public.wa_profiles')"):
        sql('delete from public.wa_profiles where id in('+ids+')')
    for user in users:api('auth/v1/admin/users/'+user['id'],token=role_key,method='DELETE')
    fixture_path.unlink()
    print('Removed all acceptance accounts and test files; security audit records retained')

{'prepare':prepare,'finish':finish,'cleanup':cleanup}[sys.argv[1]]()
