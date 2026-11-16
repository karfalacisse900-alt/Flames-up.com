import { pathToFileURL } from 'node:url';

// Catalog-only prerequisite for this native branch. It does not deploy anything
// or establish Worker compatibility, payment readiness, or device acceptance.
export const releaseMigrations = Object.freeze([
  '20261112030025', '20261115014511', '20261115015247', '20261115224938',
]);
const tables = [
  'app_businesses', 'app_business_products', 'app_business_orders', 'app_business_order_events',
  'app_tea_revisions', 'app_tea_club_settings', 'app_tea_club_rooms', 'app_tea_club_links',
  'app_tea_club_reads', 'app_tea_club_invites', 'app_tea_club_invite_requests',
  'app_professional_applications', 'app_professional_roles', 'app_professional_audit',
  'app_studio_handoffs', 'app_studio_sessions',
];
const functions = [
  'captro_professional_active(text,text)',
  'captro_professional_mutate(text,text,text,text,jsonb,uuid)',
  'captro_studio_session(text,text,text,text)',
  'captro_business_update_stock_product(uuid,uuid,uuid,jsonb,integer)',
  'captro_tea_reply_revision(text,uuid,integer)',
  'captro_tea_club(text,uuid,text,jsonb)',
];
const columns = [
  ['app_tea_replies', 'target'], ['app_group_messages', 'tea_room_id'],
  ['app_group_messages', 'tea_quote_id'], ['app_business_products', 'stock'],
  ['app_businesses', 'pickup_instructions'],
];
export const releaseCheckIDs = Object.freeze([
  ...releaseMigrations.map(v => 'migration:' + v),
  ...tables.map(v => 'table:' + v), ...functions.map(v => 'function:' + v),
  ...columns.map(([table, column]) => 'column:' + table + '.' + column),
  'audit:immutable',
]);
const values = items => items.map(item => `('${item}')`).join(',');
export const releaseSchemaSQL = `
select 'migration:'||v.id check_id, exists(select 1 from supabase_migrations.schema_migrations m where m.version=v.id) passed
from (values ${values(releaseMigrations)}) v(id)
union all
select 'table:'||v.id, coalesce(c.relrowsecurity
  and has_table_privilege('service_role',c.oid,'SELECT')
  and not has_table_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
  and not has_table_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
  and not has_any_column_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,REFERENCES')
  and not has_any_column_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE,REFERENCES'),false)
from (values ${values(tables)}) v(id) left join pg_class c on c.oid=to_regclass('public.'||v.id)
union all
select 'function:'||v.id, coalesce(not p.prosecdef
  and has_function_privilege('service_role',p.oid,'EXECUTE')
  and not has_function_privilege('anon',p.oid,'EXECUTE')
  and not has_function_privilege('authenticated',p.oid,'EXECUTE'),false)
from (values ${values(functions)}) v(id) left join pg_proc p on p.oid=to_regprocedure('public.'||v.id)
union all
select 'column:'||v.tab||'.'||v.col, exists(select 1 from information_schema.columns c where c.table_schema='public' and c.table_name=v.tab and c.column_name=v.col)
from (values ${columns.map(([table, column]) => `('${table}','${column}')`).join(',')}) v(tab,col)
union all
select 'audit:immutable', coalesce(not has_table_privilege('service_role',to_regclass('public.app_professional_audit'),'UPDATE,DELETE,TRUNCATE')
  and not has_any_column_privilege('service_role',to_regclass('public.app_professional_audit'),'UPDATE'),false);`;

export function validateReleaseSchema(rows) {
  if (!Array.isArray(rows) || rows.length !== releaseCheckIDs.length)
    throw Error('Native backend compatibility evidence is incomplete.');
  const seen = new Set();
  for (const row of rows) {
    if (!releaseCheckIDs.includes(row?.check_id) || seen.has(row.check_id) || typeof row.passed !== 'boolean')
      throw Error('Native backend compatibility evidence is malformed.');
    seen.add(row.check_id);
  }
  const failed = rows.filter(row => !row.passed).map(row => row.check_id);
  if (failed.length) throw Error('TestFlight backend rollout required: ' + failed.join(', '));
  return rows.length;
}

export async function verifyReleaseSchema(env = process.env, request = fetch) {
  const ref = env.SUPABASE_PROJECT_REF;
  const token = env.SUPABASE_ACCESS_TOKEN;
  if (ref !== 'cclgvxukwccvtgrbcwie' || !token) throw Error('Expected Captro production metadata credentials.');
  let response;
  try {
    response = await request(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
      method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ query: releaseSchemaSQL, read_only: true }),
      signal: AbortSignal.timeout(20_000), redirect: 'error',
    });
  } catch { throw Error('Backend compatibility inspection unavailable; upload remains blocked.'); }
  if (!response.ok) throw Error(`Backend compatibility inspection HTTP ${response.status}; upload remains blocked.`);
  let rows;
  try { rows = await response.json(); } catch { throw Error('Invalid backend compatibility evidence.'); }
  return validateReleaseSchema(rows);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try { console.log(`PASS: ${await verifyReleaseSchema()} native backend schema prerequisites.`); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
