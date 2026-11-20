-- Qualified reads are intentionally separate from legacy instantaneous opens.
-- No backfill: an old open is not evidence of five seconds of reading.
begin;
create table public.app_tea_qualified_reads (
  conversation_id uuid not null references public.app_tea_conversations(id) on delete cascade,
  user_id text not null references public.app_users(id) on delete cascade,
  qualified_at timestamptz not null default now(),
  primary key (conversation_id,user_id)
);
create table public.app_tea_read_sessions (
  conversation_id uuid not null references public.app_tea_conversations(id) on delete cascade,
  user_id text not null references public.app_users(id) on delete cascade,
  token uuid not null,
  started_at timestamptz not null,
  primary key (conversation_id,user_id)
);
create index app_tea_qualified_reads_user on public.app_tea_qualified_reads(user_id);
create index app_tea_read_sessions_user on public.app_tea_read_sessions(user_id);
create index if not exists app_tea_replies_engagement on public.app_tea_replies(conversation_id,author_id) where status='active';
alter table public.app_tea_qualified_reads enable row level security;
alter table public.app_tea_read_sessions enable row level security;
revoke all on public.app_tea_qualified_reads,public.app_tea_read_sessions from public,anon,authenticated;
grant select,insert,update,delete on public.app_tea_qualified_reads,public.app_tea_read_sessions to service_role;

-- One row per person, with independent reasons. No pass identities or totals
-- leave this function. Replies hidden/removed by moderation cease to qualify.
create function public.captro_tea_engaged_people(p public.app_tea_conversations)
returns table(user_id text,qualified_read boolean,active_plus boolean,visible_reply boolean)
language sql stable security invoker set search_path='' as $$
  select a.user_id,bool_or(a.reason='read'),bool_or(a.reason='plus'),bool_or(a.reason='reply')
  from (
    select q.user_id,'read' reason from public.app_tea_qualified_reads q where q.conversation_id=p.id
    union all
    select i.user_id,'plus' from public.app_tea_interest i where i.conversation_id=p.id and i.choice='interested'
    union all
    select r.author_id,'reply' from public.app_tea_replies r where r.conversation_id=p.id and r.status='active'
      and public.captro_tea_author_visible(p.author_id,r.author_id)
  ) a join public.app_users u on u.id=a.user_id
  where a.user_id<>p.author_id and coalesce(u.metadata->>'status','active')='active'
  group by a.user_id
$$;
create function public.captro_tea_engagement(p public.app_tea_conversations) returns jsonb
language sql stable security invoker set search_path='' as $$
  select jsonb_build_object('engagementCount',count(*),'engagementUpdatedAt',statement_timestamp())
  from public.captro_tea_engaged_people(p)
$$;
revoke all on function public.captro_tea_engaged_people(public.app_tea_conversations),public.captro_tea_engagement(public.app_tea_conversations) from public,anon,authenticated;
grant execute on function public.captro_tea_engaged_people(public.app_tea_conversations),public.captro_tea_engagement(public.app_tea_conversations) to service_role;

-- Preserve existing post payload/visibility. Feed and detail share this one
-- batched query; no client per-row count requests and no ranking change.
alter function public.captro_tea_post_json(public.app_tea_conversations,text) rename to captro_tea_post_json_before_engagement;
create function public.captro_tea_post_json(p public.app_tea_conversations,p_viewer text) returns jsonb
language sql stable security invoker set search_path='' as $$
  select public.captro_tea_post_json_before_engagement(p,p_viewer) || public.captro_tea_engagement(p)
$$;
revoke all on function public.captro_tea_post_json(public.app_tea_conversations,text) from public,anon,authenticated;
grant execute on function public.captro_tea_post_json(public.app_tea_conversations,text) to service_role;

create or replace function public.captro_tea_private_signal(p_actor text,p_id uuid,p_action text,p_choice text default null) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare item public.app_tea_conversations; lease public.app_tea_read_sessions; receipt uuid;
begin
  perform 1 from public.app_users where id=p_actor and coalesce(metadata->>'status','active')='active' for update;
  if not found then raise exception 'TEA_DISCUSSION_FORBIDDEN'; end if;
  select * into item from public.app_tea_conversations where id=p_id for share;
  if item.id is null or item.status<>'active' or not public.captro_tea_author_visible(p_actor,item.author_id) then
    raise exception 'TEA_DISCUSSION_UNAVAILABLE';
  end if;
  if p_action='interest' then
    if p_choice is not null and p_choice not in ('interested','pass') then raise exception 'TEA_NOTE_INVALID'; end if;
    if p_choice is null then delete from public.app_tea_interest where conversation_id=p_id and user_id=p_actor;
    else
      insert into public.app_tea_interest(conversation_id,user_id,choice) values(p_id,p_actor,p_choice)
        on conflict(conversation_id,user_id) do update set choice=excluded.choice,updated_at=now();
    end if;
    return jsonb_build_object('interest',p_choice) || public.captro_tea_engagement(item);
  elsif p_action='summary' then
    return public.captro_tea_engagement(item);
  elsif p_action='open' then
    -- Legacy clients may still call this; instantaneous opens never qualify.
    return jsonb_build_object('confirmed',true);
  elsif p_action='read-start' then
    if item.author_id=p_actor or exists(select 1 from public.app_tea_qualified_reads where conversation_id=p_id and user_id=p_actor) then
      return jsonb_build_object('qualified',true) || public.captro_tea_engagement(item);
    end if;
    receipt := gen_random_uuid();
    insert into public.app_tea_read_sessions values(p_id,p_actor,receipt,clock_timestamp())
      on conflict(conversation_id,user_id) do update set token=excluded.token,started_at=excluded.started_at;
    return jsonb_build_object('qualified',false,'token',receipt) || public.captro_tea_engagement(item);
  elsif p_action='read-qualify' then
    select * into lease from public.app_tea_read_sessions where conversation_id=p_id and user_id=p_actor;
    if lease.token is null or lease.token::text<>p_choice or p_choice is null
      or clock_timestamp()<lease.started_at+interval '5 seconds'
      or clock_timestamp()>lease.started_at+interval '2 minutes' then raise exception 'TEA_NOTE_INVALID'; end if;
    if item.author_id<>p_actor then
      insert into public.app_tea_qualified_reads(conversation_id,user_id) values(p_id,p_actor) on conflict do nothing;
    end if;
    return jsonb_build_object('qualified',true) || public.captro_tea_engagement(item);
  elsif p_action='insights' then
    if item.author_id<>p_actor then raise exception 'TEA_DISCUSSION_FORBIDDEN'; end if;
    return (select jsonb_build_object('qualifiedReads',count(*) filter(where qualified_read),
      'activePlus',count(*) filter(where active_plus),'uniqueRepliers',count(*) filter(where visible_reply),
      -- Compatibility keys contain only the new semantics; old opens remain uncounted.
      'uniqueOpens',count(*) filter(where qualified_read),'interested',count(*) filter(where active_plus),
      'replies',count(*) filter(where visible_reply)) from public.captro_tea_engaged_people(item));
  else raise exception 'TEA_NOTE_INVALID'; end if;
end $$;
commit;
