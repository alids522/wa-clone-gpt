-- Only encrypted history archives and password-wrapped random archive keys.
-- Device identities and Signal ratchets are deliberately never restored.
create table private.history_keys (
 user_id uuid primary key references auth.users on delete cascade,
 key_id uuid not null, salt text not null, iterations int not null,
 wrapped jsonb not null, revision int not null default 1,
 updated_at timestamptz not null default now()
);
create table private.history_archives (
 user_id uuid not null references auth.users on delete cascade,
 device_id uuid not null, key_id uuid not null, ciphertext text not null, source_revision bigint not null,
 updated_at timestamptz not null default now(), primary key(user_id,device_id)
);
alter table private.history_keys enable row level security;
alter table private.history_archives enable row level security;
revoke all on private.history_keys,private.history_archives from public,anon,authenticated;

create function private.history_backup(device uuid,operation text,payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare k private.history_keys; uid uuid:=auth.uid(); total bigint;
begin
 if not private.owns_device(device) then raise insufficient_privilege; end if;
 perform pg_advisory_xact_lock(hashtextextended(uid::text,52291));
 select * into k from private.history_keys where user_id=uid;
 if operation in('key','rekey') then
  if payload->>'algorithm' is distinct from 'pbkdf2-sha256-aes256gcm-v1'
   or (payload->>'iterations')::int is distinct from 600000
   or length(payload->>'salt') is distinct from 24
   or jsonb_typeof(payload->'wrapped') is distinct from 'object'
   or length(payload->'wrapped'->>'nonce') is distinct from 16
   or length(payload->'wrapped'->>'mac') is distinct from 24
   or length(payload->'wrapped'->>'ciphertext') is distinct from 44
   or payload->>'key_id' is null
  then raise exception 'Invalid key envelope'; end if;
  if operation='key' and k.user_id is null then
   insert into private.history_keys(user_id,key_id,salt,iterations,wrapped)
    values(uid,(payload->>'key_id')::uuid,payload->>'salt',600000,payload->'wrapped') returning * into k;
  elsif operation='rekey' then
   if k.user_id is null or k.key_id is distinct from (payload->>'key_id')::uuid or k.revision is distinct from (payload->>'revision')::int
    then raise exception 'Backup key changed; unlock again' using errcode='40001'; end if;
   update private.history_keys set salt=payload->>'salt',wrapped=payload->'wrapped',
    revision=revision+1,updated_at=now() where user_id=uid returning * into k;
  end if;
 elsif operation='save' then
  if k.user_id is null or k.key_id is distinct from (payload->>'key_id')::uuid then raise exception 'Unlock backup first'; end if;
  if payload->>'ciphertext' is null or length(payload->>'ciphertext') not between 40 and 16000000
   or payload->>'ciphertext' !~ '^[A-Za-z0-9+/=]+$' then raise exception 'Invalid archive'; end if;
  if not exists(select 1 from private.history_archives where user_id=uid and device_id=device)
    and (select count(*) from private.history_archives where user_id=uid)>=20
   then raise exception 'Archive device limit reached'; end if;
  select coalesce(sum(length(ciphertext)),0) into total from private.history_archives where user_id=uid and device_id<>device;
  if total+length(payload->>'ciphertext')>100000000 then raise exception 'Archive quota reached'; end if;
  if coalesce((payload->>'source_revision')::bigint,-1)<0 then raise exception 'Invalid archive revision'; end if;
  insert into private.history_archives(user_id,device_id,key_id,ciphertext,source_revision)
   values(uid,device,k.key_id,payload->>'ciphertext',(payload->>'source_revision')::bigint)
   on conflict(user_id,device_id) do update set ciphertext=excluded.ciphertext,key_id=excluded.key_id,
    source_revision=excluded.source_revision,updated_at=now()
   where private.history_archives.source_revision<excluded.source_revision;
  return (select jsonb_build_object('saved_at',updated_at) from private.history_archives where user_id=uid and device_id=device);
 elsif operation<>'get' then raise exception 'Unknown backup operation'; end if;
 return jsonb_build_object('key',case when k.user_id is null then null else
  jsonb_build_object('key_id',k.key_id,'salt',k.salt,'iterations',k.iterations,'wrapped',k.wrapped,'revision',k.revision,
   'algorithm','pbkdf2-sha256-aes256gcm-v1') end,
  'archives',case when operation='get' then coalesce((select jsonb_agg(jsonb_build_object(
   'device_id',a.device_id,'ciphertext',a.ciphertext,'updated_at',a.updated_at))
   from private.history_archives a where a.user_id=uid),'[]'::jsonb) else '[]'::jsonb end);
end $$;
create function public.history_backup(device uuid,operation text,payload jsonb default null) returns jsonb
 language sql security invoker set search_path='' as $$select private.history_backup(device,operation,payload)$$;
revoke all on function private.history_backup(uuid,text,jsonb),public.history_backup(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function private.history_backup(uuid,text,jsonb),public.history_backup(uuid,text,jsonb) to authenticated;

-- Close ringing UIs on the other devices when a call is answered or finishes.
alter table private.push_jobs drop constraint push_jobs_kind_check;
alter table private.push_jobs add constraint push_jobs_kind_check check(kind in('message','call','call_end'));
create function private.call_status_push() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.status is distinct from old.status and new.status<>'ringing' then
  insert into private.push_jobs(device_id,event_id,kind)
   select d.id,new.id,'call_end' from public.account_devices d
   join public.conversations c on c.id=new.conversation_id and d.user_id in(c.member_a,c.member_b)
   where d.revoked_at is null and (new.status not in('connecting','connected')
    or (d.user_id<>new.caller_id and d.id is distinct from new.callee_device))
   on conflict(device_id,event_id,kind) do update set available_at=now(),attempts=0,created_at=now();
 end if;
 return new;
end $$;
revoke all on function private.call_status_push() from public,anon,authenticated;
create trigger adoetz_call_status_push after update of status on public.calls for each row execute function private.call_status_push();

-- Expire durable call logs even when both applications are closed.
create or replace function private.claim_push_jobs() returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 update public.calls set status=case when status='ringing' then 'missed' else 'failed' end,
  ended_at=expires_at,reason='timeout' where expires_at<now() and status in('ringing','connecting','connected');
 delete from private.push_jobs where attempts>=8 or created_at<now()-interval '1 day';
 with due as (
  select id from private.push_jobs where available_at<=now()
   order by case when kind='call_end' then 0 when kind='call' then 1 else 2 end,id limit 100 for update skip locked
 ), claimed as (
  update private.push_jobs j set attempts=attempts+1,
   available_at=now()+least(interval '10 minutes',interval '5 seconds'*power(2,attempts))
  from due where j.id=due.id returning j.*
 )
 select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('token',t.token)),'[]'::jsonb)
 into result from claimed c join private.device_push_tokens t using(device_id)
 join public.account_devices d on d.id=c.device_id and d.revoked_at is null
 join private.accounts a on a.id=d.user_id and a.status='active';
 return result;
end $$;
notify pgrst,'reload schema';
