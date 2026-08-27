-- Captro now exposes one global Wall of Notes. Retain legacy columns for safe
-- rollback/client compatibility, but remove their data and prevent regional rows.

begin;

update public.wall_notes
set
  world_x = world_x + case wall_id
    when 'nearby' then 1200
    when 'new_york_city' then -1200
    else 0
  end,
  world_y = world_y + case wall_id
    when 'brooklyn' then 1200
    when 'upper_manhattan' then -1200
    else 0
  end,
  wall_id = 'global',
  category = case when category = 'local_recommendation' then null else category end,
  approximate_location = null,
  location_label = null,
  location_city = null,
  location_country = null,
  location_cell = null,
  location_lat_bucket = null,
  location_lng_bucket = null,
  location_visibility = false,
  updated_at = now()
where wall_id <> 'global'
   or category = 'local_recommendation'
   or approximate_location is not null
   or location_label is not null
   or location_city is not null
   or location_country is not null
   or location_cell is not null
   or location_lat_bucket is not null
   or location_lng_bucket is not null
   or location_visibility = true;

delete from public.wall_layout_state
where wall_id <> 'global';

insert into public.wall_layout_state (wall_id, next_slot, updated_at)
select
  'global',
  count(*)::bigint,
  now()
from public.wall_notes
where status = 'active'
  and moderation_status = 'approved'
on conflict (wall_id) do update
set
  next_slot = greatest(public.wall_layout_state.next_slot, excluded.next_slot),
  updated_at = now();

alter table public.wall_notes
  drop constraint if exists wall_notes_global_wall_check;

alter table public.wall_notes
  add constraint wall_notes_global_wall_check
  check (wall_id = 'global') not valid;

alter table public.wall_notes
  validate constraint wall_notes_global_wall_check;

comment on column public.wall_notes.wall_id is
  'Compatibility field constrained to global. Captro has one Wall of Notes.';

comment on column public.wall_notes.approximate_location is
  'Retained for rollback compatibility. Captro no longer collects or exposes Wall note location.';

commit;
