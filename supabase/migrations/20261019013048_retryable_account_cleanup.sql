begin;
-- Cleanup ownership and checkpoints survive Worker restarts. No client access.
create table public.app_account_cleanup_jobs (
  user_id text primary key references public.app_users(id),
  auth_user_id uuid,
  phase integer not null default 0 check(phase between 0 and 5),
  attempt_count integer not null default 0,
  lease_token uuid,
  lease_until timestamptz,
  next_attempt_at timestamptz not null default now(),
  last_error text,
  needs_attention boolean not null default false,
  completed_at timestamptz,
  updated_at timestamptz not null default now()
);
alter table public.app_account_cleanup_jobs enable row level security;
revoke all on public.app_account_cleanup_jobs from public,anon,authenticated;
grant select,insert,update on public.app_account_cleanup_jobs to service_role;

create function public.captro_claim_account_cleanup(p_user text)
returns public.app_account_cleanup_jobs language plpgsql set search_path=public,pg_temp as $$
declare u app_users%rowtype; j app_account_cleanup_jobs%rowtype;
begin
  select * into u from app_users where id=p_user for update;
  if not found or u.metadata->>'status'<>'deletion_pending'
    or coalesce((u.metadata->>'deletion_scheduled_at')::timestamptz,'infinity')>now() then return null; end if;
  insert into app_account_cleanup_jobs(user_id,auth_user_id) values(u.id,u.supabase_user_id) on conflict do nothing;
  select * into j from app_account_cleanup_jobs where user_id=p_user for update;
  if j.completed_at is not null or j.lease_until>now() or j.next_attempt_at>now() then return null; end if;
  update app_account_cleanup_jobs set lease_token=gen_random_uuid(),lease_until=now()+interval '10 minutes',
    attempt_count=attempt_count+1,updated_at=now() where user_id=p_user returning * into j;
  update app_users set metadata=metadata||jsonb_build_object('permanent_cleanup_started_at',coalesce(metadata->>'permanent_cleanup_started_at',now()::text)) where id=p_user;
  return j;
end $$;

create function public.captro_checkpoint_account_cleanup(p_user text,p_token uuid,p_phase integer,p_error text default null)
returns boolean language plpgsql set search_path=public,pg_temp as $$
declare j app_account_cleanup_jobs%rowtype;
begin
  select * into j from app_account_cleanup_jobs where user_id=p_user for update;
  if not found or j.lease_token is distinct from p_token or j.lease_until<=now() or j.completed_at is not null then return false; end if;
  if p_phase<j.phase or p_phase>j.phase+1 or p_phase>5 then raise exception 'INVALID_CLEANUP_PHASE'; end if;
  if p_phase=5 and p_error is null then
    update app_users set supabase_user_id=null,email=null,phone=null,phone_verified=false,email_verified=false,
      username='deleted_'||substr(id,1,12),full_name='Deleted user',avatar_url=null,cover_url=null,bio='',city='',
      is_private=true,is_verified=false,profile='{}',counts='{}',
      metadata=jsonb_build_object('status','deleted','permanent_deletion_completed_at',now(),'session_revoked_at',now()),updated_at=now()
      where id=p_user and metadata->>'status'='deletion_pending';
    if not found then raise exception 'CLEANUP_ACCOUNT_STATE_CHANGED'; end if;
  end if;
  update app_account_cleanup_jobs set phase=p_phase,lease_token=null,lease_until=null,
    next_attempt_at=now()+case when p_error is null then interval '0 minutes' else interval '1 hour' end,
    last_error=left(p_error,80),needs_attention=p_error is not null,
    completed_at=case when p_phase=5 and p_error is null then now() else null end,
    auth_user_id=case when p_phase=5 and p_error is null then null else auth_user_id end,updated_at=now() where user_id=p_user;
  return true;
end $$;

-- Restoration and cleanup serialize on the same account row.
create function public.captro_restore_pending_account(p_user text)
returns boolean language plpgsql set search_path=public,pg_temp as $$
declare u app_users%rowtype;
begin
  select * into u from app_users where id=p_user for update;
  if not found or u.metadata->>'status'<>'deletion_pending' then return false; end if;
  if u.metadata ? 'permanent_cleanup_started_at' then raise exception 'CLEANUP_ALREADY_STARTED'; end if;
  update app_users set metadata=(metadata-'deletion_requested_at'-'deletion_scheduled_at')||jsonb_build_object('status','active'),updated_at=now() where id=p_user;
  -- Keep token-revocation history; restoring the account does not revive old sessions.
  return true;
end $$;
revoke all on function public.captro_claim_account_cleanup(text),public.captro_checkpoint_account_cleanup(text,uuid,integer,text),public.captro_restore_pending_account(text) from public,anon,authenticated;
grant execute on function public.captro_claim_account_cleanup(text),public.captro_checkpoint_account_cleanup(text,uuid,integer,text),public.captro_restore_pending_account(text) to service_role;
commit;
