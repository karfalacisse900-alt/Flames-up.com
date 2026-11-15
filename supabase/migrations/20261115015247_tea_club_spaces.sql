-- Prepared only. General keeps the existing group message/membership records.
begin;
create table public.app_tea_club_settings (
 club_id uuid primary key references public.app_purchasables(id) on delete cascade,
 rules text not null default '' check(length(rules)<=8000),
 official_links jsonb not null default '[]', rooms_enabled boolean not null default false,
 pinned_message_id text, version integer not null default 1
);
create table public.app_tea_club_rooms (
 id uuid primary key, club_id uuid not null references public.app_purchasables(id) on delete cascade,
 name text not null check(length(btrim(name)) between 1 and 60),
 announcements boolean not null default false, created_at timestamptz not null default now(),
 unique(club_id,name)
);
alter table public.app_group_messages add column tea_room_id uuid references public.app_tea_club_rooms(id);
alter table public.app_group_messages add column tea_quote_id text;
create index tea_room_messages on public.app_group_messages(group_id,tea_room_id,created_at desc,id desc);
create table public.app_tea_club_links (
 id uuid primary key, club_id uuid not null references public.app_purchasables(id) on delete cascade,
 title text not null check(length(btrim(title)) between 1 and 100), url text not null check(length(url)<=2048 and url like 'https://%'),
 shared_by text references public.app_users(id) on delete set null, message_id text,
 version integer not null default 1, created_at timestamptz not null default now(), removed_at timestamptz
);
create index tea_club_links_page on public.app_tea_club_links(club_id,created_at desc,id desc) where removed_at is null;
create table public.app_tea_club_reads (
 club_id uuid not null references public.app_purchasables(id) on delete cascade, user_id text not null references public.app_users(id) on delete cascade,
 room text not null default 'general', seen_at timestamptz not null,
 primary key(club_id,user_id,room)
);
create table public.app_tea_club_invites (
 id uuid primary key, club_id uuid not null references public.app_purchasables(id) on delete cascade,
 created_by text not null references public.app_users(id) on delete cascade, token_hash text not null unique,
 requires_approval boolean not null, expires_at timestamptz not null,
 revoked_at timestamptz, created_at timestamptz not null default now()
);
create table public.app_tea_club_invite_requests (
 invite_id uuid not null references public.app_tea_club_invites(id) on delete cascade, user_id text not null references public.app_users(id) on delete cascade,
 status text not null default 'pending' check(status in ('pending','approved','denied')),
 decided_by text, decided_at timestamptz, created_at timestamptz not null default now(), primary key(invite_id,user_id)
);
do $$ declare t text; begin
 foreach t in array array['app_tea_club_settings','app_tea_club_rooms','app_tea_club_links','app_tea_club_reads','app_tea_club_invites','app_tea_club_invite_requests'] loop
   execute format('alter table public.%I enable row level security',t);
   execute format('revoke all on public.%I from public,anon,authenticated',t);
   execute format('grant select,insert,update,delete on public.%I to service_role',t);
 end loop;
end $$;

create function public.captro_tea_club(p_actor text,p_club uuid,p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path='' as $$
declare club public.app_purchasables; actor public.app_users; member public.app_group_chat_members;
 settings public.app_tea_club_settings; selected_room public.app_tea_club_rooms; msg public.app_group_messages;
 saved public.app_tea_club_links; invitation public.app_tea_club_invites;
 gid text; admin boolean; result jsonb; room_id uuid; target text;
begin
 select * into actor from public.app_users where id=p_actor and coalesce(metadata->>'status','active')='active';
 if actor.id is null then raise exception 'TEA_CLUB_FORBIDDEN'; end if;
 select * into club from public.app_purchasables where id=p_club and content_type in ('club','group');
 gid:=club.private_config->>'group_chat_id';
 if gid is null or club.status not in ('active','sold_out','paused') then raise exception 'TEA_CLUB_UNAVAILABLE'; end if;
 if exists(select 1 from public.app_blocks b where
   (b.blocker_id in (p_actor,actor.supabase_user_id::text) and b.blocked_id in (club.creator_app_user_id,club.creator_id::text)) or
   (b.blocked_id in (p_actor,actor.supabase_user_id::text) and b.blocker_id in (club.creator_app_user_id,club.creator_id::text))) then raise exception 'TEA_CLUB_UNAVAILABLE'; end if;
 if p_action not in ('overview','messages','message','links','members','invites','inviteRequests') then
   perform 1 from public.app_group_chats where id=gid for update;
 end if;
 select * into member from public.app_group_chat_members where group_id=gid and user_id=p_actor for share;
 if member.id is null then raise exception 'TEA_CLUB_FORBIDDEN'; end if;
 admin:=member.role in ('owner','admin');
 select * into settings from public.app_tea_club_settings where club_id=p_club;
 room_id:=nullif(p_data->>'room','')::uuid;
 if room_id is not null then
   select * into selected_room from public.app_tea_club_rooms where id=room_id and club_id=p_club;
   if selected_room.id is null or not coalesce(settings.rooms_enabled,false) then raise exception 'TEA_CLUB_UNAVAILABLE'; end if;
 end if;
 if p_action='overview' then
   return jsonb_build_object('id',club.id,'groupId',gid,'name',club.title,'description',club.description,
     'role',member.role,'viewerId',p_actor,'memberCount',(select count(*) from public.app_group_chat_members where group_id=gid),
     'rules',coalesce(settings.rules,''),'officialLinks',coalesce(settings.official_links,'[]'),
     'roomsEnabled',coalesce(settings.rooms_enabled,false),'version',coalesce(settings.version,1),
     'generalUnread',exists(select 1 from public.app_group_messages m where m.group_id=gid and m.tea_room_id is null and m.sender_id<>p_actor and m.media->>'removed_at' is null
       and m.created_at>coalesce((select seen_at from public.app_tea_club_reads where club_id=p_club and user_id=p_actor and room='general'),'epoch')),
     'approvalRequired',club.approval_required,'postId',club.post_id,
     'image',(select metadata->>'image_url' from public.app_group_chats where id=gid),
     'pin',(select jsonb_build_object('id',m.id,'body',m.body,'room',m.tea_room_id) from public.app_group_messages m where m.id=settings.pinned_message_id and m.group_id=gid and m.media->>'removed_at' is null),
     'rooms',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'name',r.name,'announcements',r.announcements,
       'unread',exists(select 1 from public.app_group_messages m where m.group_id=gid and m.tea_room_id=r.id and m.sender_id<>p_actor
       and m.created_at>coalesce((select seen_at from public.app_tea_club_reads where club_id=p_club and user_id=p_actor and room=r.id::text),'epoch')))
       order by r.created_at,r.id) from public.app_tea_club_rooms r where r.club_id=p_club and coalesce(settings.rooms_enabled,false)),'[]'));
 end if;
 if p_action in ('messages','message') then
   select coalesce(jsonb_agg(q.value order by q.created_at desc,q.id desc),'[]') into result from (
     select m.id,m.created_at,jsonb_build_object('id',m.id,'body',m.body,'createdAt',m.created_at,'room',m.tea_room_id,
       'mediaURL',m.media_url,'mediaType',m.media_type,
       'author',jsonb_build_object('id',u.id,'name',coalesce(nullif(u.full_name,''),u.username,'Captro member'),'username',coalesce(u.username,'')),
       'quote',(select jsonb_build_object('id',q.id,'body',q.body,'room',q.tea_room_id) from public.app_group_messages q
          where q.id=m.tea_quote_id and q.group_id=gid and q.media->>'removed_at' is null)) value
     from public.app_group_messages m join public.app_users u on u.id=m.sender_id
     where m.group_id=gid and m.media->>'removed_at' is null and
       ((p_action='message' and m.id=p_data->>'message') or
        (p_action='messages' and m.tea_room_id is not distinct from room_id and
         (p_data->>'before' is null or (m.created_at,m.id)<((p_data->>'before')::timestamptz,p_data->>'boundary'))))
     order by m.created_at desc,m.id desc limit 51) q;
   return result;
 end if;
 if p_action='links' then
   select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at desc,q.id desc),'[]') into result from (
     select l.* from public.app_tea_club_links l where l.club_id=p_club and l.removed_at is null
       and (p_data->>'before' is null or (l.created_at,l.id)<((p_data->>'before')::timestamptz,(p_data->>'boundary')::uuid))
     order by l.created_at desc,l.id desc limit 51) q; return result;
 end if;
 if p_action='members' then
   select coalesce(jsonb_agg(q.value),'[]') into result from (
     select jsonb_build_object('id',u.id,'name',coalesce(nullif(u.full_name,''),u.username,'Captro member'),'username',coalesce(u.username,''),'role',m.role) value
     from public.app_group_chat_members m join public.app_users u on u.id=m.user_id where m.group_id=gid and m.user_id>coalesce(p_data->>'after','')
     order by m.user_id limit 51) q; return result;
 end if;
 -- Serialize mutations for stale-version/idempotency checks; no network inside this transaction.
 perform 1 from public.app_group_chats where id=gid for update;
 if p_action='send' then
   if selected_room.announcements and not admin then raise exception 'TEA_CLUB_FORBIDDEN'; end if;
   if length(btrim(coalesce(p_data->>'body',''))) not between 1 and 2000 then raise exception 'TEA_CLUB_INVALID'; end if;
   target:=nullif(p_data->>'quote','');
   if target is not null and not exists(select 1 from public.app_group_messages where id=target and group_id=gid and media->>'removed_at' is null)
     then raise exception 'TEA_CLUB_UNAVAILABLE'; end if;
   select * into msg from public.app_group_messages where id=p_data->>'id';
   if msg.id is not null then
     if msg.sender_id<>p_actor or msg.group_id<>gid or msg.body<>p_data->>'body' or msg.tea_room_id is distinct from room_id or msg.tea_quote_id is distinct from target
       then raise exception 'TEA_CLUB_CONFLICT'; end if;
   else
     insert into public.app_group_messages(id,group_id,sender_id,body,tea_room_id,tea_quote_id)
       values(p_data->>'id',gid,p_actor,p_data->>'body',room_id,target);
   end if;
   return public.captro_tea_club(p_actor,p_club,'message',jsonb_build_object('message',p_data->>'id'));
 elsif p_action='read' then
   select * into msg from public.app_group_messages where id=p_data->>'message' and group_id=gid and tea_room_id is not distinct from room_id;
   if msg.id is null then raise exception 'TEA_CLUB_UNAVAILABLE'; end if;
   insert into public.app_tea_club_reads values(p_club,p_actor,coalesce(room_id::text,'general'),msg.created_at)
     on conflict(club_id,user_id,room) do update set seen_at=greatest(public.app_tea_club_reads.seen_at,excluded.seen_at);
 elsif p_action='saveLink' then
   target:=nullif(p_data->>'message','');
   if target is not null and not exists(select 1 from public.app_group_messages where id=target and group_id=gid and media->>'removed_at' is null
     and position(p_data->>'url' in body)>0) then raise exception 'TEA_CLUB_UNAVAILABLE'; end if;
   insert into public.app_tea_club_links(id,club_id,title,url,shared_by,message_id)
     values((p_data->>'id')::uuid,p_club,p_data->>'title',p_data->>'url',p_actor,target) on conflict(id) do nothing;
   select * into saved from public.app_tea_club_links where id=(p_data->>'id')::uuid;
   if saved.club_id<>p_club or saved.shared_by<>p_actor or saved.title<>p_data->>'title' or saved.url<>p_data->>'url' or saved.message_id is distinct from target
     then raise exception 'TEA_CLUB_CONFLICT'; end if;
   return to_jsonb(saved);
 else
   if not admin then raise exception 'TEA_CLUB_FORBIDDEN'; end if;
   if p_action in ('editLink','removeLink') then
     select * into saved from public.app_tea_club_links where id=(p_data->>'id')::uuid and club_id=p_club for update;
     if saved.id is null then raise exception 'TEA_CLUB_UNAVAILABLE'; end if;
     if p_action='removeLink' and saved.removed_at is not null then return to_jsonb(saved); end if;
     if p_action='editLink' and saved.title=p_data->>'title' and saved.url=p_data->>'url' then return to_jsonb(saved); end if;
     if saved.version is distinct from (p_data->>'version')::integer then raise exception 'TEA_CLUB_CONFLICT'; end if;
     update public.app_tea_club_links set title=case when p_action='editLink' then p_data->>'title' else title end,
       url=case when p_action='editLink' then p_data->>'url' else url end,
       removed_at=case when p_action='removeLink' then now() else null end,version=version+1 where id=saved.id returning * into saved;
     return to_jsonb(saved);
   elsif p_action='createRoom' then
     if (select count(*) from public.app_tea_club_rooms where club_id=p_club)>=30 and not exists(select 1 from public.app_tea_club_rooms where id=(p_data->>'id')::uuid and club_id=p_club) then raise exception 'TEA_CLUB_INVALID'; end if;
     insert into public.app_tea_club_rooms(id,club_id,name,announcements) values((p_data->>'id')::uuid,p_club,p_data->>'name',(p_data->>'announcements')::boolean) on conflict(id) do nothing;
     select * into selected_room from public.app_tea_club_rooms where id=(p_data->>'id')::uuid;
     if selected_room.club_id<>p_club or selected_room.name<>p_data->>'name' or selected_room.announcements is distinct from (p_data->>'announcements')::boolean then raise exception 'TEA_CLUB_CONFLICT'; end if;
     insert into public.app_tea_club_settings(club_id,rooms_enabled) values(p_club,true) on conflict(club_id) do update set rooms_enabled=true;
     return to_jsonb(selected_room);
   elsif p_action in ('pin','settings') then
     insert into public.app_tea_club_settings(club_id) values(p_club) on conflict do nothing;
     select * into settings from public.app_tea_club_settings where club_id=p_club for update;
     if p_action='pin' then
       target:=nullif(p_data->>'message','');
       if target is not null and not exists(select 1 from public.app_group_messages where id=target and group_id=gid and media->>'removed_at' is null) then raise exception 'TEA_CLUB_UNAVAILABLE'; end if;
       if settings.pinned_message_id is not distinct from target then return jsonb_build_object('ok',true); end if;
     end if;
     if p_action='settings' and settings.rules is not distinct from p_data->>'rules' and settings.official_links is not distinct from p_data->'links' then return jsonb_build_object('ok',true); end if;
     if settings.version is distinct from (p_data->>'version')::integer then raise exception 'TEA_CLUB_CONFLICT'; end if;
     if p_action='pin' then update public.app_tea_club_settings set pinned_message_id=target,version=version+1 where club_id=p_club;
     else update public.app_tea_club_settings set rules=p_data->>'rules',official_links=p_data->'links',version=version+1 where club_id=p_club; end if;
   elsif p_action='invites' then
     select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at desc,q.id desc),'[]') into result from (select i.* from public.app_tea_club_invites i where i.club_id=p_club
       and (p_data->>'before' is null or (i.created_at,i.id)<((p_data->>'before')::timestamptz,(p_data->>'boundary')::uuid)) order by i.created_at desc,i.id desc limit 51) q;
     return result;
   elsif p_action='createInvite' then
     if (p_data->>'expires')::timestamptz<=now() or (p_data->>'expires')::timestamptz>now()+interval '30 days' then raise exception 'TEA_CLUB_INVALID'; end if;
     insert into public.app_tea_club_invites(id,club_id,created_by,token_hash,requires_approval,expires_at)
       values((p_data->>'id')::uuid,p_club,p_actor,p_data->>'hash',club.approval_required or (p_data->>'approval')::boolean,(p_data->>'expires')::timestamptz) on conflict(id) do nothing;
     select * into invitation from public.app_tea_club_invites where id=(p_data->>'id')::uuid;
     if invitation.club_id<>p_club or invitation.created_by<>p_actor or invitation.token_hash<>p_data->>'hash' or invitation.expires_at is distinct from (p_data->>'expires')::timestamptz or invitation.requires_approval is distinct from (club.approval_required or (p_data->>'approval')::boolean) then raise exception 'TEA_CLUB_CONFLICT'; end if;
     return to_jsonb(invitation)-'token_hash';
   elsif p_action='revokeInvite' then
     update public.app_tea_club_invites set revoked_at=coalesce(revoked_at,now()) where id=(p_data->>'id')::uuid and club_id=p_club;
     if not found then raise exception 'TEA_CLUB_UNAVAILABLE'; end if;
   elsif p_action='inviteRequests' then
     select coalesce(jsonb_agg(q.value order by q.created_at desc,q.id desc),'[]') into result from (
       select r.created_at,r.invite_id::text||':'||r.user_id id,jsonb_build_object('id',r.invite_id::text||':'||r.user_id,'createdAt',r.created_at,'inviteId',r.invite_id,'userId',r.user_id,'name',coalesce(u.full_name,u.username),'status',r.status) value
       from public.app_tea_club_invite_requests r join public.app_tea_club_invites i on i.id=r.invite_id join public.app_users u on u.id=r.user_id where i.club_id=p_club and r.status='pending'
       and (p_data->>'before' is null or (r.created_at,r.invite_id::text||':'||r.user_id)<((p_data->>'before')::timestamptz,p_data->>'boundary'))
       order by r.created_at desc,r.invite_id::text||':'||r.user_id desc limit 51) q; return result;
   elsif p_action='decideInvite' then
     if exists(select 1 from public.app_tea_club_invite_requests r join public.app_tea_club_invites i on i.id=r.invite_id where i.club_id=p_club and r.invite_id=(p_data->>'id')::uuid and r.user_id=p_data->>'user'
       and r.status not in ('pending',case when (p_data->>'approve')::boolean then 'approved' else 'denied' end)) then raise exception 'TEA_CLUB_CONFLICT'; end if;
     update public.app_tea_club_invite_requests r set status=case when (p_data->>'approve')::boolean then 'approved' else 'denied' end,decided_by=p_actor,decided_at=now()
     from public.app_tea_club_invites i where i.id=r.invite_id and i.club_id=p_club and r.invite_id=(p_data->>'id')::uuid and r.user_id=p_data->>'user';
     if not found then raise exception 'TEA_CLUB_UNAVAILABLE'; end if;
   elsif p_action in ('removeMember','memberRole') then
     target:=p_data->>'user';
     if not exists(select 1 from public.app_group_chat_members where group_id=gid and user_id=target and role<>'owner') then raise exception 'TEA_CLUB_FORBIDDEN'; end if;
     if p_action='memberRole' then
       if member.role<>'owner' or p_data->>'role' not in ('admin','member') then raise exception 'TEA_CLUB_FORBIDDEN'; end if;
       update public.app_group_chat_members set role=p_data->>'role' where group_id=gid and user_id=target;
     else
       if member.role<>'owner' and exists(select 1 from public.app_group_chat_members where group_id=gid and user_id=target and role='admin') then raise exception 'TEA_CLUB_FORBIDDEN'; end if;
       delete from public.app_group_chat_members where group_id=gid and user_id=target;
     end if;
   else raise exception 'TEA_CLUB_INVALID'; end if;
 end if;
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.captro_tea_club(text,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.captro_tea_club(text,uuid,text,jsonb) to service_role;

-- A valid invite supplies a route to the EXISTING join/payment flow, not membership.
create function public.captro_tea_invite(p_actor text,p_hash text,p_accept boolean default false) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare i public.app_tea_club_invites; c public.app_purchasables; a public.app_users; request_status text; begin
 select * into i from public.app_tea_club_invites where token_hash=p_hash for update;
 if i.id is null then raise exception 'TEA_INVITE_INVALID'; end if;
 if i.revoked_at is not null then raise exception 'TEA_INVITE_REVOKED'; end if;
 if i.expires_at<=now() then raise exception 'TEA_INVITE_EXPIRED'; end if;
 select * into c from public.app_purchasables where id=i.club_id and status in ('active','sold_out');
 if c.id is null then raise exception 'TEA_CLUB_UNAVAILABLE'; end if;
 select * into a from public.app_users where id=p_actor and coalesce(metadata->>'status','active')='active';
 if a.id is null then raise exception 'TEA_CLUB_FORBIDDEN'; end if;
 if exists(select 1 from public.app_blocks b where (b.blocker_id in (p_actor,a.supabase_user_id::text) and b.blocked_id in (c.creator_app_user_id,c.creator_id::text)) or (b.blocked_id in (p_actor,a.supabase_user_id::text) and b.blocker_id in (c.creator_app_user_id,c.creator_id::text))) then raise exception 'TEA_CLUB_UNAVAILABLE'; end if;
 if exists(select 1 from public.app_group_chat_members where group_id=c.private_config->>'group_chat_id' and user_id=p_actor) then
   return jsonb_build_object('state','member','clubId',c.id,'name',c.title,'postId',c.post_id); end if;
 if i.requires_approval and p_accept then
   insert into public.app_tea_club_invite_requests(invite_id,user_id) values(i.id,p_actor) on conflict do nothing;
 end if;
 select status into request_status from public.app_tea_club_invite_requests where invite_id=i.id and user_id=p_actor;
 return jsonb_build_object('state',case when i.requires_approval and request_status is distinct from 'approved' then coalesce(request_status,'approval_required') else 'continue_to_join' end,
   'clubId',c.id,'name',c.title,'postId',c.post_id,'requiresApproval',i.requires_approval);
end $$;
revoke all on function public.captro_tea_invite(text,text,boolean) from public,anon,authenticated;
grant execute on function public.captro_tea_invite(text,text,boolean) to service_role;
commit;
