-- One-time repair for the first low-density Captro walls created before the
-- growing-cluster placement algorithm shipped. This deliberately affects only
-- walls with five or fewer active notes whose coordinates are still tightly
-- stacked. After this migration, every placement remains permanent.

with wall_density as (
  select
    wall_id,
    count(*) as note_count,
    max(world_x) - min(world_x) as spread_x,
    max(world_y) - min(world_y) as spread_y
  from public.wall_notes
  where status = 'active' and moderation_status = 'approved'
  group by wall_id
  having count(*) between 2 and 5
),
ranked as (
  select
    n.id,
    n.wall_id,
    row_number() over (partition by n.wall_id order by n.created_at, n.id) - 1 as slot
  from public.wall_notes n
  join wall_density d on d.wall_id = n.wall_id
  where n.status = 'active'
    and n.moderation_status = 'approved'
    and d.spread_x < 360
    and d.spread_y < 360
    and coalesce(n.metadata ->> 'layout_version', '') <> 'growing_cluster_v1'
),
layout(slot, x, y, rotation) as (
  values
    (0::bigint, -205::double precision, -55::double precision, -1.4::double precision),
    (1::bigint,   20::double precision, -165::double precision,  1.8::double precision),
    (2::bigint,   55::double precision,   80::double precision, -0.8::double precision),
    (3::bigint, -235::double precision,  170::double precision,  2.2::double precision),
    (4::bigint,  275::double precision,   15::double precision, -2.0::double precision)
)
update public.wall_notes n
set
  world_x = l.x,
  world_y = l.y,
  rotation = l.rotation,
  metadata = coalesce(n.metadata, '{}'::jsonb) || jsonb_build_object('layout_version', 'growing_cluster_v1'),
  updated_at = now()
from ranked r
join layout l on l.slot = r.slot
where n.id = r.id;

comment on table public.wall_notes is
  'Captro two-dimensional Wall of Notes. Positions are permanent after server-side growing-cluster placement; Ghost ownership remains private.';

create table if not exists public.wall_layout_state (
  wall_id text primary key,
  next_slot bigint not null default 0 check (next_slot >= 0),
  updated_at timestamptz not null default now()
);

alter table public.wall_layout_state enable row level security;
revoke all on public.wall_layout_state from anon, authenticated;

create or replace function public.captro_claim_wall_slot(p_wall_id text)
returns bigint
language plpgsql
security invoker
set search_path = public
as $$
declare
  claimed bigint;
  active_count bigint;
begin
  insert into public.wall_layout_state (wall_id, next_slot)
  values (p_wall_id, 0)
  on conflict (wall_id) do nothing;

  select next_slot into claimed
  from public.wall_layout_state
  where wall_id = p_wall_id
  for update;

  select count(*) into active_count
  from public.wall_notes
  where wall_id = p_wall_id
    and status = 'active'
    and moderation_status = 'approved';

  claimed := greatest(coalesce(claimed, 0), coalesce(active_count, 0));
  update public.wall_layout_state
  set next_slot = claimed + 1, updated_at = now()
  where wall_id = p_wall_id;
  return claimed;
end;
$$;

revoke all on function public.captro_claim_wall_slot(text) from public, anon, authenticated;
grant execute on function public.captro_claim_wall_slot(text) to service_role;

create or replace function public.captro_wall_overview(p_wall_id text)
returns table (
  total_count bigint,
  min_x double precision,
  max_x double precision,
  min_y double precision,
  max_y double precision
)
language sql
stable
security invoker
set search_path = public
as $$
  select
    count(*)::bigint,
    min(world_x),
    max(world_x + width),
    min(world_y),
    max(world_y + height)
  from public.wall_notes
  where wall_id = p_wall_id
    and status = 'active'
    and moderation_status = 'approved';
$$;

revoke all on function public.captro_wall_overview(text) from public, anon, authenticated;
grant execute on function public.captro_wall_overview(text) to service_role;

comment on function public.captro_wall_overview(text) is
  'Returns compact density and bounds data for adaptive iOS Wall of Notes framing.';

comment on table public.wall_layout_state is
  'Internal Supabase placement cursor that prevents concurrent Wall of Notes uploads from claiming the same historical slot.';
