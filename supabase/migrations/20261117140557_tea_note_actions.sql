-- Additive Notes metadata. Existing conversation IDs, replies and RPCs remain.
begin;
alter table public.app_tea_conversations add column borough text
 check(borough in ('Brooklyn','Queens','Manhattan','Bronx','Staten Island'));
alter table public.app_tea_conversations add column primary_action jsonb
 check(primary_action is null or jsonb_typeof(primary_action)='object');

create table public.app_tea_applications (
 id uuid primary key,
 note_id uuid not null references public.app_tea_conversations(id) on delete cascade,
 applicant_id text not null references public.app_users(id) on delete cascade,
 recipient_id text not null references public.app_users(id) on delete cascade,
 note_version integer not null,
 answers jsonb not null check(jsonb_typeof(answers)='object'),
 created_at timestamptz not null default now(),
 unique(note_id,applicant_id)
);
create index tea_applications_recipient on public.app_tea_applications(recipient_id,note_id,created_at desc,id desc);
create index tea_applications_applicant on public.app_tea_applications(applicant_id);
alter table public.app_tea_applications enable row level security;
revoke all on public.app_tea_applications from public,anon,authenticated;
grant select,insert,delete on public.app_tea_applications to service_role;

create function public.captro_tea_note_capabilities(p_actor text) returns jsonb
language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('canCreateForms',
   public.captro_professional_active(p_actor,'creator') or public.captro_professional_active(p_actor,'business'))
$$;

create function public.captro_tea_note_fields(p public.app_tea_conversations,p_viewer text) returns jsonb
language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('borough',p.borough,'primaryAction',case when p.primary_action is null then null
   else p.primary_action || jsonb_build_object('state',case
     when p.primary_action->>'kind'='application' and not
       ((public.captro_tea_note_capabilities(p.author_id)->>'canCreateForms')::boolean) then 'unavailable'
     when p.primary_action->>'kind'='application' and not (p.primary_action->>'accepting')::boolean then 'closed'
     when p.primary_action->>'kind'='listing' then 'checking'
     else 'active' end) end,
   'applicationSubmitted',exists(select 1 from public.app_tea_applications a where a.note_id=p.id and a.applicant_id=p_viewer),
   'canManageApplications',p.author_id=p_viewer and (p.primary_action->>'kind'='application'
     or exists(select 1 from public.app_tea_applications a where a.note_id=p.id and a.recipient_id=p_viewer)))
$$;

create or replace function public.captro_tea_post_json(p public.app_tea_conversations,p_viewer text) returns jsonb
language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('id',p.id,'title',p.title,'body',p.body,'links',p.links,'version',p.version,
   'createdAt',p.created_at,'author',jsonb_build_object('id',u.id,'name',coalesce(nullif(u.full_name,''),nullif(u.username,''),'Captro member'),'username',coalesce(u.username,'')),
   'replyCount',(select count(*) from public.app_tea_replies r where r.conversation_id=p.id and r.status='active' and public.captro_tea_author_visible(p_viewer,r.author_id)),
   'replyTargets',coalesce((select jsonb_agg(t.value order by (t.value->'target'->>'version')::integer,(t.value->'target'->>'start')::integer) from (select jsonb_build_object('target',r.target,'count',count(*)) value
     from public.app_tea_replies r where r.conversation_id=p.id and r.target is not null and r.status='active'
     and public.captro_tea_author_visible(p_viewer,r.author_id) group by r.target) t),'[]'),
   'isAuthor',u.id=p_viewer,'following',exists(select 1 from public.app_tea_follows f where f.conversation_id=p.id and f.user_id=p_viewer))
   || public.captro_tea_note_fields(p,p_viewer)
 from public.app_users u where u.id=p.author_id
$$;

-- Called only by the authenticated Worker. The old writer remains intact for
-- old clients; it never writes these columns and therefore preserves actions.
create function public.captro_tea_note_write(p_actor text,p_action text,p_id uuid,p_data jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare prior public.app_tea_conversations; item public.app_tea_conversations;
 area text; action jsonb; changed boolean; result jsonb;
begin
 if p_action not in ('create','edit') then raise exception 'TEA_NOTE_INVALID'; end if;
 perform 1 from public.app_users where id=p_actor and coalesce(metadata->>'status','active')='active' for update;
 if not found then raise exception 'TEA_DISCUSSION_FORBIDDEN'; end if;
 select * into prior from public.app_tea_conversations where id=p_id for update;
 if prior.id is not null and prior.author_id<>p_actor then raise exception 'TEA_DISCUSSION_FORBIDDEN'; end if;
 area:=case when p_data ? 'borough' then p_data->>'borough' else prior.borough end;
 action:=case when p_data ? 'primaryAction' then nullif(p_data->'primaryAction','null'::jsonb) else prior.primary_action end;
 if area is not null and area not in ('Brooklyn','Queens','Manhattan','Bronx','Staten Island') then raise exception 'TEA_NOTE_INVALID'; end if;
 if action is not null then
   if jsonb_typeof(action)<>'object' or not (action ?& array['kind','label']) or
      jsonb_typeof(action->'kind') is distinct from 'string' or action->>'kind' not in ('external','application','listing') or
      jsonb_typeof(action->'label')<>'string' or length(btrim(action->>'label')) not between 1 and 40 or
      exists(select 1 from jsonb_object_keys(action) k where k not in ('kind','label','url','listingId','heightRequested','accepting'))
     then raise exception 'TEA_NOTE_INVALID'; end if;
   if action->>'kind'='external' then
     if action->>'url' is null or length(action->>'url')>2048 or action->>'url' !~ '^https://[^[:space:]@]+\.[^[:space:]]+$'
       or action ?| array['listingId','heightRequested','accepting'] then raise exception 'TEA_NOTE_INVALID'; end if;
   elsif action->>'kind'='listing' then
     if action->>'listingId' is null or action->>'listingId' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       or action ?| array['url','heightRequested','accepting'] then raise exception 'TEA_NOTE_INVALID'; end if;
   else
     if jsonb_typeof(action->'heightRequested') is distinct from 'boolean' or jsonb_typeof(action->'accepting') is distinct from 'boolean'
       or action ?| array['url','listingId'] then raise exception 'TEA_NOTE_INVALID'; end if;
     -- A role suspension closes new applications without destroying prior ones.
     if (prior.primary_action is distinct from action or prior.id is null)
       and not (public.captro_tea_note_capabilities(p_actor)->>'canCreateForms')::boolean
       and not coalesce((prior.primary_action->>'kind'='application' and (action->>'accepting')::boolean=false
         and (prior.primary_action-'accepting')=(action-'accepting')),false) then raise exception 'TEA_NOTE_FORM_APPROVAL_REQUIRED'; end if;
   end if;
 end if;
 changed:=prior.borough is distinct from area or prior.primary_action is distinct from action;
 if prior.id is not null then
   if p_action='create' and changed then raise exception 'TEA_DISCUSSION_CONFLICT'; end if;
   if p_action='edit' and changed and prior.version is distinct from (p_data->>'version')::integer then raise exception 'TEA_DISCUSSION_CONFLICT'; end if;
 end if;
 result:=public.captro_tea_write(p_actor,p_action,p_id,p_data);
 select * into item from public.app_tea_conversations where id=p_id;
 if changed then
   update public.app_tea_conversations set borough=area,primary_action=action,
     version=case when p_action='edit' and version=prior.version then version+1 else version end,updated_at=now()
     where id=p_id returning * into item;
 end if;
 return public.captro_tea_post_json(item,p_actor);
end $$;

create function public.captro_tea_note_apply(p_actor text,p_id uuid,p_request uuid,p_version integer,p_answers jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare item public.app_tea_conversations; previous public.app_tea_applications; answer text;
begin
 perform 1 from public.app_users where id=p_actor and coalesce(metadata->>'status','active')='active' for update;
 if not found then raise exception 'TEA_DISCUSSION_FORBIDDEN'; end if;
 select * into item from public.app_tea_conversations where id=p_id and status='active' for update;
 if item.id is null or not public.captro_tea_author_visible(p_actor,item.author_id) then raise exception 'TEA_DISCUSSION_UNAVAILABLE'; end if;
 if item.author_id=p_actor then raise exception 'TEA_DISCUSSION_FORBIDDEN'; end if;
 if p_answers is null or jsonb_typeof(p_answers)<>'object' or
   exists(select 1 from jsonb_object_keys(p_answers) k where k not in ('fullName','height','availability','portfolio')) or
   jsonb_typeof(p_answers->'fullName') is distinct from 'string' or length(btrim(p_answers->>'fullName')) not between 1 and 100 or
   jsonb_typeof(p_answers->'availability') is distinct from 'string' or length(btrim(p_answers->>'availability')) not between 1 and 1000 or
   (p_answers ? 'height' and (jsonb_typeof(p_answers->'height')<>'string' or length(p_answers->>'height')>40)) or
   (p_answers ? 'portfolio' and (jsonb_typeof(p_answers->'portfolio')<>'string' or length(p_answers->>'portfolio')>2048 or
     p_answers->>'portfolio' !~ '^https://[^[:space:]@]+\.[^[:space:]]+$')) then raise exception 'TEA_NOTE_INVALID'; end if;
 select * into previous from public.app_tea_applications where id=p_request or (note_id=p_id and applicant_id=p_actor) limit 1;
 if previous.id is not null then
   if previous.note_id<>p_id or previous.applicant_id<>p_actor or previous.answers<>p_answers then raise exception 'TEA_DISCUSSION_CONFLICT'; end if;
   return jsonb_build_object('id',previous.id,'submittedAt',previous.created_at,'confirmed',true);
 end if;
 if item.primary_action->>'kind' is distinct from 'application' or
   not coalesce((item.primary_action->>'accepting')::boolean,false) or
   not (public.captro_tea_note_capabilities(item.author_id)->>'canCreateForms')::boolean then raise exception 'TEA_NOTE_FORM_CLOSED'; end if;
 if item.version is distinct from p_version then raise exception 'TEA_DISCUSSION_CONFLICT'; end if;
 if not (item.primary_action->>'heightRequested')::boolean and p_answers ? 'height' then raise exception 'TEA_NOTE_INVALID'; end if;
 insert into public.app_tea_applications(id,note_id,applicant_id,recipient_id,note_version,answers)
   values(p_request,p_id,p_actor,item.author_id,item.version,p_answers) returning * into previous;
 return jsonb_build_object('id',previous.id,'submittedAt',previous.created_at,'confirmed',true);
end $$;

create function public.captro_tea_note_applications(p_actor text,p_id uuid,p_before timestamptz default null,p_boundary uuid default null)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb; begin
 if not exists(select 1 from public.app_tea_conversations p join public.app_users u on u.id=p.author_id
   where p.id=p_id and p.author_id=p_actor and coalesce(u.metadata->>'status','active')='active') then raise exception 'TEA_DISCUSSION_FORBIDDEN'; end if;
 select coalesce(jsonb_agg(q.value order by q.created_at desc,q.id desc),'[]') into result from (
   select a.id,a.created_at,jsonb_build_object('id',a.id,'createdAt',a.created_at,'answers',a.answers) value
   from public.app_tea_applications a where a.note_id=p_id and a.recipient_id=p_actor
     and (p_before is null or (a.created_at,a.id)<(p_before,p_boundary)) order by a.created_at desc,a.id desc limit 21) q;
 return result;
end $$;

revoke all on function public.captro_tea_note_capabilities(text),public.captro_tea_note_fields(public.app_tea_conversations,text),
 public.captro_tea_note_write(text,text,uuid,jsonb),public.captro_tea_note_apply(text,uuid,uuid,integer,jsonb),
 public.captro_tea_note_applications(text,uuid,timestamptz,uuid) from public,anon,authenticated;
grant execute on function public.captro_tea_note_capabilities(text),public.captro_tea_note_fields(public.app_tea_conversations,text),
 public.captro_tea_note_write(text,text,uuid,jsonb),public.captro_tea_note_apply(text,uuid,uuid,integer,jsonb),
 public.captro_tea_note_applications(text,uuid,timestamptz,uuid) to service_role;
commit;
