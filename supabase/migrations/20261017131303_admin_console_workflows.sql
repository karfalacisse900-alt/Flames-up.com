-- PREPARED ONLY. Requires the reviewed backend-write and media boundaries first.
-- Additive: no customer/financial rows are deleted or reinterpreted.
do $$ begin
  if has_table_privilege('authenticated','public.app_users','UPDATE')
    or has_table_privilege('authenticated','public.app_admin_roles','INSERT')
    or has_table_privilege('authenticated','public.app_audit_logs','DELETE') then
    raise exception 'Apply and verify the backend security boundary before the console migration';
  end if;
end $$;
alter table public.app_reports add column if not exists admin_version bigint not null default 0;
alter table public.app_admin_roles add column if not exists admin_version bigint not null default 0;
create table public.app_admin_operations (
  actor_id text not null, id uuid not null, request jsonb not null, result jsonb not null,
  created_at timestamptz not null default now(), primary key(actor_id,id)
);
create table public.app_admin_appeals (
  id uuid primary key default gen_random_uuid(), decision_id text not null references public.app_moderation_actions(id),
  appellant_id text not null, statement text not null check(length(statement) between 3 and 4000),
  status text not null default 'open' check(status in ('open','in_review','upheld','overturned')),
  outcome_notice text, admin_version bigint not null default 0,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(decision_id,appellant_id)
);
create index app_admin_appeals_queue on public.app_admin_appeals(status,created_at desc,id);
create index if not exists app_reports_assigned_queue on public.app_reports(assigned_to,status,created_at desc,id);
alter table public.app_admin_operations enable row level security;
alter table public.app_admin_appeals enable row level security;
revoke all on public.app_admin_operations,public.app_admin_appeals from public,anon,authenticated;
grant select,insert,update on public.app_admin_operations,public.app_admin_appeals to service_role;

create or replace function public.captro_admin_execute(p_actor text,p_request jsonb)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  op uuid := (p_request->>'id')::uuid; act text := p_request->>'action'; target text := p_request->>'target';
  role_name text; actor_status text; previous public.app_admin_operations%rowtype;
  r public.app_reports%rowtype; u public.app_users%rowtype; a public.app_admin_appeals%rowtype;
  v bigint; result jsonb; code text; reason text := btrim(p_request->>'reason');
  note text := coalesce(p_request->>'note',''); stamp timestamptz := clock_timestamp();
  after_value jsonb := '{}'::jsonb; target_kind text; required_role boolean; expires timestamptz;
begin
  -- Serializes role changes before row locks, including last-owner checks.
  if act='role' then perform pg_advisory_xact_lock(hashtextextended('captro-admin-roles',0)); end if;
  select ar.role,coalesce(au.metadata->>'status','active') into role_name,actor_status
    from app_admin_roles ar join app_users au on au.id=ar.user_id
    where ar.user_id=p_actor for share of ar,au;
  if role_name is null or actor_status<>'active' then return jsonb_build_object('ok',false,'code','FORBIDDEN'); end if;
  perform pg_advisory_xact_lock(hashtextextended(p_actor||':'||op::text,0));
  select * into previous from app_admin_operations where actor_id=p_actor and id=op;
  if found then
    if previous.request<>p_request then return jsonb_build_object('ok',false,'code','IDEMPOTENCY_CONFLICT'); end if;
    return previous.result;
  end if;
  begin
    if coalesce(length(reason),0) not between 3 and 800 or length(note)>2000 then raise exception 'INVALID_REASON'; end if;
    if coalesce(p_request->>'version','') !~ '^[0-9]+$' then raise exception 'STALE_VERSION'; end if;
    required_role := case
      when act in ('note','assign','review','dismiss','escalate','resolve','duplicate','warn','restrict','appeal_review','appeal_uphold') then role_name in ('owner','admin','moderator')
      when act in ('suspend','ban','reinstate') then role_name in ('owner','admin')
      when act='role' then role_name='owner'
      else false end;
    if not required_role then raise exception 'FORBIDDEN'; end if;
    if act in ('note','assign','review','dismiss','escalate','resolve','duplicate') then
      target_kind:='report'; select * into r from app_reports where id=target for update;
      if not found then raise exception 'NOT_FOUND'; end if;
      if r.admin_version<>(p_request->>'version')::bigint then raise exception 'STALE_VERSION'; end if;
      if act='assign' and nullif(p_request->>'assignee','') is not null and not exists(
        select 1 from app_admin_roles ar join app_users au on au.id=ar.user_id
        where ar.user_id=p_request->>'assignee' and ar.role in ('owner','admin','moderator') and coalesce(au.metadata->>'status','active')='active'
      ) then raise exception 'INVALID_ASSIGNEE'; end if;
      if act='duplicate' and (target=p_request->>'duplicate_of' or not exists(select 1 from app_reports where id=p_request->>'duplicate_of' and target_type=r.target_type and target_id=r.target_id)) then raise exception 'INVALID_DUPLICATE'; end if;
      r.status:=case act when 'review' then 'under_review' when 'dismiss' then 'dismissed' when 'escalate' then 'escalated' when 'resolve' then 'action_taken' else r.status end;
      -- Resolution is a case disposition, NOT a content removal or entitlement mutation.
      if act='assign' then r.assigned_to:=nullif(p_request->>'assignee',''); end if;
      if act='duplicate' then r.metadata:=r.metadata||jsonb_build_object('duplicate_of',p_request->>'duplicate_of'); end if;
      if act='note' then
        if length(note)<1 then raise exception 'NOTE_REQUIRED'; end if;
        r.metadata:=r.metadata||jsonb_build_object('internal_notes',coalesce(r.metadata->'internal_notes','[]'::jsonb)||jsonb_build_array(jsonb_build_object('id',op,'note',note,'admin_id',p_actor,'created_at',stamp)));
      end if;
      update app_reports set status=r.status,assigned_to=r.assigned_to,metadata=r.metadata,reviewed_by=p_actor,
        closed_at=case when r.status in ('dismissed','action_taken') then stamp else null end,
        updated_at=stamp,admin_version=admin_version+1 where id=target;
      after_value:=jsonb_build_object('status',r.status,'assigned_to',r.assigned_to,'version',r.admin_version+1);
    elsif act in ('warn','restrict','suspend','ban','reinstate') then
      target_kind:='user'; select * into u from app_users where id=target for update;
      if not found then raise exception 'NOT_FOUND'; end if;
      if target=p_actor or exists(select 1 from app_admin_roles where user_id=target) then raise exception 'PROTECTED_ADMIN'; end if;
      v:=coalesce((u.metadata->>'admin_version')::bigint,0);
      if v<>(p_request->>'version')::bigint then raise exception 'STALE_VERSION'; end if;
      if coalesce(u.metadata->>'status','active') in ('deleted','deletion_pending') then raise exception 'ACCOUNT_UNAVAILABLE'; end if;
      if act in ('restrict','suspend') then
        if coalesce((p_request->>'hours')::int,0) not between 1 and 2160 then raise exception 'INVALID_DURATION'; end if;
        expires:=stamp+make_interval(hours=>(p_request->>'hours')::int);
      end if;
      if act='warn' then u.metadata:=u.metadata||jsonb_build_object('warning_count',coalesce((u.metadata->>'warning_count')::int,0)+1,'last_warning_reason',reason); end if;
      if act='restrict' then
        if coalesce(p_request->>'scope','') not in ('posting','commenting','messaging','commerce','all') then raise exception 'INVALID_SCOPE'; end if;
        u.metadata:=u.metadata||jsonb_build_object('restrictions',coalesce(u.metadata->'restrictions','[]'::jsonb)||jsonb_build_array(jsonb_build_object('id',op,'restriction_type',p_request->>'scope','reason',reason,'starts_at',stamp,'ends_at',expires,'created_by',p_actor)));
      end if;
      if act='suspend' then u.metadata:=u.metadata||jsonb_build_object('status','suspended','suspended_until',expires,'ban_reason',reason); end if;
      if act='ban' then u.metadata:=u.metadata||jsonb_build_object('status','banned','banned_at',stamp,'ban_reason',reason,'session_revoked_at',stamp); end if;
      if act='reinstate' then u.metadata:=(u.metadata-'suspended_until'-'banned_at'-'ban_reason')||jsonb_build_object('status','active'); end if;
      -- Revocation markers intentionally survive reinstatement.
      update app_users set metadata=u.metadata||jsonb_build_object('admin_version',v+1),updated_at=stamp where id=target;
      after_value:=jsonb_build_object('status',coalesce(u.metadata->>'status','active'),'version',v+1,'scope',p_request->>'scope','expires_at',expires);
      insert into app_notifications(id,user_id,type,title,body,data) values(op::text,target,'moderation_notice','Account safety update',reason,jsonb_build_object('decision_id',op,'action',act));
    elsif act='role' then
      target_kind:='admin_access';
      if not exists(select 1 from app_users where id=target and coalesce(metadata->>'status','active')='active') then raise exception 'NOT_FOUND'; end if;
      select admin_version into v from app_admin_roles where user_id=target for update;
      if coalesce(v,0)<>(p_request->>'version')::bigint then raise exception 'STALE_VERSION'; end if;
      if p_request->>'role' not in ('owner','moderator','support','none') then raise exception 'INVALID_ROLE'; end if;
      -- A disabled or orphaned owner is not a usable fallback for account recovery.
      if p_request->>'role'<>'owner' and exists(select 1 from app_admin_roles where user_id=target and role='owner')
        and (select count(*) from app_admin_roles ar join app_users au on au.id=ar.user_id
          where ar.role='owner' and coalesce(au.metadata->>'status','active')='active')<=1
        then raise exception 'LAST_OWNER'; end if;
      if p_request->>'role'='none' then delete from app_admin_roles where user_id=target;
      else insert into app_admin_roles(user_id,role,created_by,admin_version) values(target,p_request->>'role',p_actor,coalesce(v,0)+1)
        on conflict(user_id) do update set role=excluded.role,admin_version=excluded.admin_version,updated_at=stamp; end if;
      after_value:=jsonb_build_object('role',p_request->>'role','version',coalesce(v,0)+1);
    elsif act in ('appeal_review','appeal_uphold') then
      target_kind:='appeal'; select * into a from app_admin_appeals where id=target::uuid for update;
      if not found then raise exception 'NOT_FOUND'; end if;
      if a.admin_version<>(p_request->>'version')::bigint then raise exception 'STALE_VERSION'; end if;
      if exists(select 1 from app_moderation_actions where id=a.decision_id and actor_admin_user_id=p_actor) then raise exception 'INDEPENDENT_REVIEW_REQUIRED'; end if;
      if a.status not in ('open','in_review') then raise exception 'APPEAL_CLOSED'; end if;
      update app_admin_appeals set status=case when act='appeal_uphold' then 'upheld' else 'in_review' end,
        outcome_notice=case when act='appeal_uphold' then reason else null end,admin_version=admin_version+1,updated_at=stamp where id=a.id;
      after_value:=jsonb_build_object('status',case when act='appeal_uphold' then 'upheld' else 'in_review' end,'version',a.admin_version+1);
      if act='appeal_uphold' then insert into app_notifications(id,user_id,type,title,body,data) values(op::text,a.appellant_id,'appeal_outcome','Appeal reviewed',reason,jsonb_build_object('appeal_id',a.id)); end if;
    end if;
    result:=jsonb_build_object('ok',true,'id',op,'outcome',after_value);
  exception when others then
    code:=case when sqlerrm in ('FORBIDDEN','NOT_FOUND','STALE_VERSION','INVALID_REASON','NOTE_REQUIRED','INVALID_ASSIGNEE','INVALID_DUPLICATE','PROTECTED_ADMIN','INVALID_DURATION','INVALID_SCOPE','ACCOUNT_UNAVAILABLE','INVALID_ROLE','LAST_OWNER','INDEPENDENT_REVIEW_REQUIRED','APPEAL_CLOSED') then sqlerrm else 'OPERATION_FAILED' end;
    result:=jsonb_build_object('ok',false,'id',op,'code',code);
  end;
  -- Failures are committed too; internal errors/credentials never enter audit details.
  insert into app_admin_operations(actor_id,id,request,result) values(p_actor,op,p_request,result);
  insert into app_audit_logs(id,actor_admin_user_id,actor_role,action_type,target_type,target_id,reason,internal_note,after_state,request_id,metadata)
    values(op::text,p_actor,role_name,'console_'||act,coalesce(target_kind,'unknown'),target,coalesce(reason,''),note,after_value,op::text,jsonb_build_object('result',result));
  if result->>'ok'='true' then
    insert into app_moderation_actions(id,actor_admin_user_id,actor_role,action_type,target_type,target_id,target_user_id,reason,note,metadata)
      values(op::text,p_actor,role_name,'console_'||act,target_kind,target,case when target_kind='user' then target end,reason,note,after_value);
  end if;
  return result;
end $$;
revoke all on function public.captro_admin_execute(text,jsonb) from public,anon,authenticated;
grant execute on function public.captro_admin_execute(text,jsonb) to service_role;

-- An appeal may only reference the caller's own decision; no internal notes returned.
create or replace function public.captro_submit_appeal(p_user text,p_decision text,p_statement text)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare result uuid;
begin
  if length(btrim(p_statement)) not between 3 and 4000 then raise exception 'INVALID_STATEMENT'; end if;
  if not exists(select 1 from app_moderation_actions where id=p_decision and target_user_id=p_user) then raise exception 'FORBIDDEN'; end if;
  insert into app_admin_appeals(decision_id,appellant_id,statement) values(p_decision,p_user,p_statement)
    on conflict(decision_id,appellant_id) do nothing returning id into result;
  if result is null then select id into result from app_admin_appeals where decision_id=p_decision and appellant_id=p_user; end if;
  return result;
end $$;
revoke all on function public.captro_submit_appeal(text,text,text) from public,anon,authenticated;
grant execute on function public.captro_submit_appeal(text,text,text) to service_role;
