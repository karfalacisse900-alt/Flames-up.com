// Read-only release gate. Verifies the creator-scoped projections are present
// and service-role-only; it never reads customer ledger rows or payment data.
const query = `
with expected(name) as (values ('app_creator_finance_orders'),('app_creator_finance_pools'),('app_creator_finance_payouts'))
select e.name check_id,
  coalesce(c.relkind='v' and c.reloptions @> array['security_invoker=true']
    and has_table_privilege('service_role',c.oid,'SELECT')
    and not has_table_privilege('authenticated',c.oid,'SELECT')
    and not has_table_privilege('anon',c.oid,'SELECT'),false) passed
from expected e left join pg_class c on c.oid=to_regclass('public.'||e.name)
order by e.name;
`;
const { SUPABASE_PROJECT_REF: ref, SUPABASE_ACCESS_TOKEN: token } = process.env;
if (ref !== 'cclgvxukwccvtgrbcwie' || !token) throw Error('Captro earnings schema verification credentials unavailable');
const response = await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
  method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({ query, read_only: true }), signal: AbortSignal.timeout(20000),
});
if (!response.ok) throw Error(`Earnings schema verification HTTP ${response.status}`);
const rows = await response.json();
if (!Array.isArray(rows) || rows.length !== 3 || rows.some(row => row.passed !== true))
  throw Error('Creator earnings views are missing or are not safely service-role-only.');
console.log('PASS: three creator earnings views exist, use security_invoker, and are service-role-only.');
