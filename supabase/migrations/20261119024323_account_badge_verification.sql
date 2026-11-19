begin;
create table public.app_badge_applications (
 user_id text primary key references public.app_users(id),
 status text not null check(status in ('under_review','needs_changes','approved','declined','revoked')),
 display_name text not null, reason text not null, links jsonb not null default '[]',
 reviewer_message text not null default '', version integer not null default 1,
 submitted_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 decided_at timestamptz, decided_by text references public.app_users(id)
);
create index badge_review_queue on public.app_badge_applications(status,updated_at,user_id);
create table public.app_badge_audit (
 id uuid primary key, actor_id text not null references public.app_users(id),
 target_id text not null references public.app_users(id), action text not null,
 request jsonb not null, result jsonb not null, created_at timestamptz not null default now()
);
create index badge_audit_target on public.app_badge_audit(target_id,created_at desc);
alter table public.app_badge_applications enable row level security;
alter table public.app_badge_audit enable row level security;
revoke all on public.app_badge_applications,public.app_badge_audit from public,anon,authenticated;
grant select,insert,update on public.app_badge_applications to service_role;
grant select,insert on public.app_badge_audit to service_role;

create function public.captro_badge_mutate(p_actor text,p_target text,p_action text,p_id uuid,p_data jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare actor public.app_users; item public.app_badge_applications; prior public.app_badge_audit;
 input jsonb; result jsonb; admin_ok boolean; next_status text;
begin
 select * into actor from public.app_users where id=p_actor and coalesce(metadata->>'status','active')='active';
 if actor.id is null then raise exception 'BADGE_FORBIDDEN'; end if;
 if p_action not in ('submit','approve','request_changes','decline','revoke') or p_id is null
   or jsonb_typeof(p_data)<>'object' or coalesce(p_data->>'version','') !~ '^[0-9]+$' then raise exception 'BADGE_INVALID'; end if;
 select coalesce(count(distinct role)=1 and bool_and(role in ('owner','admin')),false) into admin_ok
   from public.app_admin_roles where user_id in (actor.id,actor.supabase_user_id::text);
 if (p_action='submit' and p_actor<>p_target) or (p_action<>'submit' and (not admin_ok or p_actor=p_target)) then raise exception 'BADGE_FORBIDDEN'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('badge:'||p_target,0));
 input:=jsonb_build_object('target',p_target,'action',p_action,'data',p_data);
 select * into prior from public.app_badge_audit where id=p_id;
 if prior.id is not null then
   if prior.actor_id<>p_actor or prior.request<>input then raise exception 'BADGE_CONFLICT'; end if;
   return prior.result;
 end if;
 if not exists(select 1 from public.app_users where id=p_target and (p_action='revoke' or coalesce(metadata->>'status','active')='active')) then raise exception 'BADGE_FORBIDDEN'; end if;
 select * into item from public.app_badge_applications where user_id=p_target for update;
 if coalesce(item.version,0)<>(p_data->>'version')::integer then raise exception 'BADGE_CONFLICT'; end if;
 if p_action='submit' then
   if coalesce(item.status,'declined') not in ('needs_changes','declined','revoked') then raise exception 'BADGE_CONFLICT'; end if;
   if length(trim(coalesce(p_data->>'displayName',''))) not between 1 and 120
     or length(trim(coalesce(p_data->>'reason',''))) not between 10 and 1500
     or jsonb_typeof(p_data->'links') is distinct from 'array' then raise exception 'BADGE_INVALID'; end if;
   if jsonb_array_length(p_data->'links')>3 or exists(select 1 from jsonb_array_elements_text(p_data->'links') l where length(l)>2048 or l !~ '^https://') then raise exception 'BADGE_INVALID'; end if;
   insert into public.app_badge_applications(user_id,status,display_name,reason,links)
     values(p_target,'under_review',p_data->>'displayName',p_data->>'reason',p_data->'links')
   on conflict(user_id) do update set status='under_review',display_name=excluded.display_name,reason=excluded.reason,links=excluded.links,
     reviewer_message='',submitted_at=now(),updated_at=now(),decided_at=null,decided_by=null,version=app_badge_applications.version+1;
 else
   if (p_action='revoke' and item.status is distinct from 'approved') or
     (p_action<>'revoke' and item.status is distinct from 'under_review') then raise exception 'BADGE_CONFLICT'; end if;
   if length(trim(coalesce(p_data->>'message',''))) not between 3 and 1500 or length(coalesce(p_data->>'note',''))>2000 then raise exception 'BADGE_INVALID'; end if;
   next_status:=case p_action when 'approve' then 'approved' when 'request_changes' then 'needs_changes' when 'decline' then 'declined' else 'revoked' end;
   update public.app_badge_applications set status=next_status,reviewer_message=p_data->>'message',version=version+1,
     decided_at=now(),decided_by=p_actor,updated_at=now() where user_id=p_target;
   if p_action in ('approve','revoke') then update public.app_users set is_verified=(p_action='approve') where id=p_target; end if;
 end if;
 result:=jsonb_build_object('ok',true);
 insert into public.app_badge_audit(id,actor_id,target_id,action,request,result) values(p_id,p_actor,p_target,p_action,input,result);
 return result;
end $$;
revoke all on function public.captro_badge_mutate(text,text,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.captro_badge_mutate(text,text,text,uuid,jsonb) to service_role;
commit;
