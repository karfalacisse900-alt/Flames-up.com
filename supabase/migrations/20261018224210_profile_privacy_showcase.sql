-- Deploy only with the matching Worker, after the earlier authorization hardening.
-- Existing relationships are retained. No membership or financial data changes.
begin;
revoke all on public.app_follows from public, anon, authenticated;

create or replace function public.captro_profile_follow(p_actor text, p_target text, p_action text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  actor_row public.app_users%rowtype;
  target_row public.app_users%rowtype;
  follower text;
  following text;
  current_status text;
  next_status text;
begin
  if p_actor = p_target or p_action not in ('follow','unfollow','approve','decline') then
    raise exception 'PROFILE_INVALID_ACTION';
  end if;
  -- Canonical ordered row locks also serialize competing decisions and requests.
  perform 1 from public.app_users where id in (p_actor,p_target) order by id for update;
  select * into actor_row from public.app_users where id=p_actor;
  select * into target_row from public.app_users where id=p_target;
  if actor_row.id is null or target_row.id is null
     or coalesce(actor_row.metadata->>'status','active') <> 'active'
     or coalesce(target_row.metadata->>'status','active') <> 'active' then
    raise exception 'PROFILE_UNAVAILABLE';
  end if;
  if exists(select 1 from public.app_blocks where
      (blocker_id=p_actor and blocked_id=p_target) or (blocker_id=p_target and blocked_id=p_actor)) then
    raise exception 'PROFILE_BLOCKED';
  end if;
  follower := case when p_action in ('approve','decline') then p_target else p_actor end;
  following := case when p_action in ('approve','decline') then p_actor else p_target end;
  select status into current_status from public.app_follows
    where app_follower_id=follower and app_following_id=following;
  if p_action in ('unfollow','decline') then
    if p_action='unfollow' or current_status='pending' then
      delete from public.app_follows where app_follower_id=follower and app_following_id=following;
      current_status := null;
    end if;
    return jsonb_build_object('following',coalesce(current_status='active',false),'follow_pending',false);
  end if;
  if p_action='approve' then
    if current_status='active' then return jsonb_build_object('following',true,'follow_pending',false); end if;
    if current_status is distinct from 'pending' then raise exception 'PROFILE_REQUEST_MISSING'; end if;
    next_status := 'active';
  else
    next_status := case when current_status='active' or not target_row.is_private then 'active' else 'pending' end;
  end if;
  insert into public.app_follows(app_follower_id,app_following_id,status)
    values(follower,following,next_status)
    on conflict(app_follower_id,app_following_id) do update set status=excluded.status,updated_at=now();
  return jsonb_build_object('following',next_status='active','follow_pending',next_status='pending');
end $$;
revoke all on function public.captro_profile_follow(text,text,text) from public,anon,authenticated;
grant execute on function public.captro_profile_follow(text,text,text) to service_role;

create or replace function public.captro_profile_showcase(p_actor text, p_patch jsonb)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare owner_row public.app_users%rowtype; item text; items jsonb; result jsonb;
begin
  if jsonb_typeof(p_patch) <> 'object' or exists(select 1 from jsonb_object_keys(p_patch) k where k not in ('pinned_post_id','club_post_ids')) then
    raise exception 'PROFILE_INVALID_FIELDS';
  end if;
  select * into owner_row from public.app_users where id=p_actor for update;
  if owner_row.id is null or coalesce(owner_row.metadata->>'status','active') <> 'active' then raise exception 'PROFILE_UNAVAILABLE'; end if;
  if p_patch ? 'club_post_ids' and (jsonb_typeof(p_patch->'club_post_ids') <> 'array' or jsonb_array_length(p_patch->'club_post_ids') > 12) then
    raise exception 'PROFILE_INVALID_CLUBS';
  end if;
  items := coalesce(p_patch->'club_post_ids','[]'::jsonb);
  if nullif(p_patch->>'pinned_post_id','') is not null then items := items || jsonb_build_array(p_patch->>'pinned_post_id'); end if;
  for item in select jsonb_array_elements_text(items) loop
    if not exists(select 1 from public.app_posts p where p.app_user_id=p_actor and p.status='active'
        and (p.legacy_post_id=item or to_jsonb(p)->>'id'=item)) then raise exception 'PROFILE_ITEM_NOT_OWNED'; end if;
  end loop;
  for item in select jsonb_array_elements_text(coalesce(p_patch->'club_post_ids','[]'::jsonb)) loop
    if not exists(select 1 from public.app_posts p where p.app_user_id=p_actor and p.status='active'
        and (p.legacy_post_id=item or to_jsonb(p)->>'id'=item) and p.post_type in ('club','group','group_access')) then
      raise exception 'PROFILE_ITEM_NOT_CLUB';
    end if;
  end loop;
  result := coalesce(owner_row.profile,'{}'::jsonb) || p_patch;
  update public.app_users set profile=result,updated_at=now() where id=p_actor;
  return jsonb_build_object('pinned_post_id',result->'pinned_post_id','club_post_ids',coalesce(result->'club_post_ids','[]'::jsonb));
end $$;
revoke all on function public.captro_profile_showcase(text,jsonb) from public,anon,authenticated;
grant execute on function public.captro_profile_showcase(text,jsonb) to service_role;
commit;
