-- Additive; old clients keep general replies and all existing RPC signatures.
begin;
alter table public.app_tea_replies add column target jsonb;
alter table public.app_tea_replies add constraint tea_target_shape check(target is null or
 (jsonb_typeof(target)='object' and target ?& array['id','version','start','end','quote']));
create table public.app_tea_revisions (
 conversation_id uuid not null references public.app_tea_conversations(id) on delete cascade,
 version integer not null, body text not null, primary key(conversation_id,version)
);
alter table public.app_tea_revisions enable row level security;
revoke all on public.app_tea_revisions from public,anon,authenticated;
grant select,insert,update,delete on public.app_tea_revisions to service_role;
insert into public.app_tea_revisions select id,version,body from public.app_tea_conversations;
create function public.captro_tea_snapshot_revision() returns trigger
language plpgsql security invoker set search_path='' as $$ begin
 insert into public.app_tea_revisions values(new.id,new.version,new.body) on conflict do nothing;
 return new;
end $$;
revoke all on function public.captro_tea_snapshot_revision() from public,anon,authenticated;
grant execute on function public.captro_tea_snapshot_revision() to service_role;
create trigger tea_revision_snapshot after insert or update on public.app_tea_conversations
for each row execute function public.captro_tea_snapshot_revision();
create function public.captro_tea_reply_revision(p_viewer text,p_id uuid,p_version integer) returns text
language plpgsql stable security invoker set search_path='' as $$ declare caption text; begin
 if not exists(select 1 from public.app_tea_conversations p where p.id=p_id and p.status='active'
   and public.captro_tea_author_visible(p_viewer,p.author_id)) then raise exception 'TEA_DISCUSSION_UNAVAILABLE'; end if;
 select body into caption from public.app_tea_revisions where conversation_id=p_id and version=p_version;
 if caption is null then raise exception 'TEA_DISCUSSION_CONFLICT'; end if;
 return caption;
end $$;
revoke all on function public.captro_tea_reply_revision(text,uuid,integer) from public,anon,authenticated;
grant execute on function public.captro_tea_reply_revision(text,uuid,integer) to service_role;
create or replace function public.captro_tea_post_json(p public.app_tea_conversations,p_viewer text) returns jsonb
language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('id',p.id,'title',p.title,'body',p.body,'links',p.links,'version',p.version,
   'createdAt',p.created_at,'author',jsonb_build_object('id',u.id,'name',coalesce(nullif(u.full_name,''),nullif(u.username,''),'Captro member'),'username',coalesce(u.username,'')),
   'replyCount',(select count(*) from public.app_tea_replies r where r.conversation_id=p.id and r.status='active' and public.captro_tea_author_visible(p_viewer,r.author_id)),
   'replyTargets',coalesce((select jsonb_agg(t.value) from (select jsonb_build_object('target',r.target,'count',count(*)) value
     from public.app_tea_replies r where r.conversation_id=p.id and r.target is not null and r.status='active'
     and public.captro_tea_author_visible(p_viewer,r.author_id) group by r.target) t),'[]'),
   'isAuthor',u.id=p_viewer,'following',exists(select 1 from public.app_tea_follows f where f.conversation_id=p.id and f.user_id=p_viewer))
 from public.app_users u where u.id=p.author_id
$$;
create or replace function public.captro_tea_read(p_viewer text,p_kind text,p_id uuid default null,
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
   select r.created_at,r.id,jsonb_build_object('id',r.id,'body',r.body,'target',r.target,'createdAt',r.created_at,
     'author',jsonb_build_object('id',u.id,'name',coalesce(nullif(u.full_name,''),nullif(u.username,''),'Captro member'),'username',coalesce(u.username,''))) value
   from public.app_tea_replies r join public.app_users u on u.id=r.author_id
   where r.conversation_id=p_id and r.status='active' and r.created_at<=p_snapshot
     and (p_before is null or (r.created_at,r.id)>(p_before,p_boundary))
     and public.captro_tea_author_visible(p_viewer,r.author_id)
   order by r.created_at,r.id limit 21) q;
 return result;
end $$;

create or replace function public.captro_tea_write(p_actor text,p_action text,p_id uuid,p_data jsonb) returns jsonb
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
   select * into existing_reply from public.app_tea_replies where id=(p_data->>'requestID')::uuid;
   if existing_reply.id is null and p_data->'target' is not null and p_data->'target'<>'null'::jsonb then
     if (p_data->'target'->>'version')::integer is distinct from item.version
       or (p_data->'target'->>'start')::integer<0
       or (p_data->'target'->>'end')::integer<=(p_data->'target'->>'start')::integer
       or substring(item.body from (p_data->'target'->>'start')::integer+1 for
         (p_data->'target'->>'end')::integer-(p_data->'target'->>'start')::integer) is distinct from p_data->'target'->>'quote'
     then raise exception 'TEA_DISCUSSION_CONFLICT'; end if;
   end if;
   insert into public.app_tea_replies(id,conversation_id,author_id,body,target)
     values((p_data->>'requestID')::uuid,p_id,p_actor,p_data->>'body',nullif(p_data->'target','null'::jsonb)) on conflict(id) do nothing;
   select * into existing_reply from public.app_tea_replies where id=(p_data->>'requestID')::uuid;
   if existing_reply.author_id<>p_actor or existing_reply.conversation_id<>p_id or existing_reply.body<>p_data->>'body' or existing_reply.target is distinct from nullif(p_data->'target','null'::jsonb) then raise exception 'TEA_DISCUSSION_CONFLICT'; end if;
   return jsonb_build_object('id',existing_reply.id,'body',existing_reply.body,'target',existing_reply.target,'createdAt',existing_reply.created_at,
     'author',jsonb_build_object('id',actor.id,'name',coalesce(nullif(actor.full_name,''),nullif(actor.username,''),'Captro member'),'username',coalesce(actor.username,'')));
 elsif p_action='follow' then
   if (p_data->>'following')::boolean then
     insert into public.app_tea_follows(conversation_id,user_id) values(p_id,p_actor) on conflict do nothing;
   else delete from public.app_tea_follows where conversation_id=p_id and user_id=p_actor; end if;
 else raise exception 'TEA_DISCUSSION_INVALID'; end if;
 return public.captro_tea_post_json(item,p_actor);
end $$;


-- Target-specific paging keeps a sentence thread independent of general reply
-- volume. The original read RPC remains unchanged for older app builds.
create function public.captro_tea_target_replies(p_viewer text,p_id uuid,p_target text,
 p_before timestamptz default null,p_boundary uuid default null,p_snapshot timestamptz default now()) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare result jsonb; begin
 if not exists(select 1 from public.app_tea_conversations p where p.id=p_id and p.status='active' and public.captro_tea_author_visible(p_viewer,p.author_id)) then raise exception 'TEA_DISCUSSION_UNAVAILABLE'; end if;
 select coalesce(jsonb_agg(q.value order by q.created_at,q.id),'[]') into result from (
   select r.created_at,r.id,jsonb_build_object('id',r.id,'body',r.body,'target',r.target,'createdAt',r.created_at,
     'author',jsonb_build_object('id',u.id,'name',coalesce(nullif(u.full_name,''),nullif(u.username,''),'Captro member'),'username',coalesce(u.username,''))) value
   from public.app_tea_replies r join public.app_users u on u.id=r.author_id
   where r.conversation_id=p_id and r.status='active' and r.created_at<=p_snapshot
     and ((p_target='general' and r.target is null) or r.target->>'id'=p_target)
     and (p_before is null or (r.created_at,r.id)>(p_before,p_boundary))
     and public.captro_tea_author_visible(p_viewer,r.author_id)
   order by r.created_at,r.id limit 21) q;
 return result;
end $$;
revoke all on function public.captro_tea_target_replies(text,uuid,text,timestamptz,uuid,timestamptz) from public,anon,authenticated;
grant execute on function public.captro_tea_target_replies(text,uuid,text,timestamptz,uuid,timestamptz) to service_role;

commit;
