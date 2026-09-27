-- Additive guard. No historical dates, orders or event statuses are changed.
-- All creation routes are checked under the same item lock as capacity reservation.
create function public.captro_guard_new_purchase_dates()
returns trigger language plpgsql security invoker set search_path = public as $$
declare item public.app_purchasables%rowtype;
begin
  select * into item from public.app_purchasables where id = new.purchasable_id for update;
  if not found then raise exception 'CAPTRO_ITEM_UNAVAILABLE'; end if;
  if item.expires_at is not null and item.expires_at <= now() then
    raise exception 'CAPTRO_ITEM_EXPIRED';
  end if;
  if item.content_type in ('event','meetup','party') and item.ends_at is not null and item.ends_at <= now() then
    raise exception 'CAPTRO_EVENT_ENDED';
  end if;
  return new;
end;
$$;
revoke all on function public.captro_guard_new_purchase_dates() from public, anon, authenticated;
create trigger captro_guard_new_purchase_dates
  before insert on public.app_purchases
  for each row execute function public.captro_guard_new_purchase_dates();
