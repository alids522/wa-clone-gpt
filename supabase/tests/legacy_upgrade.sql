\set ON_ERROR_STOP on
begin;
insert into private.invitations(token_hash,expires_at) values
 (encode(extensions.digest('legacy-a','sha256'),'hex'),now()+interval '1 day'),
 (encode(extensions.digest('legacy-b','sha256'),'hex'),now()+interval '1 day');
insert into auth.users(id,email,raw_user_meta_data) values
 ('40000000-0000-4000-8000-000000000001','a@legacy.test','{"username":"legacy_a","invite_code":"legacy-a"}'),
 ('40000000-0000-4000-8000-000000000002','b@legacy.test','{"username":"legacy_b","invite_code":"legacy-b"}');
select set_config('test.bundle',jsonb_build_object('identity_key',repeat('A',44),'signed_prekey',repeat('B',44),'signature',repeat('C',88),'signed_prekey_id',1,'registration_id',10,'prekeys',jsonb_build_array(jsonb_build_object('id',1,'key',repeat('D',44))))::text,true);
set local role authenticated;
select set_config('request.jwt.claim.sub','40000000-0000-4000-8000-000000000001',true);
-- Simulate an old APK registering after the multi-device migration.
select public.register_device(current_setting('test.bundle')::jsonb);
select public.create_chat('40000000-0000-4000-8000-000000000002') as chat \gset
select set_config('test.chat',:'chat',true);
reset role;
delete from private.prekeys where user_id='40000000-0000-4000-8000-000000000001' and key_id=1;
set local role authenticated;
do $$ begin
 if public.register_device_v2('50000000-0000-4000-8000-000000000001',current_setting('test.bundle')::jsonb,'Upgraded phone')<>'40000000-0000-4000-8000-000000000001'::uuid then raise exception 'Upgrade changed original Signal address'; end if;
end $$;
select set_config('request.jwt.claim.sub','40000000-0000-4000-8000-000000000002',true);
select public.register_device(current_setting('test.bundle')::jsonb);
select public.register_device_v2('50000000-0000-4000-8000-000000000002',current_setting('test.bundle')::jsonb,'Peer');
select set_config('request.jwt.claim.sub','40000000-0000-4000-8000-000000000001',true);
select public.send_message(:'chat','60000000-0000-4000-8000-000000000001','{"protocol":"signal-v1","body":"YWJj"}');
select public.send_message(:'chat','60000000-0000-4000-8000-000000000001','{"protocol":"signal-v1","body":"YWJj"}');
reset role;
do $$ begin
 if exists(select 1 from private.device_prekeys where device_id='40000000-0000-4000-8000-000000000001' and key_id=1) then raise exception 'Consumed legacy prekey restored'; end if;
 if (select count(*) from private.push_jobs where device_id='40000000-0000-4000-8000-000000000002')<>1 then raise exception 'Legacy retry push missing or duplicated'; end if;
end $$;
rollback;
