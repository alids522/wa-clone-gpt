-- PostgreSQL requires the queue's data-modifying CTE at statement top level.
create or replace function private.claim_push_jobs() returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 delete from private.push_jobs where attempts>=8 or created_at<now()-interval '1 day';
 with due as (
  select id from private.push_jobs where available_at<=now() order by id limit 100 for update skip locked
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
