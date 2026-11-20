-- Additive, private presentation signals. No ranking, follows or commerce changes.
begin;
create table public.app_tea_interest (
  conversation_id uuid not null references public.app_tea_conversations(id) on delete cascade,
  user_id text not null references public.app_users(id),
  choice text not null check (choice in ('interested','pass')),
  updated_at timestamptz not null default now(),
  primary key (conversation_id,user_id)
);
create index app_tea_interest_author_totals on public.app_tea_interest(conversation_id) where choice='interested';
create table public.app_tea_opens (
  conversation_id uuid not null references public.app_tea_conversations(id) on delete cascade,
  user_id text not null references public.app_users(id),
  opened_at timestamptz not null default now(),
  primary key (conversation_id,user_id)
);
alter table public.app_tea_interest enable row level security;
alter table public.app_tea_opens enable row level security;
revoke all on public.app_tea_interest,public.app_tea_opens from public,anon,authenticated;
grant select,insert,update,delete on public.app_tea_interest,public.app_tea_opens to service_role;

-- Extend the existing payload only with this viewer's private selection.
-- Neither identities nor aggregate interest/open counts enter the public feed.
create or replace function public.captro_tea_post_json(p public.app_tea_conversations,p_viewer text) returns jsonb
language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('id',p.id,'title',p.title,'body',p.body,'links',p.links,'version',p.version,
   'createdAt',p.created_at,'author',jsonb_build_object('id',u.id,'name',coalesce(nullif(u.full_name,''),nullif(u.username,''),'Captro member'),'username',coalesce(u.username,'')),
   'replyCount',(select count(*) from public.app_tea_replies r where r.conversation_id=p.id and r.status='active' and public.captro_tea_author_visible(p_viewer,r.author_id)),
   'replyTargets',coalesce((select jsonb_agg(t.value order by (t.value->'target'->>'version')::integer,(t.value->'target'->>'start')::integer) from (select jsonb_build_object('target',r.target,'count',count(*)) value
     from public.app_tea_replies r where r.conversation_id=p.id and r.target is not null and r.status='active'
     and public.captro_tea_author_visible(p_viewer,r.author_id) group by r.target) t),'[]'),
   'isAuthor',u.id=p_viewer,'following',exists(select 1 from public.app_tea_follows f where f.conversation_id=p.id and f.user_id=p_viewer),
   'interest',(select i.choice from public.app_tea_interest i where i.conversation_id=p.id and i.user_id=p_viewer))
   || public.captro_tea_note_fields(p,p_viewer)
 from public.app_users u where u.id=p.author_id
$$;

-- Only the authenticated Worker may supply p_actor, from its canonical session.
create function public.captro_tea_private_signal(p_actor text,p_id uuid,p_action text,p_choice text default null) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare item public.app_tea_conversations;
begin
 perform 1 from public.app_users where id=p_actor and coalesce(metadata->>'status','active')='active' for update;
 if not found then raise exception 'TEA_DISCUSSION_FORBIDDEN'; end if;
 select * into item from public.app_tea_conversations where id=p_id for share;
 if item.id is null or item.status<>'active' or not public.captro_tea_author_visible(p_actor,item.author_id) then
   raise exception 'TEA_DISCUSSION_UNAVAILABLE';
 end if;
 if p_action='interest' then
   if p_choice is not null and p_choice not in ('interested','pass') then raise exception 'TEA_NOTE_INVALID'; end if;
   if p_choice is null then
     delete from public.app_tea_interest where conversation_id=p_id and user_id=p_actor;
   else
     insert into public.app_tea_interest(conversation_id,user_id,choice) values(p_id,p_actor,p_choice)
       on conflict(conversation_id,user_id) do update set choice=excluded.choice,updated_at=now();
   end if;
   return jsonb_build_object('interest',p_choice);
 elsif p_action='open' then
   if item.author_id<>p_actor then
     insert into public.app_tea_opens(conversation_id,user_id) values(p_id,p_actor) on conflict do nothing;
   end if;
   return jsonb_build_object('confirmed',true);
 elsif p_action='insights' then
   if item.author_id<>p_actor then raise exception 'TEA_DISCUSSION_FORBIDDEN'; end if;
   return jsonb_build_object(
     'uniqueOpens',(select count(*) from public.app_tea_opens where conversation_id=p_id),
     'interested',(select count(*) from public.app_tea_interest where conversation_id=p_id and choice='interested'),
     'replies',(select count(*) from public.app_tea_replies r where conversation_id=p_id and status='active'
       and public.captro_tea_author_visible(p_actor,r.author_id)));
 else raise exception 'TEA_NOTE_INVALID'; end if;
end $$;
revoke all on function public.captro_tea_private_signal(text,uuid,text,text) from public,anon,authenticated;
grant execute on function public.captro_tea_private_signal(text,uuid,text,text) to service_role;
commit;
