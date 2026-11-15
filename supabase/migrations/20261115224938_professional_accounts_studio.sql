-- Prepared only. Requires the existing Business ordering migration; never auto-enrolls sellers.
begin;
create table public.app_professional_applications (
  user_id text not null references public.app_users(id),
  role text not null check(role in ('creator','business')),
  status text not null default 'draft' check(status in ('draft','under_review','needs_changes','approved','declined')),
  public_data jsonb not null default '{}', reviewer_message text not null default '',
  applicant_message text not null default '', version integer not null default 1,
  submitted_at timestamptz, decided_at timestamptz, decided_by text references public.app_users(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  primary key(user_id,role)
);
create index professional_queue on public.app_professional_applications(status,updated_at,user_id,role);
create table public.app_professional_roles (
  user_id text not null references public.app_users(id),
  role text not null check(role in ('creator','business')),
  status text not null check(status in ('active','suspended','removed')),
  public_data jsonb not null, version integer not null default 1,
  approved_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  primary key(user_id,role)
);
create table public.app_professional_audit (
  id uuid primary key, actor_id text not null references public.app_users(id),
  target_id text not null references public.app_users(id), role text not null,
  action text not null, request jsonb not null, result jsonb not null,
  reason text, internal_note text, created_at timestamptz not null default now()
);
create index professional_audit_target on public.app_professional_audit(target_id,role,created_at desc);
create index professional_audit_actor on public.app_professional_audit(actor_id,created_at desc);
create table public.app_studio_handoffs (
  token_hash text primary key check(length(token_hash)=64), user_id text not null references public.app_users(id),
  issued_at timestamptz not null default now(), expires_at timestamptz not null default now()+interval '60 seconds',
  consumed_at timestamptz
);
create table public.app_studio_sessions (
  token_hash text primary key check(length(token_hash)=64), user_id text not null references public.app_users(id),
  issued_at timestamptz not null, expires_at timestamptz not null default now()+interval '1 hour', revoked_at timestamptz
);
create index studio_handoff_expiry on public.app_studio_handoffs(expires_at);
create index studio_session_expiry on public.app_studio_sessions(expires_at);
create index studio_handoff_user on public.app_studio_handoffs(user_id);
create index studio_session_user on public.app_studio_sessions(user_id);
do $$ declare t text; begin
  foreach t in array array['app_professional_applications','app_professional_roles','app_professional_audit','app_studio_handoffs','app_studio_sessions'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on public.%I from public,anon,authenticated',t);
    execute format('grant select,insert,update on public.%I to service_role',t);
  end loop;
end $$;
revoke update on public.app_professional_audit from service_role;

create function public.captro_professional_active(p_user text,p_role text) returns boolean
language sql stable security invoker set search_path='' as $$
  select exists(select 1 from public.app_professional_roles r join public.app_users u on u.id=r.user_id
    where (u.id=p_user or u.supabase_user_id::text=p_user) and r.role=p_role and r.status='active'
    and coalesce(u.metadata->>'status','active')='active');
$$;
create function public.captro_professional_mutate(p_actor text,p_target text,p_role text,p_action text,p_data jsonb,p_id uuid)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare actor public.app_users; application public.app_professional_applications; assigned public.app_professional_roles;
 prior public.app_professional_audit; result jsonb; is_review boolean; is_admin boolean; input jsonb; failure text;
begin
 select * into actor from public.app_users where id=p_actor and coalesce(metadata->>'status','active')='active';
 if actor.id is null or p_role not in ('creator','business') then return jsonb_build_object('error','PROFESSIONAL_FORBIDDEN'); end if;
 is_review:=p_action in ('request_changes','approve','decline','suspend','restore','remove');
 select coalesce(count(distinct role)=1 and bool_and(role in ('owner','admin')),false) into is_admin
   from public.app_admin_roles where user_id in (actor.id,actor.supabase_user_id::text);
 if (is_review and not is_admin) or (not is_review and p_actor<>p_target) then return jsonb_build_object('error','PROFESSIONAL_FORBIDDEN'); end if;
 if not exists(select 1 from public.app_users where id=p_target) then return jsonb_build_object('error','PROFESSIONAL_NOT_FOUND'); end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_target||':'||p_role,0));
 input:=jsonb_build_object('target',p_target,'role',p_role,'action',p_action,'data',p_data);
 select * into prior from public.app_professional_audit where id=p_id;
 if prior.id is not null then
   if prior.actor_id<>p_actor or prior.request<>input then return jsonb_build_object('error','PROFESSIONAL_CONFLICT'); end if;
   return prior.result;
 end if;
 begin
   select * into application from public.app_professional_applications where user_id=p_target and role=p_role for update;
   select * into assigned from public.app_professional_roles where user_id=p_target and role=p_role for update;
   if p_action in ('save','submit') then
     if coalesce(application.status,'draft') not in ('draft','needs_changes','declined') or assigned.user_id is not null then raise exception 'PROFESSIONAL_CONFLICT'; end if;
     if coalesce(application.version,0)<>(p_data->>'version')::integer then raise exception 'PROFESSIONAL_CONFLICT'; end if;
     insert into public.app_professional_applications(user_id,role,status,public_data,applicant_message,submitted_at)
       values(p_target,p_role,case when p_action='submit' then 'under_review' else 'draft' end,p_data->'public',p_data->>'message',case when p_action='submit' then now() end)
     on conflict(user_id,role) do update set status=excluded.status,public_data=excluded.public_data,
       applicant_message=excluded.applicant_message,submitted_at=excluded.submitted_at,version=app_professional_applications.version+1,updated_at=now();
   elsif p_action in ('request_changes','approve','decline') then
     if application.status is distinct from 'under_review' or application.version<>(p_data->>'version')::integer then raise exception 'PROFESSIONAL_CONFLICT'; end if;
     if p_action='approve' and not exists(select 1 from public.app_users where id=p_target and coalesce(metadata->>'status','active')='active') then raise exception 'PROFESSIONAL_FORBIDDEN'; end if;
     update public.app_professional_applications set status=case p_action when 'approve' then 'approved' when 'decline' then 'declined' else 'needs_changes' end,
       reviewer_message=p_data->>'message',decided_by=p_actor,decided_at=now(),updated_at=now(),version=version+1 where user_id=p_target and role=p_role;
     if p_action='approve' then
       insert into public.app_professional_roles(user_id,role,status,public_data) values(p_target,p_role,'active',application.public_data);
     end if;
   elsif p_action='edit_public' then
     if assigned.status is distinct from 'active' then raise exception 'PROFESSIONAL_FORBIDDEN'; end if;
     if assigned.version<>(p_data->>'version')::integer then raise exception 'PROFESSIONAL_CONFLICT'; end if;
     update public.app_professional_roles set public_data=p_data->'public',version=version+1,updated_at=now() where user_id=p_target and role=p_role;
   elsif p_action in ('suspend','restore','remove') then
     if assigned.user_id is null or assigned.version<>(p_data->>'version')::integer then raise exception 'PROFESSIONAL_CONFLICT'; end if;
     if (p_action='suspend' and assigned.status<>'active') or (p_action='remove' and assigned.status='removed') or (p_action='restore' and assigned.status='active') then raise exception 'PROFESSIONAL_CONFLICT'; end if;
     if p_action='restore' and not exists(select 1 from public.app_users where id=p_target and coalesce(metadata->>'status','active')='active') then raise exception 'PROFESSIONAL_FORBIDDEN'; end if;
     update public.app_professional_roles set status=case p_action when 'suspend' then 'suspended' when 'remove' then 'removed' else 'active' end,
       version=version+1,updated_at=now() where user_id=p_target and role=p_role;
   else raise exception 'PROFESSIONAL_INVALID'; end if;
   result:=jsonb_build_object('ok',true);
 exception when others then
   get stacked diagnostics failure=message_text;
   result:=jsonb_build_object('error',case when failure in ('PROFESSIONAL_CONFLICT','PROFESSIONAL_FORBIDDEN','PROFESSIONAL_INVALID') then failure else 'PROFESSIONAL_WRITE_FAILED' end);
 end;
 insert into public.app_professional_audit(id,actor_id,target_id,role,action,request,result,reason,internal_note)
   values(p_id,p_actor,p_target,p_role,p_action,input,result,p_data->>'reason',p_data->>'note');
 return result;
end $$;

create function public.captro_studio_session(p_action text,p_hash text,p_user text default null,p_session_hash text default null)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare handoff public.app_studio_handoffs; session public.app_studio_sessions; actor public.app_users;
begin
 if p_hash !~ '^[a-f0-9]{64}$' then raise exception 'STUDIO_SESSION_INVALID'; end if;
 if p_action='issue' then
   select * into actor from public.app_users where id=p_user and coalesce(metadata->>'status','active')='active';
   if actor.id is null or not exists(select 1 from public.app_professional_roles where user_id=p_user) then raise exception 'PROFESSIONAL_FORBIDDEN'; end if;
   insert into public.app_studio_handoffs(token_hash,user_id) values(p_hash,p_user);
   return jsonb_build_object('expires_in',60);
 elsif p_action='exchange' then
   select * into handoff from public.app_studio_handoffs where token_hash=p_hash for update;
   if handoff.user_id is null or handoff.expires_at<=now() or handoff.consumed_at is not null or p_session_hash !~ '^[a-f0-9]{64}$' then raise exception 'STUDIO_SESSION_INVALID'; end if;
   select * into actor from public.app_users where id=handoff.user_id and coalesce(metadata->>'status','active')='active';
   if actor.id is null or coalesce((actor.metadata->>'session_revoked_at')::timestamptz,'epoch')>=handoff.issued_at then raise exception 'STUDIO_SESSION_INVALID'; end if;
   update public.app_studio_handoffs set consumed_at=now() where token_hash=p_hash;
   insert into public.app_studio_sessions(token_hash,user_id,issued_at) values(p_session_hash,handoff.user_id,handoff.issued_at);
   return jsonb_build_object('expires_in',3600);
 elsif p_action='revoke' then
   update public.app_studio_sessions set revoked_at=now() where token_hash=p_hash;
   return jsonb_build_object('ok',true);
 elsif p_action='resolve' then
   select * into session from public.app_studio_sessions where token_hash=p_hash and revoked_at is null and expires_at>now();
   select * into actor from public.app_users where id=session.user_id and coalesce(metadata->>'status','active')='active';
   if actor.id is null or coalesce((actor.metadata->>'session_revoked_at')::timestamptz,'epoch')>=session.issued_at then raise exception 'STUDIO_SESSION_INVALID'; end if;
   return jsonb_build_object('user_id',actor.id,'issued_at',session.issued_at);
 end if;
 raise exception 'STUDIO_SESSION_INVALID';
end $$;

-- Recheck at the financial insert boundary without changing historical snapshots or payouts.
create function public.captro_professional_purchase_guard() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 if new.content_type='creator_support' and not public.captro_professional_active(new.creator_id::text,'creator') then raise exception 'CAPTRO_SUPPORT_PROFESSIONAL_REQUIRED'; end if;
 return new;
end $$;
create trigger professional_support_guard before insert on public.app_purchases for each row execute function public.captro_professional_purchase_guard();
create function public.captro_professional_business_guard() returns trigger
language plpgsql security invoker set search_path='' as $$
declare owner_id uuid;
begin
 if tg_table_name='app_business_orders' then select b.owner_id into owner_id from public.app_businesses b where b.id=new.business_id;
 elsif tg_table_name='app_business_products' then select b.owner_id into owner_id from public.app_businesses b where b.id=new.business_id;
 else owner_id:=new.owner_id; end if;
 if not public.captro_professional_active(owner_id::text,'business') then raise exception 'PROFESSIONAL_FORBIDDEN'; end if;
 return new;
end $$;
create trigger professional_business_shop before insert or update on public.app_businesses for each row execute function public.captro_professional_business_guard();
create trigger professional_business_product before insert or update on public.app_business_products for each row execute function public.captro_professional_business_guard();
create trigger professional_business_order before insert on public.app_business_orders for each row execute function public.captro_professional_business_guard();
create or replace function public.captro_business_discover(p_lat double precision,p_lon double precision,p_offset integer)
returns jsonb language sql stable security invoker set search_path='' as $$
 select coalesce(jsonb_agg(to_jsonb(b)-'owner_id'-'tax_bps'),'[]') from (
   select b.*,case when p_lat is not null and p_lon is not null then
     3958.76*acos(least(1.,greatest(-1.,sin(radians(p_lat))*sin(radians(b.latitude))+cos(radians(p_lat))*cos(radians(b.latitude))*cos(radians(b.longitude-p_lon))))) end as distance_miles
   from public.app_businesses b where b.published and public.captro_professional_active(b.owner_id::text,'business')
   order by distance_miles nulls last,b.name,b.id limit 30 offset greatest(0,least(p_offset,10000))
 ) b;
$$;
-- Existing order transitions/refunds remain available to the verified owner after role removal.
alter table public.app_businesses add column pickup_instructions text not null default '' check(length(pickup_instructions)<=500);
alter table public.app_business_products add column stock integer check(stock is null or stock>=0);
create function public.captro_business_reserve_stock() returns trigger language plpgsql security invoker set search_path='' as $$
declare line jsonb; quantity integer;
begin
 -- Canonical product order prevents deadlocks between concurrent bags.
 for line in select value from jsonb_array_elements(new.lines) order by value->>'product_id' loop
   quantity:=(line->>'quantity')::integer;
   update public.app_business_products set stock=stock-quantity where id=(line->>'product_id')::uuid and stock>=quantity;
   if not found and exists(select 1 from public.app_business_products where id=(line->>'product_id')::uuid and stock is not null) then raise exception 'PRODUCT_UNAVAILABLE'; end if;
 end loop;
 return new;
end $$;
create trigger business_reserve_stock before insert on public.app_business_orders for each row execute function public.captro_business_reserve_stock();
-- Stock is a reservation at checkout. Cancellation/refund does not silently add prepared food back to stock.
revoke all on function public.captro_professional_active(text,text),public.captro_professional_mutate(text,text,text,text,jsonb,uuid),public.captro_studio_session(text,text,text,text),public.captro_professional_purchase_guard(),public.captro_professional_business_guard(),public.captro_business_reserve_stock() from public,anon,authenticated;
grant execute on function public.captro_professional_active(text,text),public.captro_professional_mutate(text,text,text,text,jsonb,uuid),public.captro_studio_session(text,text,text,text),public.captro_professional_purchase_guard(),public.captro_professional_business_guard(),public.captro_business_reserve_stock() to service_role;
commit;
