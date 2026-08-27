-- Aura social meetup participation. Community data remains off-chain; paid
-- meetup entry is deliberately not accepted by this function until an exact,
-- confirmed Aura transaction can be bound to the join.

create table if not exists public.aura_meetup_joins (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.app_posts(id) on delete cascade,
  app_user_id text not null references public.app_users(id) on delete cascade,
  status text not null default 'confirmed'
    check (status = any (array['confirmed'::text, 'cancelled'::text])),
  payment_txid text,
  joined_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (post_id, app_user_id)
);

comment on table public.aura_meetup_joins is
  'Server-managed Aura social meetup participation. Paid joins require a separately verified confirmed AUR transaction.';
comment on column public.aura_meetup_joins.payment_txid is
  'Reserved for an exact confirmed Aura payment transaction. Never populated from a client claim alone.';

create index if not exists aura_meetup_joins_post_status_idx
  on public.aura_meetup_joins (post_id, status, joined_at);
create index if not exists aura_meetup_joins_user_status_idx
  on public.aura_meetup_joins (app_user_id, status, joined_at desc);
create unique index if not exists aura_meetup_joins_payment_txid_idx
  on public.aura_meetup_joins (payment_txid)
  where payment_txid is not null;

alter table public.aura_meetup_joins enable row level security;
revoke all on table public.aura_meetup_joins from public, anon, authenticated;
grant select, insert, update, delete on table public.aura_meetup_joins to service_role;

create or replace function public.aura_join_free_meetup(
  p_post_id text,
  p_app_user_id text
)
returns table(join_id uuid, joined_at timestamptz)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_post public.app_posts%rowtype;
  v_join public.aura_meetup_joins%rowtype;
  v_entry_type text;
  v_capacity_text text;
  v_capacity integer;
  v_joined integer;
begin
  if coalesce(length(trim(p_post_id)), 0) = 0
     or coalesce(length(trim(p_app_user_id)), 0) = 0 then
    raise exception using errcode = '22023', message = 'INVALID_MEETUP_JOIN_INPUT';
  end if;

  select *
    into v_post
    from public.app_posts
   where legacy_post_id = p_post_id
      or id::text = p_post_id
   limit 1
   for update;

  if not found or v_post.status <> 'active' or v_post.post_type <> 'meetup' then
    raise exception using errcode = '22023', message = 'MEETUP_NOT_FOUND';
  end if;

  v_entry_type := lower(coalesce(v_post.metadata #>> '{community,entry_type}', 'free'));
  if v_entry_type <> 'free' then
    raise exception using errcode = '22023', message = 'PAID_MEETUP_REQUIRES_CONFIRMED_AUR';
  end if;

  select *
    into v_join
    from public.aura_meetup_joins
   where post_id = v_post.id
     and app_user_id = p_app_user_id
   for update;

  if found and v_join.status = 'confirmed' then
    return query select v_join.id, v_join.joined_at;
    return;
  end if;

  v_capacity_text := coalesce(v_post.metadata #>> '{community,max_people}', '50');
  v_capacity := case
    when v_capacity_text ~ '^[0-9]{1,3}$' then greatest(2, least(500, v_capacity_text::integer))
    else 50
  end;

  select count(*)::integer
    into v_joined
    from public.aura_meetup_joins
   where post_id = v_post.id
     and status = 'confirmed';

  if v_joined >= v_capacity then
    raise exception using errcode = '22023', message = 'MEETUP_FULL';
  end if;

  insert into public.aura_meetup_joins (post_id, app_user_id, status, payment_txid, joined_at, updated_at)
  values (v_post.id, p_app_user_id, 'confirmed', null, now(), now())
  on conflict (post_id, app_user_id) do update
    set status = 'confirmed',
        payment_txid = null,
        joined_at = now(),
        updated_at = now()
  returning * into v_join;

  return query select v_join.id, v_join.joined_at;
end;
$$;

revoke all on function public.aura_join_free_meetup(text, text) from public, anon, authenticated;
grant execute on function public.aura_join_free_meetup(text, text) to service_role;

notify pgrst, 'reload schema';
