-- Preserve devices and durable outboxes created by 0.1 clients during rollout.
create or replace function private.register_device_v2(requested_id uuid,bundle jsonb,device_label text) returns uuid language plpgsql security definer set search_path='' as $$
declare selected_id uuid; existing jsonb; k jsonb; highwater int; next_highwater int;
begin
 if not private.is_active(auth.uid()) then raise insufficient_privilege; end if;
 if requested_id is null or bundle is null or length(bundle->>'identity_key') is distinct from 44
 or length(bundle->>'signed_prekey') is distinct from 44 or length(bundle->>'signature') is distinct from 88
 or coalesce((bundle->>'registration_id')::int,0) not between 1 and 16380
 or jsonb_typeof(bundle->'prekeys') is distinct from 'array' or jsonb_array_length(bundle->'prekeys')>100
 then raise exception 'Invalid device bundle'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
 -- A 0.1 client may first register after the device-directory migration.
 -- Adopt only its matching identity, preserving the original Signal address.
 -- Never recreate an existing revoked entry or restore consumed one-time keys.
 if not exists(select 1 from public.account_devices where id=auth.uid())
 and exists(select 1 from public.devices d where d.user_id=auth.uid()
   and d.bundle->>'identity_key'=register_device_v2.bundle->>'identity_key') then
  insert into public.account_devices(id,user_id,bundle,label,created_at,prekey_highwater)
   select user_id,user_id,d.bundle,'Android (perangkat awal)',created_at,50
   from public.devices d where d.user_id=auth.uid();
  insert into private.device_prekeys(device_id,key_id,public_key)
   select user_id,key_id,public_key from private.prekeys where user_id=auth.uid();
 end if;
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
-- A committed old outbox must retry its original envelope, not re-encrypt.
-- Only the original peer device can decrypt that one-device ciphertext.
create function private.queue_legacy_push() returns trigger
language plpgsql security definer set search_path='' as $$
declare peer uuid;
begin
 if new.ciphertext->>'protocol'='signal-v1' then
  select case when member_a=new.sender_id then member_b else member_a end
   into peer from public.conversations where id=new.conversation_id;
  insert into private.push_jobs(device_id,event_id,kind)
   select id,new.id,'message' from public.account_devices
   where id=peer and user_id=peer and revoked_at is null
   on conflict(device_id,event_id,kind) do nothing;
 end if;
 return new;
end $$;
revoke all on function private.queue_legacy_push() from public,anon,authenticated;
create trigger queue_legacy_push after insert on public.messages
 for each row execute function private.queue_legacy_push();
