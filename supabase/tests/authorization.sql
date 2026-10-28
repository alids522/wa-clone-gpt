\set ON_ERROR_STOP on
begin;
-- Provision three invited users in the actual signup trigger transaction.
insert into private.invitations(token_hash,expires_at) values
 (encode(extensions.digest('fixture-a','sha256'),'hex'),now()+interval '1 day'),
 (encode(extensions.digest('fixture-b','sha256'),'hex'),now()+interval '1 day'),
 (encode(extensions.digest('fixture-c','sha256'),'hex'),now()+interval '1 day');
insert into auth.users(id,email,raw_user_meta_data) values
 ('00000000-0000-4000-8000-000000000001','alice@example.test','{"username":"alice","invite_code":"fixture-a","role":"admin"}'),
 ('00000000-0000-4000-8000-000000000002','bob@example.test','{"username":"bob","invite_code":"fixture-b"}'),
 ('00000000-0000-4000-8000-000000000003','eve@example.test','{"username":"eve","invite_code":"fixture-c"}');
do $$ begin
 if (select role from private.accounts where id='00000000-0000-4000-8000-000000000001')<>'user' then raise exception 'User metadata elevated role'; end if;
 if exists(select 1 from auth.users where raw_user_meta_data ? 'invite_code') then raise exception 'Invite code retained'; end if;
 begin
  insert into auth.users values('00000000-0000-4000-8000-000000000004','direct@example.test','{"username":"direct"}');
  raise exception 'Public signup bypassed invite' using errcode='XX000';
 exception when raise_exception then null; end;
 begin
  insert into auth.users values('00000000-0000-4000-8000-000000000004','direct@example.test','{"username":"direct","invite_code":"fixture-a"}');
  raise exception 'Invite reused' using errcode='XX000';
 exception when raise_exception then null; end;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
select public.create_chat('00000000-0000-4000-8000-000000000002') as chat \gset
select set_config('test.chat',:'chat',true);
select public.send_message(:'chat','10000000-0000-4000-8000-000000000001','{"protocol":"signal-v1","type":3,"body":"Y2lwaGVydGV4dA=="}');
select public.send_message(:'chat','10000000-0000-4000-8000-000000000001','{"protocol":"signal-v1","type":3,"body":"Y2lwaGVydGV4dA=="}');
do $$ begin
 if (select count(*) from public.messages)<>1 then raise exception 'Retry duplicated message'; end if;
 if (select count(*) from public.profiles)<>1 then raise exception 'Raw profile enumeration allowed'; end if;
 begin
  perform public.adoetz_admin_snapshot('00000000-0000-4000-8000-000000000001','users');
  raise exception 'Admin RPC callable by user' using errcode='XX000';
 exception when insufficient_privilege then null; end;
 begin
  update private.accounts set role='admin' where id=auth.uid();
  raise exception 'Role mutable by client' using errcode='XX000';
 exception when insufficient_privilege then null; end;
 begin
  insert into public.messages(conversation_id,sender_id,client_message_id,ciphertext) select id,auth.uid(),gen_random_uuid(),'{"protocol":"signal-v1","body":"plain"}' from public.conversations;
  raise exception 'Direct message insert allowed' using errcode='XX000';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',true);
do $$ begin
 if exists(select 1 from public.messages) then raise exception 'Cross-user message read'; end if;
 if exists(select 1 from public.conversations) then raise exception 'Cross-user chat read'; end if;
end $$;
do $$ begin
 begin
  perform public.sync_messages(current_setting('test.chat')::uuid,0);
  raise exception 'Nonmember sync allowed' using errcode='XX000';
 exception when insufficient_privilege then null; end;
 begin
  perform public.send_message(current_setting('test.chat')::uuid,gen_random_uuid(),'{"protocol":"signal-v1","body":"YQ=="}');
  raise exception 'Nonmember send allowed' using errcode='XX000';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
insert into public.blocked_users(blocker_id,blocked_id) values(auth.uid(),'00000000-0000-4000-8000-000000000001');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
do $$ begin
 begin
  perform public.send_message(current_setting('test.chat')::uuid,gen_random_uuid(),'{"protocol":"signal-v1","body":"YQ=="}');
  raise exception 'Blocked send allowed' using errcode='XX000';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
update private.accounts set status='suspended' where id='00000000-0000-4000-8000-000000000001';
set local role authenticated;
do $$ begin
 if exists(select 1 from public.messages) then raise exception 'Suspended JWT still reads messages'; end if;
 begin
  perform public.list_chats();
  raise exception 'Suspended JWT still lists chats' using errcode='XX000';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
rollback;
