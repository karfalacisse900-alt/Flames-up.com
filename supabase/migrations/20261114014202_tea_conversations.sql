-- Prepared only. Deploy with the matching Worker; no Home/commerce data changes.
begin;
create table public.app_tea_conversations (
  id uuid primary key,
  author_id text not null references public.app_users(id),
  title text not null check (length(btrim(title)) between 1 and 160),
  body text not null check (length(btrim(body)) between 1 and 8000),
  links jsonb not null default '[]' check (jsonb_typeof(links)='array' and jsonb_array_length(links)<=3),
  status text not null default 'active' check(status in ('active','removed')),
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index app_tea_conversations_page on public.app_tea_conversations(created_at desc,id desc) where status='active';
create table public.app_tea_replies (
  id uuid primary key,
  conversation_id uuid not null references public.app_tea_conversations(id),
  author_id text not null references public.app_users(id),
  body text not null check(length(btrim(body)) between 1 and 4000),
  status text not null default 'active' check(status in ('active','removed')),
  created_at timestamptz not null default now()
);
create index app_tea_replies_page on public.app_tea_replies(conversation_id,created_at,id) where status='active';
create table public.app_tea_follows (
  conversation_id uuid not null references public.app_tea_conversations(id),
  user_id text not null references public.app_users(id),
  created_at timestamptz not null default now(),
  primary key(conversation_id,user_id)
);
alter table public.app_tea_conversations enable row level security;
alter table public.app_tea_replies enable row level security;
alter table public.app_tea_follows enable row level security;
revoke all on public.app_tea_conversations,public.app_tea_replies,public.app_tea_follows from public,anon,authenticated;
grant select,insert,update,delete on public.app_tea_conversations,public.app_tea_replies,public.app_tea_follows to service_role;

-- The trusted Worker supplies a canonical app identity, never a client actor ID.
create function public.captro_tea_author_visible(p_viewer text,p_author text) returns boolean
language sql stable security invoker set search_path='' as $$
 select exists(select 1 from public.app_users u where u.id=p_author
   and coalesce(u.metadata->>'status','active')='active'
   and (p_viewer=u.id or u.is_private=false or exists(select 1 from public.app_follows f
     where f.app_follower_id=p_viewer and f.app_following_id=u.id and f.status='active'))
   and not exists(select 1 from public.app_blocks b join public.app_users v on v.id=p_viewer
     where (b.blocker_id in (u.id,u.supabase_user_id::text) and b.blocked_id in (v.id,v.supabase_user_id::text))
       or (b.blocked_id in (u.id,u.supabase_user_id::text) and b.blocker_id in (v.id,v.supabase_user_id::text))))
$$;
create function public.captro_tea_post_json(p public.app_tea_conversations,p_viewer text) returns jsonb
language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('id',p.id,'title',p.title,'body',p.body,'links',p.links,'version',p.version,
   'createdAt',p.created_at,'author',jsonb_build_object('id',u.id,'name',coalesce(nullif(u.full_name,''),u.username),'username',u.username),
   'isAuthor',u.id=p_viewer,'following',exists(select 1 from public.app_tea_follows f where f.conversation_id=p.id and f.user_id=p_viewer))
 from public.app_users u where u.id=p.author_id
$$;
create function public.captro_tea_read(p_viewer text,p_kind text,p_id uuid default null,
 p_before timestamptz default null,p_boundary uuid default null,p_snapshot timestamptz default now()) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare result jsonb; item public.app_tea_conversations;
begin
 if p_kind='list' then
   select coalesce(jsonb_agg(public.captro_tea_post_json(q,p_viewer) order by q.created_at desc,q.id desc),'[]') into result
   from (select p.* from public.app_tea_conversations p where p.status='active'
     and p.created_at<=p_snapshot and (p_before is null or (p.created_at,p.id)<(p_before,p_boundary))
     and public.captro_tea_author_visible(p_viewer,p.author_id)
     order by p.created_at desc,p.id desc limit 21) q;
   return result;
 end if;
 select * into item from public.app_tea_conversations p where p.id=p_id and p.status='active'
   and public.captro_tea_author_visible(p_viewer,p.author_id);
 if item.id is null then raise exception 'TEA_DISCUSSION_UNAVAILABLE'; end if;
 if p_kind='detail' then return public.captro_tea_post_json(item,p_viewer); end if;
 if p_kind<>'replies' then raise exception 'TEA_DISCUSSION_INVALID'; end if;
 select coalesce(jsonb_agg(q.value order by q.created_at,q.id),'[]') into result from (
   select r.created_at,r.id,jsonb_build_object('id',r.id,'body',r.body,'createdAt',r.created_at,
     'author',jsonb_build_object('id',u.id,'name',coalesce(nullif(u.full_name,''),u.username),'username',u.username)) value
   from public.app_tea_replies r join public.app_users u on u.id=r.author_id
   where r.conversation_id=p_id and r.status='active' and r.created_at<=p_snapshot
     and (p_before is null or (r.created_at,r.id)>(p_before,p_boundary))
     and public.captro_tea_author_visible(p_viewer,r.author_id)
   order by r.created_at,r.id limit 21) q;
 return result;
end $$;

create function public.captro_tea_write(p_actor text,p_action text,p_id uuid,p_data jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare item public.app_tea_conversations; existing_reply public.app_tea_replies; actor public.app_users;
begin
 select * into actor from public.app_users where id=p_actor for update;
 if actor.id is null or coalesce(actor.metadata->>'status','active')<>'active' then raise exception 'TEA_DISCUSSION_FORBIDDEN'; end if;
 if p_action='create' then
   insert into public.app_tea_conversations(id,author_id,title,body,links)
     values(p_id,p_actor,p_data->>'title',p_data->>'body',p_data->'links') on conflict(id) do nothing;
 end if;
 select * into item from public.app_tea_conversations where id=p_id for update;
 if item.id is null or item.status<>'active' or not public.captro_tea_author_visible(p_actor,item.author_id) then raise exception 'TEA_DISCUSSION_UNAVAILABLE'; end if;
 if p_action in ('create','edit') then
   if item.author_id<>p_actor then raise exception 'TEA_DISCUSSION_FORBIDDEN'; end if;
   if p_action='create' then
     if item.title<>p_data->>'title' or item.body<>p_data->>'body' or item.links<>p_data->'links' then raise exception 'TEA_DISCUSSION_CONFLICT'; end if;
   else
     if item.title=p_data->>'title' and item.body=p_data->>'body' and item.links=p_data->'links' then
       return public.captro_tea_post_json(item,p_actor);
     end if;
     if item.version is distinct from (p_data->>'version')::integer then raise exception 'TEA_DISCUSSION_CONFLICT'; end if;
     update public.app_tea_conversations set title=p_data->>'title',body=p_data->>'body',links=p_data->'links',
       version=version+1,updated_at=now() where id=p_id returning * into item;
   end if;
 elsif p_action='reply' then
   insert into public.app_tea_replies(id,conversation_id,author_id,body)
     values((p_data->>'requestID')::uuid,p_id,p_actor,p_data->>'body') on conflict(id) do nothing;
   select * into existing_reply from public.app_tea_replies where id=(p_data->>'requestID')::uuid;
   if existing_reply.author_id<>p_actor or existing_reply.conversation_id<>p_id or existing_reply.body<>p_data->>'body' then raise exception 'TEA_DISCUSSION_CONFLICT'; end if;
   return jsonb_build_object('id',existing_reply.id,'body',existing_reply.body,'createdAt',existing_reply.created_at,
     'author',jsonb_build_object('id',actor.id,'name',coalesce(nullif(actor.full_name,''),actor.username),'username',actor.username));
 elsif p_action='follow' then
   if (p_data->>'following')::boolean then
     insert into public.app_tea_follows(conversation_id,user_id) values(p_id,p_actor) on conflict do nothing;
   else delete from public.app_tea_follows where conversation_id=p_id and user_id=p_actor; end if;
 else raise exception 'TEA_DISCUSSION_INVALID'; end if;
 return public.captro_tea_post_json(item,p_actor);
end $$;
revoke all on function public.captro_tea_author_visible(text,text),public.captro_tea_post_json(public.app_tea_conversations,text),
 public.captro_tea_read(text,text,uuid,timestamptz,uuid,timestamptz),public.captro_tea_write(text,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.captro_tea_author_visible(text,text),public.captro_tea_post_json(public.app_tea_conversations,text),
 public.captro_tea_read(text,text,uuid,timestamptz,uuid,timestamptz),public.captro_tea_write(text,text,uuid,jsonb) to service_role;
commit;
