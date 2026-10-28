-- Apply to a dedicated staging project. Never test this against production.
create extension if not exists pgcrypto with schema extensions;
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated, service_role;

create table private.accounts (
 id uuid primary key references auth.users on delete cascade,
 role text not null default 'user' check (role in ('user','admin')),
 status text not null default 'active' check (status in ('active','suspended','reset_required','deleted')),
 created_at timestamptz not null default now()
);
create table private.invitations (
 id uuid primary key default gen_random_uuid(), token_hash text not null unique,
 created_by uuid references auth.users, expires_at timestamptz not null,
 used_by uuid references auth.users, used_at timestamptz, revoked boolean not null default false
);
create table private.audit_logs (
 id bigint generated always as identity primary key,
 actor_id uuid not null, target_id uuid, action text not null, reason text not null,
 request_id uuid not null unique, created_at timestamptz not null default now()
);
create table private.rate_limits (key_hash text primary key, window_start timestamptz not null, requests int not null);
create table public.profiles (
 id uuid primary key references auth.users on delete cascade,
 username text not null unique check (username ~ '^[a-z0-9_]{3,24}$' and username not in ('admin','root','system','support','adoetz')),
 display_name text not null check (length(display_name) between 1 and 60),
 bio text not null default '' check (length(bio) <= 160),
 discoverable boolean not null default true,
 created_at timestamptz not null default now()
);
create table public.conversations (
 id uuid primary key default gen_random_uuid(),
 member_a uuid not null references auth.users, member_b uuid not null references auth.users,
 created_at timestamptz not null default now(),
 unique(member_a,member_b), check (member_a < member_b)
);
create index conversations_member_b on public.conversations(member_b);
create table public.blocked_users (
 blocker_id uuid not null references auth.users on delete cascade,
 blocked_id uuid not null references auth.users on delete cascade,
 created_at timestamptz not null default now(), primary key(blocker_id,blocked_id), check(blocker_id <> blocked_id)
);
create index blocked_users_reverse on public.blocked_users(blocked_id,blocker_id);
create table public.devices (
 user_id uuid primary key references auth.users on delete cascade,
 bundle jsonb not null, created_at timestamptz not null default now()
);
create table private.prekeys (
 user_id uuid not null references auth.users on delete cascade, key_id int not null,
 public_key text not null, primary key(user_id,key_id)
);
create table public.messages (
 id uuid primary key default gen_random_uuid(), sequence bigint generated always as identity unique,
 conversation_id uuid not null references public.conversations,
 sender_id uuid not null references auth.users, client_message_id uuid not null,
 ciphertext jsonb not null check (ciphertext->>'protocol' = 'signal-v1' and length(ciphertext->>'body') between 1 and 100000),
 created_at timestamptz not null default now(), unique(sender_id,client_message_id)
);
create index messages_chat_cursor on public.messages(conversation_id,sequence);
create table private.push_tokens (user_id uuid primary key references auth.users on delete cascade, token text not null, updated_at timestamptz not null default now());

-- No role or status is taken from editable user_metadata.
create function private.is_active(uid uuid) returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from private.accounts where id=uid and status='active')
$$;
revoke all on function private.is_active(uuid) from public,anon;
grant execute on function private.is_active(uuid) to authenticated;
create function private.can_read_chat(chat uuid) returns boolean language sql stable security definer set search_path = '' as $$
 select auth.uid() is not null and private.is_active(auth.uid()) and exists(select 1 from public.conversations where id=chat and auth.uid() in (member_a,member_b))
$$;
revoke all on function private.can_read_chat(uuid) from public,anon;
grant execute on function private.can_read_chat(uuid) to authenticated;
create function private.can_send_chat(chat uuid) returns boolean language sql stable security definer set search_path = '' as $$
 select private.can_read_chat(chat) and exists(select 1 from public.conversations c where c.id=chat and private.is_active(c.member_a) and private.is_active(c.member_b) and not exists(select 1 from public.blocked_users b where (b.blocker_id=c.member_a and b.blocked_id=c.member_b) or (b.blocker_id=c.member_b and b.blocked_id=c.member_a)))
$$;
revoke all on function private.can_send_chat(uuid) from public,anon;
grant execute on function private.can_send_chat(uuid) to authenticated;

-- Invite is validated and consumed in the SAME Auth transaction, including
-- direct /auth/v1/signup calls. Any collision rolls back invite consumption.
create function private.on_signup() returns trigger language plpgsql security definer set search_path = '' as $$
declare username_value text; invite_id uuid;
begin
 username_value := new.raw_user_meta_data->>'username';
 if username_value is null or new.raw_user_meta_data->>'invite_code' is null then raise exception 'Registration is invitation only'; end if;
 select id into invite_id from private.invitations
 where token_hash=encode(extensions.digest(new.raw_user_meta_data->>'invite_code','sha256'),'hex')
 and used_at is null and not revoked and expires_at>now() for update;
 if invite_id is null then raise exception 'Invitation unavailable'; end if;
 insert into public.profiles(id,username,display_name) values(new.id,username_value,username_value);
 insert into private.accounts(id) values(new.id);
 update private.invitations set used_by=new.id,used_at=now() where id=invite_id;
 update auth.users set raw_user_meta_data=raw_user_meta_data - 'invite_code' where id=new.id;
 return new;
end $$;
revoke all on function private.on_signup() from public,anon,authenticated;
create trigger adoetz_signup after insert on auth.users for each row execute function private.on_signup();

alter table public.profiles enable row level security;
alter table public.conversations enable row level security;
alter table public.blocked_users enable row level security;
alter table public.devices enable row level security;
alter table public.messages enable row level security;
alter table private.accounts enable row level security;
alter table private.invitations enable row level security;
alter table private.audit_logs enable row level security;
alter table private.rate_limits enable row level security;
alter table private.prekeys enable row level security;
alter table private.push_tokens enable row level security;
revoke all on public.profiles,public.conversations,public.blocked_users,public.devices,public.messages from anon,authenticated;
grant select on public.profiles,public.conversations,public.messages to authenticated;
grant update(display_name,bio,discoverable) on public.profiles to authenticated;
grant select,insert,delete on public.blocked_users to authenticated;
create policy own_profile_read on public.profiles for select to authenticated using (id=(select auth.uid()) and private.is_active((select auth.uid())));
create policy own_profile_update on public.profiles for update to authenticated using (id=(select auth.uid()) and private.is_active((select auth.uid()))) with check (id=(select auth.uid()) and private.is_active((select auth.uid())));
create policy chat_members_read on public.conversations for select to authenticated using (private.can_read_chat(id));
create policy message_members_read on public.messages for select to authenticated using (private.can_read_chat(conversation_id));
create policy own_blocks_read on public.blocked_users for select to authenticated using (blocker_id=(select auth.uid()) and private.is_active((select auth.uid())));
create policy own_blocks_insert on public.blocked_users for insert to authenticated with check (blocker_id=(select auth.uid()) and private.is_active((select auth.uid())));
create policy own_blocks_delete on public.blocked_users for delete to authenticated using (blocker_id=(select auth.uid()) and private.is_active((select auth.uid())));

-- All definer code is private; exposed entry points use invoker security.
create function private.my_account() returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
 if auth.uid() is null then raise insufficient_privilege; end if;
 return (select jsonb_build_object('role',role,'status',status) from private.accounts where id=auth.uid());
end $$;
create function public.my_account() returns jsonb language sql stable security invoker set search_path = '' as $$ select private.my_account() $$;

create function private.search_people(prefix text) returns jsonb language plpgsql security definer set search_path = '' as $$
begin
 if not private.is_active(auth.uid()) then raise insufficient_privilege; end if;
 if prefix !~ '^[a-z0-9_]{3,24}$' then return '[]'::jsonb; end if;
 return coalesce((select jsonb_agg(to_jsonb(p)) from (select p.id,p.username,p.display_name,p.bio from public.profiles p join private.accounts a on a.id=p.id where p.discoverable and a.status='active' and p.id<>auth.uid() and starts_with(p.username,prefix) and not exists(select 1 from public.blocked_users b where (b.blocker_id=auth.uid() and b.blocked_id=p.id) or (b.blocker_id=p.id and b.blocked_id=auth.uid())) order by p.username limit 20) p),'[]'::jsonb);
end $$;
create function public.search_people(prefix text) returns jsonb language sql security invoker set search_path = '' as $$ select private.search_people(prefix) $$;
create function private.create_chat(peer uuid) returns uuid language plpgsql security definer set search_path = '' as $$
declare result uuid;
begin
 if auth.uid() is null or peer=auth.uid() or not private.is_active(auth.uid()) or not private.is_active(peer) then raise insufficient_privilege; end if;
 if exists(select 1 from public.blocked_users where (blocker_id=peer and blocked_id=auth.uid()) or (blocked_id=peer and blocker_id=auth.uid())) then raise insufficient_privilege; end if;
 insert into public.conversations(member_a,member_b) values(least(auth.uid(),peer),greatest(auth.uid(),peer)) on conflict(member_a,member_b) do nothing;
 select id into result from public.conversations where member_a=least(auth.uid(),peer) and member_b=greatest(auth.uid(),peer);
 return result;
end $$;
create function public.create_chat(peer uuid) returns uuid language sql security invoker set search_path = '' as $$ select private.create_chat(peer) $$;
create function private.list_chats() returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
 if not private.is_active(auth.uid()) then raise insufficient_privilege; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'peer',jsonb_build_object('id',p.id,'username',p.username,'display_name',p.display_name,'bio',p.bio))) from public.conversations c join public.profiles p on p.id=case when c.member_a=auth.uid() then c.member_b else c.member_a end where auth.uid() in (c.member_a,c.member_b)),'[]'::jsonb);
end $$;
create function public.list_chats() returns jsonb language sql stable security invoker set search_path = '' as $$ select private.list_chats() $$;
create function private.register_device(bundle jsonb) returns void language plpgsql security definer set search_path = '' as $$
declare existing jsonb; k jsonb;
begin
 if not private.is_active(auth.uid()) then raise insufficient_privilege; end if;
 if length(bundle->>'identity_key')<>44 or length(bundle->>'signed_prekey')<>44 or length(bundle->>'signature')<>88 or (bundle->>'registration_id')::int not between 1 and 16380 or jsonb_array_length(bundle->'prekeys')>100 then raise exception 'Invalid public bundle'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
 select d.bundle into existing from public.devices d where user_id=auth.uid();
 if existing is not null and existing->>'identity_key'<>bundle->>'identity_key' then raise exception 'A different device is registered. Contact administrator before replacing identity.'; end if;
 insert into public.devices(user_id,bundle) values(auth.uid(),bundle-'prekeys') on conflict(user_id) do nothing;
 for k in select * from jsonb_array_elements(bundle->'prekeys') loop
  if length(k->>'key')<>44 then raise exception 'Invalid prekey'; end if;
  -- Only provision initially: consumed prekeys must never be reintroduced on login.
  if existing is null then insert into private.prekeys(user_id,key_id,public_key) values(auth.uid(),(k->>'id')::int,k->>'key'); end if;
 end loop;
end $$;
create function public.register_device(bundle jsonb) returns void language sql security invoker set search_path = '' as $$ select private.register_device(bundle) $$;
create function private.get_prekey_bundle(peer uuid,consume boolean default true) returns jsonb language plpgsql security definer set search_path = '' as $$
declare result jsonb; selected_key private.prekeys;
begin
 if not exists(select 1 from public.conversations where peer in (member_a,member_b) and private.can_send_chat(id)) then raise insufficient_privilege; end if;
 select bundle into result from public.devices where user_id=peer;
 if result is null then raise exception 'Peer has not initialized device'; end if;
 select * into selected_key from private.prekeys where user_id=peer order by key_id limit 1 for update skip locked;
 if consume and selected_key.key_id is not null then
  delete from private.prekeys where user_id=peer and key_id=selected_key.key_id;
  result := result || jsonb_build_object('prekey',jsonb_build_object('id',selected_key.key_id,'key',selected_key.public_key));
 end if;
 return result;
end $$;
create function public.get_prekey_bundle(peer uuid,consume boolean default true) returns jsonb language sql security invoker set search_path = '' as $$ select private.get_prekey_bundle(peer,consume) $$;
create function private.send_message(chat uuid,client_id uuid,envelope jsonb) returns jsonb language plpgsql security definer set search_path = '' as $$
declare result public.messages;
begin
 if not private.can_send_chat(chat) then raise insufficient_privilege; end if;
 -- Serialize creation so the sequence cursor reflects commit order per chat.
 perform 1 from public.conversations where id=chat for update;
 insert into public.messages(conversation_id,sender_id,client_message_id,ciphertext) values(chat,auth.uid(),client_id,envelope) on conflict(sender_id,client_message_id) do nothing;
 select * into result from public.messages where sender_id=auth.uid() and client_message_id=client_id;
 if result.conversation_id<>chat or result.ciphertext<>envelope then raise exception 'Idempotency conflict'; end if;
 return jsonb_build_object('id',result.id,'sequence',result.sequence,'created_at',result.created_at);
end $$;
create function public.send_message(chat uuid,client_id uuid,envelope jsonb) returns jsonb language sql security invoker set search_path = '' as $$ select private.send_message(chat,client_id,envelope) $$;
create function private.sync_messages(chat uuid,after_sequence bigint) returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
 if not private.can_read_chat(chat) then raise insufficient_privilege; end if;
 return coalesce((select jsonb_agg(to_jsonb(m) order by m.sequence) from (select * from public.messages where conversation_id=chat and sequence>after_sequence order by sequence limit 50) m),'[]'::jsonb);
end $$;
create function public.sync_messages(chat uuid,after_sequence bigint) returns jsonb language sql stable security invoker set search_path = '' as $$ select private.sync_messages(chat,after_sequence) $$;
create function private.register_push_token(push_token text) returns void language plpgsql security definer set search_path = '' as $$
begin
 if not private.is_active(auth.uid()) or length(push_token)>4096 then raise insufficient_privilege; end if;
 insert into private.push_tokens(user_id,token) values(auth.uid(),push_token) on conflict(user_id) do update set token=excluded.token,updated_at=now();
end $$;
create function public.register_push_token(push_token text) returns void language sql security invoker set search_path = '' as $$ select private.register_push_token(push_token) $$;

-- Explicitly scoped function privileges; private isn't in exposed API schemas.
revoke all on function private.is_active(uuid),private.can_read_chat(uuid),private.can_send_chat(uuid),private.on_signup(),private.my_account(),private.search_people(text),private.create_chat(uuid),private.list_chats(),private.register_device(jsonb),private.get_prekey_bundle(uuid,boolean),private.send_message(uuid,uuid,jsonb),private.sync_messages(uuid,bigint),private.register_push_token(text) from public,anon,authenticated;
grant execute on function private.is_active(uuid),private.can_read_chat(uuid),private.can_send_chat(uuid),private.my_account(),private.search_people(text),private.create_chat(uuid),private.list_chats(),private.register_device(jsonb),private.get_prekey_bundle(uuid,boolean),private.send_message(uuid,uuid,jsonb),private.sync_messages(uuid,bigint),private.register_push_token(text) to authenticated;
revoke all on function public.my_account(),public.search_people(text),public.create_chat(uuid),public.list_chats(),public.register_device(jsonb),public.get_prekey_bundle(uuid,boolean),public.send_message(uuid,uuid,jsonb),public.sync_messages(uuid,bigint),public.register_push_token(text) from public,anon;
grant execute on function public.my_account(),public.search_people(text),public.create_chat(uuid),public.list_chats(),public.register_device(jsonb),public.get_prekey_bundle(uuid,boolean),public.send_message(uuid,uuid,jsonb),public.sync_messages(uuid,bigint),public.register_push_token(text) to authenticated;

-- Service-only helpers for edge functions.
create function public.adoetz_rate_limit(bucket_hash text) returns boolean language plpgsql security invoker set search_path = '' as $$
declare hits int;
begin
 insert into private.rate_limits as r(key_hash,window_start,requests) values(bucket_hash,now(),1) on conflict(key_hash) do update set requests=case when r.window_start<now()-interval '1 minute' then 1 else r.requests+1 end,window_start=case when r.window_start<now()-interval '1 minute' then now() else r.window_start end returning requests into hits;
 return hits<=10;
end $$;
create function public.adoetz_login_lookup(identifier text) returns text language sql stable security invoker set search_path = '' as $$ select u.email from auth.users u join public.profiles p on p.id=u.id join private.accounts a on a.id=u.id where p.username=identifier and a.status='active' limit 1 $$;
create function public.adoetz_admin_snapshot(actor uuid,kind text) returns jsonb language plpgsql security invoker set search_path = '' as $$
begin
 if not exists(select 1 from private.accounts where id=actor and role='admin' and status='active') then raise insufficient_privilege; end if;
 if kind='audit' then return coalesce((select jsonb_agg(to_jsonb(a)) from (select * from private.audit_logs order by id desc limit 100) a),'[]'::jsonb); end if;
 return coalesce((select jsonb_agg(to_jsonb(a)) from (select p.id,p.username,p.display_name,a.role,a.status from public.profiles p join private.accounts a on a.id=p.id order by p.username limit 100) a),'[]'::jsonb);
end $$;
create function public.adoetz_admin_action(actor uuid,target uuid,operation text,reason text,request_id uuid,invite_hash text default null) returns void language plpgsql security invoker set search_path = '' as $$
begin
 perform pg_advisory_xact_lock(5222026);
 if not exists(select 1 from private.accounts where id=actor and role='admin' and status='active') or length(reason) not between 1 and 200 then raise insufficient_privilege; end if;
 if exists(select 1 from private.audit_logs a where a.request_id=adoetz_admin_action.request_id) then return; end if;
 if operation='create-invite' then
  insert into private.invitations(token_hash,created_by,expires_at) values(invite_hash,actor,now()+interval '7 days');
 else
  if target=actor or not exists(select 1 from private.accounts where id=target) then raise insufficient_privilege; end if;
  -- Alpha prohibits destructive or credential actions against ALL admins.
  if exists(select 1 from private.accounts where id=target and role='admin') then raise insufficient_privilege; end if;
  if operation not in ('suspend','unsuspend','force-reset','soft-delete') then raise exception 'Unsupported operation'; end if;
  update private.accounts set status=case operation when 'suspend' then 'suspended' when 'unsuspend' then 'active' when 'force-reset' then 'reset_required' else 'deleted' end where id=target;
  delete from private.push_tokens where user_id=target;
 end if;
 insert into private.audit_logs(actor_id,target_id,action,reason,request_id) values(actor,target,operation,reason,request_id);
end $$;
revoke all on function public.adoetz_rate_limit(text),public.adoetz_login_lookup(text),public.adoetz_admin_snapshot(uuid,text),public.adoetz_admin_action(uuid,uuid,text,text,uuid,text) from public,anon,authenticated;
grant execute on function public.adoetz_rate_limit(text),public.adoetz_login_lookup(text),public.adoetz_admin_snapshot(uuid,text),public.adoetz_admin_action(uuid,uuid,text,text,uuid,text) to service_role;
grant all on private.accounts,private.invitations,private.audit_logs,private.rate_limits,private.prekeys,private.push_tokens to service_role;
grant select on public.profiles to service_role;
grant usage on schema auth to service_role;
grant select(id,email) on auth.users to service_role;
grant usage,select on sequence private.audit_logs_id_seq to service_role;

-- Postgres Changes is a small closed-alpha hint. Catch-up RPC is authoritative.
do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') then
  alter publication supabase_realtime add table public.messages;
 end if;
end $$;


