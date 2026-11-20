-- Add a bounded sentence-range read to the existing reply API. Old exact-target clients remain compatible.
begin;
create or replace function public.captro_tea_target_replies(p_viewer text,p_id uuid,p_target text,
 p_before timestamptz default null,p_boundary uuid default null,p_snapshot timestamptz default now()) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare result jsonb; grouped boolean := left(p_target,9)='sentence:';
 v integer; lo integer; hi integer;
 begin
 if grouped then
   if p_target !~ '^sentence:[1-9][0-9]*:[0-9]+:[0-9]+$' then raise exception 'TEA_DISCUSSION_INVALID'; end if;
   v := split_part(p_target,':',2)::integer; lo := split_part(p_target,':',3)::integer; hi := split_part(p_target,':',4)::integer;
   if hi<=lo then raise exception 'TEA_DISCUSSION_INVALID'; end if;
 end if;
 if not exists(select 1 from public.app_tea_conversations p where p.id=p_id and p.status='active' and public.captro_tea_author_visible(p_viewer,p.author_id)) then raise exception 'TEA_DISCUSSION_UNAVAILABLE'; end if;
 select coalesce(jsonb_agg(q.value order by q.created_at,q.id),'[]') into result from (
   select r.created_at,r.id,jsonb_build_object('id',r.id,'body',r.body,'target',r.target,'createdAt',r.created_at,
     'author',jsonb_build_object('id',u.id,'name',coalesce(nullif(u.full_name,''),nullif(u.username,''),'Captro member'),'username',coalesce(u.username,''))) value
   from public.app_tea_replies r join public.app_users u on u.id=r.author_id
   where r.conversation_id=p_id and r.status='active' and r.created_at<=p_snapshot
     and ((p_target='general' and r.target is null) or r.target->>'id'=p_target
       or (grouped and (r.target->>'version')::integer=v
         and (r.target->>'start')::integer>=lo and (r.target->>'end')::integer<=hi))
     and (p_before is null or (r.created_at,r.id)>(p_before,p_boundary))
     and public.captro_tea_author_visible(p_viewer,r.author_id)
   order by r.created_at,r.id limit case when grouped then 6 else 21 end) q;
 return result;
end $$;
revoke all on function public.captro_tea_target_replies(text,uuid,text,timestamptz,uuid,timestamptz) from public,anon,authenticated;
grant execute on function public.captro_tea_target_replies(text,uuid,text,timestamptz,uuid,timestamptz) to service_role;

commit;
