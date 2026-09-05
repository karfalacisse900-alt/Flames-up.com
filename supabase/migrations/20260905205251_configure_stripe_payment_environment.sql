-- Bind a database ledger to exactly one Stripe environment. Once the row has
-- been created it can only be read again with the same mode; moving a ledger
-- between test and live would mix provider references and is forbidden.
create or replace function public.captro_configure_payment_environment(p_stripe_mode text)
returns public.app_payment_environment
language plpgsql
set search_path = public
as $$
declare
  configured_row public.app_payment_environment%rowtype;
begin
  if p_stripe_mode not in ('test', 'live') then
    raise exception 'STRIPE_DATABASE_MODE_INVALID';
  end if;

  insert into public.app_payment_environment (id, stripe_mode)
    values (true, p_stripe_mode)
  on conflict (id) do update
    set stripe_mode = public.app_payment_environment.stripe_mode
    where public.app_payment_environment.stripe_mode = excluded.stripe_mode
  returning * into configured_row;

  if configured_row.id is null then
    raise exception 'STRIPE_DATABASE_MODE_MISMATCH';
  end if;
  return configured_row;
end;
$$;

revoke all on function public.captro_configure_payment_environment(text) from public, anon, authenticated;
grant execute on function public.captro_configure_payment_environment(text) to service_role;
