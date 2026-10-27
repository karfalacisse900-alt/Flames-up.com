-- Categorize Creator Support in the existing per-creator finance ledger.
-- This changes no balances, cash movement, entitlements or rollout switches.
begin;
create or replace function public.captro_finance_category(kind text) returns text
language sql immutable set search_path=public as $$
 select case when kind='creator_support' then 'creator_support'
 when kind in ('event','party','ticket','access_pass') then 'event'
 when kind in ('club','meetup','deal') then kind
 when kind in ('group','group_access') then 'group_access'
 when kind in ('offer','booking','reservation','local_offer') then 'local_offer'
 else 'unassigned' end;
$$;
revoke all on function public.captro_finance_category(text) from public,anon,authenticated;
grant execute on function public.captro_finance_category(text) to service_role;
commit;
