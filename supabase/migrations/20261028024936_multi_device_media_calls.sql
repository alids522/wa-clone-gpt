-- Additive upgrade: existing accounts, identities, prekeys and ciphertext remain.
create table public.account_devices (
 id uuid primary key, user_id uuid not null references auth.users on delete cascade,
 bundle jsonb not null, label text not null default 'Android',
 created_at timestamptz not null default now(), last_seen timestamptz not null default now(),
 revoked_at timestamptz, prekey_highwater int not null default 50
);
create unique index account_devices_identity on public.account_devices(user_id,(bundle->>'identity_key'));
create index account_devices_owner on public.account_devices(user_id) where revoked_at is null;
create table private.device_prekeys (
 device_id uuid not null references public.account_devices on delete cascade,
 key_id int not null, public_key text not null, primary key(device_id,key_id)
);
create table private.device_sessions (
 session_id uuid primary key references auth.sessions on delete cascade,
 device_id uuid not null references public.account_devices on delete cascade
);
create index device_sessions_device on private.device_sessions(device_id);
alter table private.device_sessions enable row level security;
revoke all on private.device_sessions from public,anon,authenticated;
-- Legacy device IDs equal their account IDs, preserving Signal addresses.
insert into public.account_devices(id,user_id,bundle,created_at,label)
 select user_id,user_id,bundle,created_at,'Android (perangkat awal)' from public.devices;
insert into private.device_prekeys select user_id,key_id,public_key from private.prekeys;
create table private.device_push_tokens (
 device_id uuid primary key references public.account_devices on delete cascade,
 token text not null unique, updated_at timestamptz not null default now()
);
insert into private.device_push_tokens(device_id,token,updated_at)
 select user_id,token,updated_at from private.push_tokens where user_id in (select id from public.account_devices);
create table private.push_jobs (
 id bigint generated always as identity primary key, device_id uuid not null references public.account_devices on delete cascade,
 event_id uuid not null, kind text not null check(kind in ('message','call')),
 created_at timestamptz not null default now(), available_at timestamptz not null default now(),
 attempts int not null default 0, unique(device_id,event_id,kind)
);
create index push_jobs_due on private.push_jobs(available_at);
alter table public.account_devices enable row level security;
alter table private.device_prekeys enable row level security;
alter table private.device_push_tokens enable row level security;
alter table private.push_jobs enable row level security;
revoke all on public.account_devices,private.device_prekeys,private.device_push_tokens,private.push_jobs from anon,authenticated;

create function private.current_session() returns uuid language sql stable security invoker set search_path='' as $$
 select (nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'session_id')::uuid
$$;
revoke all on function private.current_session() from public,anon;
grant execute on function private.current_session() to authenticated,service_role;
create or replace function private.is_active(uid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.accounts where id=uid and status='active')
 and (uid is distinct from auth.uid() or private.current_session() is null or exists(select 1 from auth.sessions where id=private.current_session() and user_id=uid))
$$;
create or replace function private.my_account() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise insufficient_privilege; end if;
 if private.current_session() is not null and not exists(select 1 from auth.sessions where id=private.current_session() and user_id=auth.uid()) then return jsonb_build_object('role','user','status','session_revoked'); end if;
 return (select jsonb_build_object('role',role,'status',status) from private.accounts where id=auth.uid());
end $$;
create function private.owns_device(device uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.is_active(auth.uid()) and exists(select 1 from public.account_devices where id=device and user_id=auth.uid() and revoked_at is null)
 and (private.current_session() is null or exists(select 1 from private.device_sessions where session_id=private.current_session() and device_id=device))
$$;

create function private.register_device_v2(requested_id uuid,bundle jsonb,device_label text) returns uuid language plpgsql security definer set search_path='' as $$
declare selected_id uuid; existing jsonb; k jsonb; highwater int; next_highwater int;
begin
 if not private.is_active(auth.uid()) then raise insufficient_privilege; end if;
 if requested_id is null or bundle is null or length(bundle->>'identity_key') is distinct from 44
 or length(bundle->>'signed_prekey') is distinct from 44 or length(bundle->>'signature') is distinct from 88
 or coalesce((bundle->>'registration_id')::int,0) not between 1 and 16380
 or jsonb_typeof(bundle->'prekeys') is distinct from 'array' or jsonb_array_length(bundle->'prekeys')>100
 then raise exception 'Invalid device bundle'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
 select id,d.bundle into selected_id,existing from public.account_devices d
 where user_id=auth.uid() and d.bundle->>'identity_key'=register_device_v2.bundle->>'identity_key' and revoked_at is null;
 if selected_id is null then
  if (select count(*) from public.account_devices where user_id=auth.uid() and revoked_at is null)>=10 then raise exception 'Device limit reached'; end if;
  selected_id:=requested_id;
  insert into public.account_devices(id,user_id,bundle,label) values(selected_id,auth.uid(),bundle-'prekeys',left(coalesce(device_label,'Android'),60));
 end if;
 select case when existing is null then 0 else prekey_highwater end into highwater from public.account_devices where id=selected_id;
 next_highwater:=highwater;
 -- Immutable identity; only higher, previously unseen one-time key IDs replenish.
 for k in select * from jsonb_array_elements(bundle->'prekeys') loop
  if length(k->>'key') is distinct from 44 or (k->>'id')::int<1 then raise exception 'Invalid prekey'; end if;
  if (k->>'id')::int>highwater then
   insert into private.device_prekeys values(selected_id,(k->>'id')::int,k->>'key');
   next_highwater:=greatest(next_highwater,(k->>'id')::int);
  end if;
 end loop;
 update public.account_devices set last_seen=now(),prekey_highwater=next_highwater,bundle=register_device_v2.bundle-'prekeys' where id=selected_id;
 if selected_id=auth.uid() then update public.devices set bundle=register_device_v2.bundle-'prekeys' where user_id=auth.uid(); end if;
 if private.current_session() is not null then
  insert into private.device_sessions(session_id,device_id) values(private.current_session(),selected_id) on conflict(session_id) do update set device_id=excluded.device_id;
 end if;
 return selected_id;
end $$;
create function public.register_device_v2(requested_id uuid,bundle jsonb,device_label text default 'Android') returns uuid language sql security invoker set search_path='' as $$ select private.register_device_v2(requested_id,bundle,device_label) $$;

create function private.chat_devices(chat uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.can_send_chat(chat) then raise insufficient_privilege; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'user_id',d.user_id,'identity_key',d.bundle->>'identity_key')) from public.account_devices d join public.conversations c on c.id=chat and d.user_id in(c.member_a,c.member_b) where d.revoked_at is null),'[]'::jsonb);
end $$;
create function public.chat_devices(chat uuid) returns jsonb language sql stable security invoker set search_path='' as $$ select private.chat_devices(chat) $$;

create function private.device_prekey_bundle(chat uuid,device uuid,consume boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; selected_key private.device_prekeys;
begin
 if not private.can_send_chat(chat) or not exists(select 1 from public.account_devices d join public.conversations c on c.id=chat and d.user_id in(c.member_a,c.member_b) where d.id=device and d.revoked_at is null) then raise insufficient_privilege; end if;
 select bundle into result from public.account_devices where id=device;
 if consume then
  if not private.user_budget('prekeys',60) then raise exception 'Rate limited' using errcode='53300'; end if;
  select * into selected_key from private.device_prekeys where device_id=device order by key_id limit 1 for update skip locked;
  if selected_key.key_id is not null then
   delete from private.device_prekeys where device_id=device and key_id=selected_key.key_id;
   -- Also consume the legacy directory entry while old clients are being upgraded.
   delete from private.prekeys where user_id=device and key_id=selected_key.key_id;
   result:=result||jsonb_build_object('prekey',jsonb_build_object('id',selected_key.key_id,'key',selected_key.public_key));
  end if;
 end if;
 return result;
end $$;
create function public.device_prekey_bundle(chat uuid,device uuid,consume boolean default true) returns jsonb language sql security invoker set search_path='' as $$ select private.device_prekey_bundle(chat,device,consume) $$;

-- Permit an authenticated, bounded per-device fanout; old rows stay readable.
alter table public.messages drop constraint messages_ciphertext_check;
alter table public.messages add constraint messages_ciphertext_check check (
 (ciphertext->>'protocol'='signal-v1' and length(ciphertext->>'body') between 1 and 100000)
 or (ciphertext->>'protocol'='signal-devices-v2' and jsonb_typeof(ciphertext->'envelopes')='object' and octet_length(ciphertext::text)<2000000)
);
create function private.send_device_message(chat uuid,client_id uuid,envelope jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare result public.messages; source uuid; target record; c public.conversations; peer uuid;
begin
 if not private.can_send_chat(chat) then raise insufficient_privilege; end if;
 source:=(envelope->>'sender_device')::uuid;
 if not private.owns_device(source) or envelope->>'protocol' is distinct from 'signal-devices-v2' or jsonb_typeof(envelope->'envelopes') is distinct from 'object' then raise insufficient_privilege; end if;
 select * into c from public.conversations where id=chat for update;
 -- Idempotent retries remain valid even if devices were added/revoked afterwards.
 select * into result from public.messages where sender_id=auth.uid() and client_message_id=client_id;
 if result.id is not null then
  if result.conversation_id<>chat or result.ciphertext<>envelope then raise exception 'Idempotency conflict'; end if;
  return jsonb_build_object('id',result.id,'sequence',result.sequence,'created_at',result.created_at);
 end if;
 if (select count(*) from jsonb_object_keys(envelope->'envelopes'))>19 then raise exception 'Fanout limit'; end if;
 if not private.user_budget('messages',300) then raise exception 'Rate limited' using errcode='53300'; end if;
 for target in select key,value from jsonb_each(envelope->'envelopes') loop
  if target.key=source::text or not exists(select 1 from public.account_devices where id=target.key::uuid and user_id in(c.member_a,c.member_b) and revoked_at is null)
  or target.value->>'protocol' is distinct from 'signal-v1' or coalesce(length(target.value->>'body'),0) not between 1 and 100000 then raise insufficient_privilege; end if;
 end loop;
 peer:=case when c.member_a=auth.uid() then c.member_b else c.member_a end;
 if not exists(select 1 from public.account_devices d where d.user_id=peer and d.revoked_at is null and envelope->'envelopes' ? d.id::text) then raise exception 'No receiving device'; end if;
 -- The client must include every active device it observed. A concurrent addition
 -- is included by the next message; it can never replace an existing identity.
 insert into public.messages(conversation_id,sender_id,client_message_id,ciphertext) values(chat,auth.uid(),client_id,envelope) returning * into result;
 insert into private.push_jobs(device_id,event_id,kind)
 select d.id,result.id,'message' from public.account_devices d where d.revoked_at is null and envelope->'envelopes' ? d.id::text and envelope->>'notify'='true';
 return jsonb_build_object('id',result.id,'sequence',result.sequence,'created_at',result.created_at);
end $$;
create function public.send_device_message(chat uuid,client_id uuid,envelope jsonb) returns jsonb language sql security invoker set search_path='' as $$ select private.send_device_message(chat,client_id,envelope) $$;

create function private.sync_device_messages(chat uuid,device uuid,after_sequence bigint) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.can_read_chat(chat) or not private.owns_device(device) then raise insufficient_privilege; end if;
 return coalesce((select jsonb_agg(to_jsonb(m) order by m.sequence) from (
 select * from public.messages where conversation_id=chat and sequence>after_sequence and (
 (ciphertext->>'protocol'='signal-devices-v2' and (ciphertext->'envelopes' ? device::text or ciphertext->>'sender_device'=device::text))
 or (ciphertext->>'protocol'='signal-v1' and device=auth.uid())) order by sequence limit 50) m),'[]'::jsonb);
end $$;
create function public.sync_device_messages(chat uuid,device uuid,after_sequence bigint) returns jsonb language sql stable security invoker set search_path='' as $$ select private.sync_device_messages(chat,device,after_sequence) $$;
-- Keep older installations able to read their original ciphertext while all
-- participants install the multi-device APK. They cannot decrypt v2 fanouts.
create or replace function private.sync_messages(chat uuid,after_sequence bigint) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.can_read_chat(chat) then raise insufficient_privilege; end if;
 return coalesce((select jsonb_agg(to_jsonb(m) order by m.sequence) from(select * from public.messages where conversation_id=chat and sequence>after_sequence and ciphertext->>'protocol'='signal-v1' order by sequence limit 50)m),'[]'::jsonb);
end $$;

create function private.device_settings(device uuid,operation text,push_token text) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not private.is_active(auth.uid()) then raise insufficient_privilege; end if;
 if operation='list' then return coalesce((select jsonb_agg(jsonb_build_object('id',id,'label',label,'created_at',created_at,'last_seen',last_seen,'revoked_at',revoked_at)) from public.account_devices where user_id=auth.uid()),'[]'::jsonb); end if;
 if operation='revoke' then
  if not exists(select 1 from public.account_devices where id=device and user_id=auth.uid() and revoked_at is null) then raise insufficient_privilege; end if;
 elsif not private.owns_device(device) then raise insufficient_privilege; end if;
 if operation='revoke' then
  -- A user may revoke another device belonging to this account. The target
  -- need not belong to the caller's session; the current session must be active.
  update public.account_devices set revoked_at=now() where id=device;
  delete from private.device_prekeys where device_id=device;
  delete from private.device_push_tokens where device_id=device;
  delete from auth.refresh_tokens where session_id in(select session_id from private.device_sessions where device_id=device);
  delete from auth.sessions where id in(select session_id from private.device_sessions where device_id=device);
 elsif operation='push' then
  if push_token is null then delete from private.device_push_tokens where device_id=device;
  elsif length(push_token) between 10 and 4096 then
   delete from private.device_push_tokens where token=push_token and device_id<>device;
   insert into private.device_push_tokens values(device,push_token,now()) on conflict(device_id) do update set token=excluded.token,updated_at=now();
  else raise exception 'Invalid push token'; end if;
 else raise exception 'Invalid operation'; end if;
 return '{}'::jsonb;
end $$;
create function public.device_settings(device uuid,operation text,push_token text default null) returns jsonb language sql security invoker set search_path='' as $$ select private.device_settings(device,operation,push_token) $$;

-- Private authenticated Storage: ciphertext paths chat/account/object. The blob
-- format carries no original name/MIME/key; those stay inside Signal messages.
alter table public.profiles add column avatar_path text;
grant update(avatar_path) on public.profiles to authenticated;
alter table public.profiles add constraint avatar_owner_path check(avatar_path is null or avatar_path like id::text||'/%');
create or replace function private.list_chats() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.is_active(auth.uid()) then raise insufficient_privilege; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'peer',jsonb_build_object('id',p.id,'username',p.username,'display_name',p.display_name,'bio',p.bio,'avatar_path',p.avatar_path))) from public.conversations c join public.profiles p on p.id=case when c.member_a=auth.uid() then c.member_b else c.member_a end where auth.uid() in(c.member_a,c.member_b)),'[]'::jsonb);
end $$;
create or replace function private.search_people(prefix text) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not private.is_active(auth.uid()) then raise insufficient_privilege; end if;
 if prefix !~ '^[a-z0-9_]{3,24}$' then return '[]'::jsonb; end if;
 if not private.user_budget('search',60) then raise exception 'Rate limited' using errcode='53300'; end if;
 return coalesce((select jsonb_agg(to_jsonb(p)) from (select p.id,p.username,p.display_name,p.bio,p.avatar_path from public.profiles p join private.accounts a on a.id=p.id where p.discoverable and a.status='active' and p.id<>auth.uid() and starts_with(p.username,prefix) and not exists(select 1 from public.blocked_users b where (b.blocker_id=auth.uid() and b.blocked_id=p.id) or (b.blocker_id=p.id and b.blocked_id=auth.uid())) order by p.username limit 20) p),'[]'::jsonb);
end $$;
create function private.attachment_access(path text,writing boolean) returns boolean language plpgsql stable security definer set search_path='' as $$
declare parts text[]:=string_to_array(path,'/'); cid uuid;
begin
 if array_length(parts,1)<>3 or not private.is_active(auth.uid()) then return false; end if;
 begin cid:=parts[1]::uuid; exception when invalid_text_representation then return false; end;
 return case when writing then parts[2]=auth.uid()::text and private.can_send_chat(cid) else private.can_read_chat(cid) end;
end $$;
-- CI supplies a minimal Storage fixture; production uses the Storage-owned tables.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
 ('chat-media','chat-media',false,110000000,array['application/octet-stream']),
 ('avatars','avatars',false,5000000,array['image/jpeg','image/png','image/webp']) on conflict(id) do nothing;
create policy adoetz_media_read on storage.objects for select to authenticated using(bucket_id='chat-media' and private.attachment_access(name,false));
create policy adoetz_media_insert on storage.objects for insert to authenticated with check(bucket_id='chat-media' and private.attachment_access(name,true));
create policy adoetz_media_delete on storage.objects for delete to authenticated using(bucket_id='chat-media' and split_part(name,'/',2)=(select auth.uid())::text and private.attachment_access(name,false));
create policy adoetz_avatar_read on storage.objects for select to authenticated using(bucket_id='avatars' and private.is_active((select auth.uid())));
create policy adoetz_avatar_insert on storage.objects for insert to authenticated with check(bucket_id='avatars' and split_part(name,'/',1)=(select auth.uid())::text and private.is_active((select auth.uid())));
create policy adoetz_avatar_delete on storage.objects for delete to authenticated using(bucket_id='avatars' and split_part(name,'/',1)=(select auth.uid())::text and private.is_active((select auth.uid())));
create table private.media_references(object_path text primary key,message_id uuid not null references public.messages on delete cascade);
alter table private.media_references enable row level security;
revoke all on private.media_references from public,anon,authenticated;
create function private.bind_media_objects() returns trigger language plpgsql security definer set search_path='' as $$
declare path text;
begin
 if new.ciphertext->>'protocol'<>'signal-devices-v2' then return new; end if;
 if jsonb_typeof(new.ciphertext->'objects') is distinct from 'array' then
  -- Text-only clients predating attachment support do not include this field.
  if new.ciphertext ? 'objects' then raise exception 'Invalid object references'; end if;
  return new;
 end if;
 if jsonb_array_length(new.ciphertext->'objects')>5 then raise exception 'Too many objects'; end if;
 for path in select jsonb_array_elements_text(new.ciphertext->'objects') loop
  if not starts_with(path,new.conversation_id::text||'/'||new.sender_id::text||'/') or not exists(select 1 from storage.objects where bucket_id='chat-media' and name=path) then raise insufficient_privilege; end if;
  insert into private.media_references values(path,new.id);
 end loop;
 return new;
end $$;
revoke all on function private.bind_media_objects() from public,anon,authenticated;
create trigger adoetz_bind_media after insert on public.messages for each row execute function private.bind_media_objects();
create function private.orphan_media() returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(to_jsonb(o)),'[]'::jsonb) from(
 select bucket_id,name from storage.objects s where s.created_at<now()-interval '1 day' and(
 (s.bucket_id='chat-media' and not exists(select 1 from private.media_references r where r.object_path=s.name))
 or(s.bucket_id='avatars' and not exists(select 1 from public.profiles p where p.avatar_path=s.name))) order by s.created_at limit 20)o
$$;
create function public.adoetz_orphan_media() returns jsonb language sql stable security invoker set search_path='' as $$select private.orphan_media()$$;
revoke all on function private.orphan_media(),public.adoetz_orphan_media() from public,anon,authenticated;
grant execute on function private.orphan_media(),public.adoetz_orphan_media() to service_role;

create table public.calls (
 id uuid primary key, conversation_id uuid not null references public.conversations,
 caller_id uuid not null references auth.users, caller_device uuid not null references public.account_devices,
 callee_device uuid references public.account_devices, video boolean not null,
 status text not null check(status in('ringing','connecting','connected','ended','declined','missed','failed')),
 created_at timestamptz not null default now(), expires_at timestamptz not null,
 connected_at timestamptz, ended_at timestamptz, reason text
);
create index calls_chat_created on public.calls(conversation_id,created_at desc);
create index calls_live on public.calls(expires_at) where status in('ringing','connecting','connected');
alter table public.calls enable row level security;
revoke all on public.calls from anon,authenticated;
grant select on public.calls to authenticated;
create policy call_member_read on public.calls for select to authenticated using(private.can_read_chat(conversation_id));
create function private.call_action(call_id uuid,device uuid,operation text,chat uuid,is_video boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.calls; room public.conversations;
begin
 if not private.owns_device(device) then raise insufficient_privilege; end if;
 if operation='start' then
  if not private.can_send_chat(chat) then raise insufficient_privilege; end if;
  select * into room from public.conversations where id=chat;
  perform pg_advisory_xact_lock(hashtextextended(room.member_a::text,8));
  perform pg_advisory_xact_lock(hashtextextended(room.member_b::text,8));
  update public.calls set status=case when status='ringing' then 'missed' else 'failed' end,ended_at=now(),reason='timeout' where expires_at<now() and status in('ringing','connecting','connected');
  select * into c from public.calls where id=call_id;
  if c.id is null then
   if not private.user_budget('call-start',5) then raise exception 'Rate limited' using errcode='53300'; end if;
   if exists(select 1 from public.calls x join public.conversations r on x.conversation_id=r.id where x.status in('ringing','connecting','connected') and (r.member_a in(room.member_a,room.member_b) or r.member_b in(room.member_a,room.member_b))) then raise exception 'User busy'; end if;
   insert into public.calls(id,conversation_id,caller_id,caller_device,video,status,expires_at) values(call_id,chat,auth.uid(),device,is_video,'ringing',now()+interval '45 seconds') returning * into c;
   insert into private.push_jobs(device_id,event_id,kind) select d.id,call_id,'call' from public.account_devices d where d.user_id in(room.member_a,room.member_b) and d.user_id<>auth.uid() and d.revoked_at is null;
  elsif c.caller_device<>device or c.conversation_id<>chat then raise insufficient_privilege; end if;
 else
  select * into c from public.calls where id=call_id for update;
  if c.id is null or not private.can_read_chat(c.conversation_id) then raise insufficient_privilege; end if;
  if c.expires_at<now() and c.status in('ringing','connecting','connected') then
   update public.calls set status=case when status='ringing' then 'missed' else 'failed' end,ended_at=now(),reason='timeout' where id=call_id returning * into c;
  end if;
  if operation='accept' then
   if c.caller_id=auth.uid() or not private.can_send_chat(c.conversation_id) then raise insufficient_privilege; end if;
   if c.status='ringing' then update public.calls set status='connecting',callee_device=device,expires_at=now()+interval '60 seconds' where id=call_id returning * into c;
   elsif c.callee_device is distinct from device then raise exception 'Call answered on another device'; end if;
  elsif operation in('connected','heartbeat') then
   if device<>c.caller_device and device is distinct from c.callee_device then raise insufficient_privilege; end if;
   if c.status in('connecting','connected') then update public.calls set status=case when operation='connected' then 'connected' else status end,connected_at=case when operation='connected' then coalesce(connected_at,now()) else connected_at end,expires_at=now()+interval '60 seconds' where id=call_id returning * into c; end if;
  elsif operation in('end','decline') then
   if operation='decline' and (c.caller_id=auth.uid() or c.status<>'ringing') then raise insufficient_privilege; end if;
   if c.status in('ringing','connecting','connected') then update public.calls set status=case when operation='decline' then 'declined' else 'ended' end,ended_at=now(),reason=operation where id=call_id returning * into c; end if;
  elsif operation<>'get' then raise exception 'Invalid operation'; end if;
 end if;
 return to_jsonb(c);
end $$;
create function public.call_action(call_id uuid,device uuid,operation text,chat uuid default null,is_video boolean default false) returns jsonb language sql security invoker set search_path='' as $$ select private.call_action(call_id,device,operation,chat,is_video) $$;

-- Worker can claim only a bounded set. Tokens/credentials never enter user APIs.
create function private.claim_push_jobs() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 delete from private.push_jobs where attempts>=8 or created_at<now()-interval '1 day';
 return coalesce((with due as(select id from private.push_jobs where available_at<=now() order by id limit 100 for update skip locked), claimed as(update private.push_jobs j set attempts=attempts+1,available_at=now()+least(interval '10 minutes',interval '5 seconds'*power(2,attempts)) from due where j.id=due.id returning j.*) select jsonb_agg(to_jsonb(c)||jsonb_build_object('token',t.token)) from claimed c join private.device_push_tokens t using(device_id) join public.account_devices d on d.id=c.device_id and d.revoked_at is null join private.accounts a on a.id=d.user_id and a.status='active'),'[]'::jsonb);
end $$;
create function public.adoetz_claim_push_jobs() returns jsonb language sql security invoker set search_path='' as $$ select private.claim_push_jobs() $$;
create function private.finish_push_job(job bigint,invalid_token boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 if invalid_token then delete from private.device_push_tokens where device_id=(select device_id from private.push_jobs where id=job); end if;
 delete from private.push_jobs where id=job;
end $$;
create function public.adoetz_finish_push_job(job bigint,invalid_token boolean default false) returns void language sql security invoker set search_path='' as $$ select private.finish_push_job(job,invalid_token) $$;

-- Every newly introduced helper/entry point has an explicit allowlist.
revoke all on function private.owns_device(uuid),private.register_device_v2(uuid,jsonb,text),private.chat_devices(uuid),private.device_prekey_bundle(uuid,uuid,boolean),private.send_device_message(uuid,uuid,jsonb),private.sync_device_messages(uuid,uuid,bigint),private.device_settings(uuid,text,text),private.attachment_access(text,boolean),private.call_action(uuid,uuid,text,uuid,boolean),private.claim_push_jobs(),private.finish_push_job(bigint,boolean) from public,anon,authenticated;
grant execute on function private.owns_device(uuid),private.register_device_v2(uuid,jsonb,text),private.chat_devices(uuid),private.device_prekey_bundle(uuid,uuid,boolean),private.send_device_message(uuid,uuid,jsonb),private.sync_device_messages(uuid,uuid,bigint),private.device_settings(uuid,text,text),private.attachment_access(text,boolean),private.call_action(uuid,uuid,text,uuid,boolean) to authenticated;
revoke all on function public.register_device_v2(uuid,jsonb,text),public.chat_devices(uuid),public.device_prekey_bundle(uuid,uuid,boolean),public.send_device_message(uuid,uuid,jsonb),public.sync_device_messages(uuid,uuid,bigint),public.device_settings(uuid,text,text),public.call_action(uuid,uuid,text,uuid,boolean),public.adoetz_claim_push_jobs(),public.adoetz_finish_push_job(bigint,boolean) from public,anon,authenticated;
grant execute on function public.register_device_v2(uuid,jsonb,text),public.chat_devices(uuid),public.device_prekey_bundle(uuid,uuid,boolean),public.send_device_message(uuid,uuid,jsonb),public.sync_device_messages(uuid,uuid,bigint),public.device_settings(uuid,text,text),public.call_action(uuid,uuid,text,uuid,boolean) to authenticated;
grant execute on function private.claim_push_jobs(),private.finish_push_job(bigint,boolean),public.adoetz_claim_push_jobs(),public.adoetz_finish_push_job(bigint,boolean) to service_role;
create function private.consume_legacy_prekey() returns trigger language plpgsql security definer set search_path='' as $$
begin
 delete from private.device_prekeys where device_id=old.user_id and key_id=old.key_id;
 return old;
end $$;
revoke all on function private.consume_legacy_prekey() from public,anon,authenticated;
create trigger adoetz_consume_legacy_prekey after delete on private.prekeys for each row execute function private.consume_legacy_prekey();

create or replace function public.adoetz_login_lookup(identifier text) returns text language sql stable security invoker set search_path='' as $$
 select u.email from auth.users u join public.profiles p on p.id=u.id join private.accounts a on a.id=u.id where p.username=identifier and a.status in('active','reset_required') limit 1
$$;
create or replace function public.adoetz_admin_snapshot(actor uuid,kind text) returns jsonb language plpgsql security invoker set search_path='' as $$
begin
 if not exists(select 1 from private.accounts where id=actor and role='admin' and status='active') then raise insufficient_privilege; end if;
 if kind='audit' then return coalesce((select jsonb_agg(to_jsonb(a)) from(select * from private.audit_logs order by id desc limit 100)a),'[]'::jsonb); end if;
 if kind='reports' then return coalesce((select jsonb_agg(to_jsonb(a)) from(select * from private.reports order by created_at desc limit 100)a),'[]'::jsonb); end if;
 if kind='invites' then return coalesce((select jsonb_agg(to_jsonb(a)) from(select id,created_by,expires_at,used_by,used_at,revoked from private.invitations order by expires_at desc limit 100)a),'[]'::jsonb); end if;
 return coalesce((select jsonb_agg(to_jsonb(a)) from(select p.id,p.username,p.display_name,a.role,a.status from public.profiles p join private.accounts a on a.id=p.id order by p.username limit 100)a),'[]'::jsonb);
end $$;
create function private.admin_action_v2(actor uuid,target uuid,operation text,reason text,request_id uuid,invite_hash text) returns void language plpgsql security definer set search_path='' as $$
begin
 perform pg_advisory_xact_lock(5222026);
 if not exists(select 1 from private.accounts where id=actor and role='admin' and status='active') or length(reason) not between 1 and 200 then raise insufficient_privilege; end if;
 if exists(select 1 from private.audit_logs a where a.request_id=admin_action_v2.request_id) then
  if not exists(select 1 from private.audit_logs a where a.request_id=admin_action_v2.request_id and a.actor_id=actor and a.target_id is not distinct from target and a.action=operation) then raise insufficient_privilege; end if;
  return;
 end if;
 if operation='create-invite' then
  insert into private.invitations(token_hash,created_by,expires_at) values(invite_hash,actor,now()+interval '7 days');
 elsif operation='revoke-invite' then
  update private.invitations set revoked=true where id=target and used_at is null;
  if not found then raise exception 'Invitation unavailable'; end if;
 else
  if target=actor or not exists(select 1 from private.accounts where id=target) then raise insufficient_privilege; end if;
  if exists(select 1 from private.accounts where id=target and status='deleted') and operation not in('soft-delete','revoke-sessions') then raise insufficient_privilege; end if;
  if operation='demote' then
   if (select count(*) from private.accounts where role='admin' and status='active')<2 or not exists(select 1 from private.accounts where id=target and role='admin') then raise insufficient_privilege; end if;
   update private.accounts set role='user' where id=target;
  elsif operation='promote' then
   if not exists(select 1 from private.accounts where id=target and role='user' and status='active') then raise insufficient_privilege; end if;
   update private.accounts set role='admin' where id=target;
  else
   if exists(select 1 from private.accounts where id=target and role='admin') then raise insufficient_privilege; end if;
   if operation not in('suspend','unsuspend','force-reset','soft-delete','revoke-sessions') then raise exception 'Unsupported operation'; end if;
   if operation='unsuspend' and not exists(select 1 from private.accounts where id=target and status='suspended') then raise insufficient_privilege; end if;
   if operation<>'revoke-sessions' then update private.accounts set status=case operation when 'suspend' then 'suspended' when 'unsuspend' then 'active' when 'force-reset' then 'reset_required' else 'deleted' end where id=target; end if;
   if operation<>'unsuspend' then
    delete from private.push_tokens where user_id=target;
    delete from private.device_push_tokens where device_id in(select id from public.account_devices where user_id=target);
    delete from auth.refresh_tokens where session_id in(select id from auth.sessions where user_id=target);
    delete from auth.sessions where user_id=target;
    update public.calls set status='ended',ended_at=now(),reason='account-unavailable' where status in('ringing','connecting','connected') and conversation_id in(select id from public.conversations where target in(member_a,member_b));
   end if;
  end if;
 end if;
 insert into private.audit_logs(actor_id,target_id,action,reason,request_id) values(actor,target,operation,reason,request_id);
end $$;
create or replace function public.adoetz_admin_action(actor uuid,target uuid,operation text,reason text,request_id uuid,invite_hash text default null) returns void language sql security invoker set search_path='' as $$ select private.admin_action_v2(actor,target,operation,reason,request_id,invite_hash) $$;
revoke all on function private.admin_action_v2(uuid,uuid,text,text,uuid,text) from public,anon,authenticated;
grant execute on function private.admin_action_v2(uuid,uuid,text,text,uuid,text) to service_role;

create function private.password_changed(actor uuid,keep_session uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from private.accounts where id=actor and status in('active','reset_required')) or not exists(select 1 from auth.sessions where id=keep_session and user_id=actor) then raise insufficient_privilege; end if;
 update private.accounts set status='active' where id=actor;
 delete from auth.refresh_tokens where session_id in(select id from auth.sessions where user_id=actor and id<>keep_session);
 delete from auth.sessions where user_id=actor and id<>keep_session;
 insert into private.audit_logs(actor_id,target_id,action,reason,request_id) values(actor,actor,'password-changed','User completed password change',gen_random_uuid());
end $$;
create function public.adoetz_password_changed(actor uuid,keep_session uuid) returns void language sql security invoker set search_path='' as $$ select private.password_changed(actor,keep_session) $$;
revoke all on function private.password_changed(uuid,uuid),public.adoetz_password_changed(uuid,uuid) from public,anon,authenticated;
grant execute on function private.password_changed(uuid,uuid),public.adoetz_password_changed(uuid,uuid) to service_role;
create table private.reports(id uuid primary key default gen_random_uuid(),reporter_id uuid not null references auth.users,target_id uuid not null references auth.users,conversation_id uuid not null references public.conversations,reason text not null check(length(reason) between 1 and 1000),created_at timestamptz not null default now());
create index reports_actor_created on private.reports(reporter_id,created_at);
alter table private.reports enable row level security;
revoke all on private.reports from public,anon,authenticated;
grant select on private.reports to service_role;
create function private.submit_report(chat uuid,reason text) returns void language plpgsql security definer set search_path='' as $$
declare target uuid;
begin
 if not private.can_read_chat(chat) or length(reason) not between 1 and 1000 then raise insufficient_privilege; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,9));
 if (select count(*) from private.reports where reporter_id=auth.uid() and created_at>now()-interval '1 day')>=5 then raise exception 'Daily report limit'; end if;
 select case when member_a=auth.uid() then member_b else member_a end into target from public.conversations where id=chat;
 insert into private.reports(reporter_id,target_id,conversation_id,reason) values(auth.uid(),target,chat,reason);
end $$;
create function public.submit_report(chat uuid,reason text) returns void language sql security invoker set search_path='' as $$ select private.submit_report(chat,reason) $$;
revoke all on function private.submit_report(uuid,text),public.submit_report(uuid,text) from public,anon,authenticated;
grant execute on function private.submit_report(uuid,text),public.submit_report(uuid,text) to authenticated;
create function private.user_budget(scope text,ceiling int) returns boolean language plpgsql security definer set search_path='' as $$
declare hits int; key text;
begin
 if auth.uid() is null then return false; end if;
 key:=encode(extensions.digest(auth.uid()::text||':'||scope,'sha256'),'hex');
 insert into private.rate_limits as r values(key,now(),1) on conflict(key_hash) do update set requests=case when r.window_start<now()-interval '1 minute' then 1 else r.requests+1 end,window_start=case when r.window_start<now()-interval '1 minute' then now() else r.window_start end returning requests into hits;
 return hits<=ceiling;
end $$;
revoke all on function private.user_budget(text,int) from public,anon,authenticated;
create function private.realtime_chat_access(topic text) returns boolean language plpgsql stable security definer set search_path='' as $$
declare cid uuid;
begin
 if not starts_with(topic,'chat:') then return false; end if;
 begin cid:=substring(topic from 6)::uuid; exception when invalid_text_representation then return false; end;
 return private.can_send_chat(cid);
end $$;
revoke all on function private.realtime_chat_access(text) from public,anon,authenticated;
grant execute on function private.realtime_chat_access(text) to authenticated;
do $$ begin
 if to_regclass('realtime.messages') is not null then
  execute 'create policy adoetz_private_chat_read on realtime.messages for select to authenticated using(extension in (''broadcast'',''presence'') and private.realtime_chat_access((select realtime.topic())))';
  execute 'create policy adoetz_private_chat_write on realtime.messages for insert to authenticated with check(extension in (''broadcast'',''presence'') and private.realtime_chat_access((select realtime.topic())))';
 end if;
end $$;
notify pgrst,'reload schema';
