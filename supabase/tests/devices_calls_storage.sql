\set ON_ERROR_STOP on
begin;
set local role service_role;
do $$ begin if public.adoetz_claim_push_jobs()<>'[]'::jsonb then raise exception 'Nonempty initial queue'; end if; end $$;
reset role;
insert into private.invitations(token_hash,expires_at) values
 (encode(extensions.digest('device-a','sha256'),'hex'),now()+interval '1 day'),
 (encode(extensions.digest('device-b','sha256'),'hex'),now()+interval '1 day'),
 (encode(extensions.digest('device-e','sha256'),'hex'),now()+interval '1 day');
insert into auth.users(id,email,raw_user_meta_data) values
 ('00000000-0000-4000-8000-000000000001','a@device.test','{"username":"alice","invite_code":"device-a"}'),
 ('00000000-0000-4000-8000-000000000002','b@device.test','{"username":"bob","invite_code":"device-b"}'),
 ('00000000-0000-4000-8000-000000000003','e@device.test','{"username":"eve","invite_code":"device-e"}');
insert into auth.sessions values
 ('90000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001'),
 ('90000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000001'),
 ('90000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-000000000002'),
 ('90000000-0000-4000-8000-000000000004','00000000-0000-4000-8000-000000000003');
select set_config('test.bundle',jsonb_build_object('identity_key',repeat('A',44),'signed_prekey',repeat('B',44),'signature',repeat('C',88),'signed_prekey_id',1,'registration_id',10,'prekeys',jsonb_build_array(jsonb_build_object('id',1,'key',repeat('D',44))))::text,true);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"session_id":"90000000-0000-4000-8000-000000000001"}',true);
select public.register_device_v2('10000000-0000-4000-8000-000000000001',current_setting('test.bundle')::jsonb,'Phone');
select public.create_chat('00000000-0000-4000-8000-000000000002') as chat \gset
select set_config('test.chat',:'chat',true);
select set_config('request.jwt.claims','{"session_id":"90000000-0000-4000-8000-000000000002"}',true);
select public.register_device_v2('10000000-0000-4000-8000-000000000002',jsonb_set(current_setting('test.bundle')::jsonb,'{identity_key}',to_jsonb(repeat('E',44))),'Tablet');
do $$ begin
 if jsonb_array_length(public.device_settings('10000000-0000-4000-8000-000000000002','list'))<>2 then raise exception 'Second login replaced first device'; end if;
 begin
  perform public.sync_device_messages(current_setting('test.chat')::uuid,'10000000-0000-4000-8000-000000000001',0);
  raise exception 'Session used another device identity' using errcode='XX000';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"session_id":"90000000-0000-4000-8000-000000000003"}',true);
select public.register_device_v2('10000000-0000-4000-8000-000000000003',current_setting('test.bundle')::jsonb,'Peer');
select public.device_settings('10000000-0000-4000-8000-000000000003','push','test-push-token-peer');
select public.device_prekey_bundle(:'chat','10000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"session_id":"90000000-0000-4000-8000-000000000001"}',true);
select public.register_device_v2('10000000-0000-4000-8000-000000000001',current_setting('test.bundle')::jsonb,'Phone');
select set_config('test.envelope',jsonb_build_object('protocol','signal-devices-v2','sender_device','10000000-0000-4000-8000-000000000001','notify',true,'envelopes',jsonb_build_object('10000000-0000-4000-8000-000000000002',jsonb_build_object('protocol','signal-v1','body','YWJj'),'10000000-0000-4000-8000-000000000003',jsonb_build_object('protocol','signal-v1','body','ZGVm')))::text,true);
select public.send_device_message(:'chat','20000000-0000-4000-8000-000000000001',current_setting('test.envelope')::jsonb);
select public.send_device_message(:'chat','20000000-0000-4000-8000-000000000001',current_setting('test.envelope')::jsonb);
select public.call_action('30000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','start',:'chat',true);
do $$ begin
 if not private.attachment_access(current_setting('test.chat')||'/00000000-0000-4000-8000-000000000001/blob',true) then raise exception 'Own attachment denied'; end if;
 if private.attachment_access(current_setting('test.chat')||'/00000000-0000-4000-8000-000000000002/blob',true) then raise exception 'Other user attachment path writable'; end if;
 begin
  perform public.call_action('30000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001','start',current_setting('test.chat')::uuid,false);
  raise exception 'Concurrent call bypassed busy check' using errcode='XX000';
 exception when raise_exception then null; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"session_id":"90000000-0000-4000-8000-000000000003"}',true);
select public.call_action('30000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000003','accept');
do $$ begin
 if jsonb_array_length(public.sync_device_messages(current_setting('test.chat')::uuid,'10000000-0000-4000-8000-000000000003',0))<>1 then raise exception 'Fanout/dedup failed'; end if;
 begin
  perform public.device_settings('10000000-0000-4000-8000-000000000001','revoke');
  raise exception 'Revoked another account device' using errcode='XX000';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claims','{"session_id":"90000000-0000-4000-8000-000000000004"}',true);
do $$ begin
 if private.attachment_access(current_setting('test.chat')||'/00000000-0000-4000-8000-000000000001/blob',false) then raise exception 'Outsider read attachment'; end if;
 begin
  perform public.call_action('30000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000003','accept');
  raise exception 'Outsider answered call' using errcode='XX000';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"session_id":"90000000-0000-4000-8000-000000000001"}',true);
select public.device_settings('10000000-0000-4000-8000-000000000002','revoke');
select set_config('request.jwt.claims','{"session_id":"90000000-0000-4000-8000-000000000002"}',true);
do $$ begin
 if public.my_account()->>'status'<>'session_revoked' then raise exception 'Revoked access JWT remained active'; end if;
end $$;
reset role;
set local role service_role;
do $$ begin if jsonb_array_length(public.adoetz_claim_push_jobs())<>2 then raise exception 'Durable push queue did not claim eligible device jobs'; end if; end $$;
reset role;
do $$ begin
 if exists(select 1 from private.device_prekeys where device_id='10000000-0000-4000-8000-000000000001' and key_id=1) then raise exception 'Login resurrected consumed prekey'; end if;
 if (select count(*) from private.push_jobs where kind='message')<>2 then raise exception 'Push did not fan out'; end if;
end $$;
-- Backup RPCs expose only the current account's encrypted archives.
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"session_id":"90000000-0000-4000-8000-000000000001"}',true);
do $$ declare result jsonb; envelope jsonb:=jsonb_build_object('algorithm','pbkdf2-sha256-aes256gcm-v1',
 'key_id','50000000-0000-4000-8000-000000000001','salt',repeat('A',24),'iterations',600000,
 'wrapped',jsonb_build_object('nonce',repeat('B',16),'mac',repeat('C',24),'ciphertext',repeat('D',44)));
begin
 result:=public.history_backup('10000000-0000-4000-8000-000000000001','key',envelope);
 if result->'key'->>'key_id'<>envelope->>'key_id' then raise exception 'Key creation failed'; end if;
 perform public.history_backup('10000000-0000-4000-8000-000000000001','save',jsonb_build_object('key_id',envelope->>'key_id','ciphertext',repeat('A',64),'source_revision',2));
 perform public.history_backup('10000000-0000-4000-8000-000000000001','save',jsonb_build_object('key_id',envelope->>'key_id','ciphertext',repeat('B',64),'source_revision',1));
 result:=public.history_backup('10000000-0000-4000-8000-000000000001','get',null);
 if result->'archives'->0->>'ciphertext'<>repeat('A',64) then raise exception 'Stale background archive replaced newer history'; end if;
 begin
  perform public.history_backup('10000000-0000-4000-8000-000000000001','rekey',envelope);
  raise exception 'Missing CAS revision accepted' using errcode='XX000';
 exception when serialization_failure then null; end;
 begin
  perform public.history_backup('10000000-0000-4000-8000-000000000001','key','{}');
  raise exception 'Malformed key accepted' using errcode='XX000';
 exception when raise_exception then null; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"session_id":"90000000-0000-4000-8000-000000000003"}',true);
do $$ declare result jsonb; begin
 result:=public.history_backup('10000000-0000-4000-8000-000000000003','get',null);
 if result->'key'<>'null'::jsonb or jsonb_array_length(result->'archives')<>0 then raise exception 'Another account archive leaked'; end if;
 begin
  perform public.history_backup('10000000-0000-4000-8000-000000000001','get',null);
  raise exception 'Another account device accepted' using errcode='XX000';
 exception when insufficient_privilege then null; end;
 begin
  perform 1 from private.history_keys;
  raise exception 'Private backup keys directly readable' using errcode='XX000';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
-- The worker expires calls without either application running and retains logs.
update public.calls set status='ringing',callee_device=null,expires_at=now()-interval '1 second'
 where id='30000000-0000-4000-8000-000000000001';
set local role service_role;
select public.adoetz_claim_push_jobs();
reset role;
do $$ begin
 if (select status from public.calls where id='30000000-0000-4000-8000-000000000001')<>'missed' then raise exception 'Closed-app call log not expired'; end if;
 if (select count(*) from private.push_jobs where kind='call_end')<>2 then raise exception 'Call-end notifications did not fan out'; end if;
end $$;
rollback;
