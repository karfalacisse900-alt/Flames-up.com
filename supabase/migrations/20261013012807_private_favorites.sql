-- Extends canonical app_post_interactions(kind='save'); does not create a second save list.
-- Access is through authenticated Worker routes, never direct client table/RPC access.
create table public.app_favorite_collections (
  id uuid primary key default gen_random_uuid(),
  owner_id text not null references public.app_users(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 80),
  created_at timestamptz not null default now(),
  unique(owner_id,id)
);
create unique index app_favorite_collection_name on public.app_favorite_collections(owner_id,lower(name));
create table public.app_favorite_revisions (
  owner_id text not null references public.app_users(id) on delete cascade,
  post_key text not null,
  revision bigint not null default 0,
  last_request uuid,
  primary key(owner_id,post_key)
);
create table public.app_favorite_memberships (
  owner_id text not null,
  collection_id uuid not null,
  post_key text not null,
  primary key(owner_id,collection_id,post_key),
  foreign key(owner_id,collection_id) references public.app_favorite_collections(owner_id,id) on delete cascade,
  foreign key(owner_id,post_key) references public.app_favorite_revisions(owner_id,post_key) on delete cascade
);
create index app_favorite_membership_post on public.app_favorite_memberships(owner_id,post_key);
alter table public.app_favorite_collections enable row level security;
alter table public.app_favorite_revisions enable row level security;
alter table public.app_favorite_memberships enable row level security;
revoke all on public.app_favorite_collections,public.app_favorite_revisions,public.app_favorite_memberships from public,anon,authenticated;
grant select,insert,update,delete on public.app_favorite_collections,public.app_favorite_revisions,public.app_favorite_memberships to service_role;

create function public.captro_favorites(p_owner text,p_identity jsonb,p_action text,p_input jsonb default '{}'::jsonb)
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare
  r record; v_collection uuid; v_post text := p_input->>'post_key';
  v_ids uuid[]; v_revision bigint; v_request uuid := (p_input->>'request_id')::uuid;
  v_expected bigint := (p_input->>'expected_revision')::bigint;
  v_saved boolean; v_created timestamptz; v_state jsonb := null; v_collections jsonb; v_posts jsonb;
  v_offset integer := greatest(0,coalesce((p_input->>'offset')::integer,0));
  v_name text := btrim(p_input->>'name'); v_last uuid; v_count integer;
begin
  if coalesce(p_owner,'')='' or coalesce(p_identity->>'actor_key','')='' then
    raise exception 'FAVORITES_INVALID_OWNER';
  end if;
  -- Serializes writes/initial legacy import and collection deletion for one account,
  -- not the whole database. Transaction lock is always released on rollback.
  perform pg_advisory_xact_lock(hashtextextended('favorites:'||p_owner,0));
  -- Import each existing save's single legacy collection once, without deleting saves.
  for r in
    select distinct on (coalesce(i.legacy_post_id,i.post_id::text))
      coalesce(i.legacy_post_id,i.post_id::text) as post_key,i.collection
    from public.app_post_interactions i
    where i.kind='save' and (i.app_user_id in (select jsonb_array_elements_text(p_identity->'app_ids'))
      or i.user_id::text in (select jsonb_array_elements_text(p_identity->'auth_ids'))
      or i.actor_key in (select jsonb_array_elements_text(p_identity->'actor_keys')))
      and not exists(select 1 from public.app_favorite_revisions s where s.owner_id=p_owner
        and s.post_key=coalesce(i.legacy_post_id,i.post_id::text))
  loop
    insert into public.app_favorite_revisions(owner_id,post_key) values(p_owner,r.post_key) on conflict do nothing;
    if btrim(coalesce(r.collection,''))<>'' and lower(btrim(r.collection)) not in ('saved','bookmarks','favorites') then
      insert into public.app_favorite_collections(owner_id,name) values(p_owner,btrim(r.collection)) on conflict do nothing;
      select id into v_collection from public.app_favorite_collections where owner_id=p_owner and lower(name)=lower(btrim(r.collection));
      insert into public.app_favorite_memberships values(p_owner,v_collection,r.post_key) on conflict do nothing;
    end if;
  end loop;
  if p_action in ('create','rename') then
    if v_name is null or char_length(v_name) not between 1 and 80 then raise exception 'FAVORITES_INVALID_NAME'; end if;
    if p_action='create' then
      select count(*) into v_count from public.app_favorite_collections where owner_id=p_owner;
      if v_count>=100 then raise exception 'FAVORITES_COLLECTION_LIMIT'; end if;
      insert into public.app_favorite_collections(owner_id,name) values(p_owner,v_name);
    else
      update public.app_favorite_collections set name=v_name where owner_id=p_owner and id=(p_input->>'collection_id')::uuid;
      if not found then raise exception 'FAVORITES_COLLECTION_NOT_FOUND'; end if;
    end if;
  elsif p_action='delete' then
    -- Memberships cascade, canonical saves do not. Increment affected post revisions
    -- so an old picker/Undo cannot silently revive a deleted collection.
    update public.app_favorite_revisions s set revision=revision+1,last_request=null where s.owner_id=p_owner
      and exists(select 1 from public.app_favorite_memberships m where m.owner_id=p_owner
        and m.post_key=s.post_key and m.collection_id=(p_input->>'collection_id')::uuid);
    delete from public.app_favorite_collections where owner_id=p_owner and id=(p_input->>'collection_id')::uuid;
    if not found then raise exception 'FAVORITES_COLLECTION_NOT_FOUND'; end if;
  elsif p_action not in ('read','set') then raise exception 'FAVORITES_INVALID_ACTION';
  end if;
  if v_post is not null then
    insert into public.app_favorite_revisions(owner_id,post_key) values(p_owner,v_post) on conflict do nothing;
    select revision,last_request into v_revision,v_last from public.app_favorite_revisions where owner_id=p_owner and post_key=v_post;
    if p_action='set' and (v_request is null or v_last is distinct from v_request) then
      if v_expected is not null and v_expected<>v_revision then raise exception 'FAVORITES_CONFLICT'; end if;
      if jsonb_typeof(p_input->'saved') is distinct from 'boolean' then raise exception 'FAVORITES_INVALID_STATE'; end if;
      v_saved := (p_input->>'saved')::boolean;
      if p_input ? 'collection_ids' then
        select coalesce(array_agg(distinct x::uuid),'{}'::uuid[]) into v_ids from jsonb_array_elements_text(p_input->'collection_ids') x;
        if cardinality(v_ids)>20 then raise exception 'FAVORITES_MEMBERSHIP_LIMIT'; end if;
        if exists(select 1 from unnest(v_ids) x where not exists(select 1 from public.app_favorite_collections c where c.owner_id=p_owner and c.id=x)) then
          raise exception 'FAVORITES_COLLECTION_NOT_FOUND';
        end if;
      end if;
      select min(created_at) into v_created from public.app_post_interactions i where i.kind='save'
        and (i.legacy_post_id=v_post or i.post_id::text=p_input->>'post_uuid')
        and (i.app_user_id in(select jsonb_array_elements_text(p_identity->'app_ids'))
          or i.user_id::text in(select jsonb_array_elements_text(p_identity->'auth_ids'))
          or i.actor_key in(select jsonb_array_elements_text(p_identity->'actor_keys')));
      delete from public.app_post_interactions i where i.kind='save'
        and (i.legacy_post_id=v_post or i.post_id::text=p_input->>'post_uuid')
        and (i.app_user_id in(select jsonb_array_elements_text(p_identity->'app_ids'))
          or i.user_id::text in(select jsonb_array_elements_text(p_identity->'auth_ids'))
          or i.actor_key in(select jsonb_array_elements_text(p_identity->'actor_keys')));
      if v_saved then
        insert into public.app_post_interactions(legacy_post_id,post_id,app_user_id,user_id,kind,collection,actor_key,created_at)
        values(v_post,(p_input->>'post_uuid')::uuid,p_owner,(p_identity->>'auth_id')::uuid,'save',
          coalesce(p_input->>'legacy_collection','saved'),p_identity->>'actor_key',coalesce(v_created,now()));
      end if;
      if not v_saved or v_ids is not null then
        delete from public.app_favorite_memberships where owner_id=p_owner and post_key=v_post;
      end if;
      if v_saved and v_ids is not null then
        insert into public.app_favorite_memberships select p_owner,x,v_post from unnest(v_ids) x;
      elsif v_saved and btrim(coalesce(p_input->>'legacy_collection',''))<>''
        and lower(btrim(p_input->>'legacy_collection')) not in ('saved','bookmarks','favorites') then
        insert into public.app_favorite_collections(owner_id,name) values(p_owner,btrim(p_input->>'legacy_collection')) on conflict do nothing;
        select id into v_collection from public.app_favorite_collections where owner_id=p_owner and lower(name)=lower(btrim(p_input->>'legacy_collection'));
        insert into public.app_favorite_memberships values(p_owner,v_collection,v_post) on conflict do nothing;
      end if;
      update public.app_favorite_revisions set revision=revision+1,last_request=v_request where owner_id=p_owner and post_key=v_post;
    end if;
    select jsonb_build_object('post_id',v_post,'revision',s.revision,
      'saved',exists(select 1 from public.app_post_interactions i where i.kind='save'
        and (i.legacy_post_id=v_post or i.post_id::text=p_input->>'post_uuid')
        and (i.app_user_id in(select jsonb_array_elements_text(p_identity->'app_ids'))
          or i.user_id::text in(select jsonb_array_elements_text(p_identity->'auth_ids'))
          or i.actor_key in(select jsonb_array_elements_text(p_identity->'actor_keys')))),
      'collection_ids',coalesce((select jsonb_agg(m.collection_id order by m.collection_id) from public.app_favorite_memberships m
        where m.owner_id=p_owner and m.post_key=v_post),'[]')) into v_state
    from public.app_favorite_revisions s where s.owner_id=p_owner and s.post_key=v_post;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,
    'count',(select count(*) from public.app_favorite_memberships m where m.owner_id=p_owner and m.collection_id=c.id),
    'preview_post_ids',(select coalesce(jsonb_agg(q.post_key),'[]') from (select m.post_key from public.app_favorite_memberships m
      where m.owner_id=p_owner and m.collection_id=c.id order by m.post_key limit 3) q)) order by lower(c.name)),'[]')
    into v_collections from public.app_favorite_collections c where c.owner_id=p_owner;
  if p_action='read' and v_post is null then
    if p_input ? 'collection_id' and not exists(select 1 from public.app_favorite_collections where owner_id=p_owner and id=(p_input->>'collection_id')::uuid) then
      raise exception 'FAVORITES_COLLECTION_NOT_FOUND';
    end if;
    select coalesce(jsonb_agg(q.post_key order by q.saved_at desc,q.post_key),'[]') into v_posts from (
      select coalesce(i.legacy_post_id,i.post_id::text) post_key,max(i.created_at) saved_at
      from public.app_post_interactions i where i.kind='save'
        and (i.app_user_id in(select jsonb_array_elements_text(p_identity->'app_ids'))
          or i.user_id::text in(select jsonb_array_elements_text(p_identity->'auth_ids'))
          or i.actor_key in(select jsonb_array_elements_text(p_identity->'actor_keys')))
        and (not p_input ? 'collection_id' or exists(select 1 from public.app_favorite_memberships m where m.owner_id=p_owner
          and m.collection_id=(p_input->>'collection_id')::uuid and m.post_key=coalesce(i.legacy_post_id,i.post_id::text)))
      group by coalesce(i.legacy_post_id,i.post_id::text) order by saved_at desc,post_key limit 41 offset v_offset
    ) q;
  end if;
  return jsonb_build_object('state',v_state,'collections',v_collections,'post_ids',coalesce(v_posts,'[]'));
end $$;
revoke all on function public.captro_favorites(text,jsonb,text,jsonb) from public,anon,authenticated;
grant execute on function public.captro_favorites(text,jsonb,text,jsonb) to service_role;
