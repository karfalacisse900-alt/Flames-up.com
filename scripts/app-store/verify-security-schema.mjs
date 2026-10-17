import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

// A release prerequisite, not a security certification. The SQL reads only
// catalogs/migration versions and never application rows or stored credentials.
export const securitySchemaSQL = readFileSync(new URL('./security-schema-checks.sql', import.meta.url), 'utf8');
export const securityCheckIDs = Object.freeze([
  'migration_20261006012846', 'migration_20261013154326', 'migration_20261013154328',
  'required_tables_exist', 'client_writes_denied', 'private_columns_unreadable',
  'client_ddl_privileges_denied', 'required_rls_enabled',
  'identity_helper_active_only', 'group_helper_private', 'group_select_policies',
  'push_rpc_service_only', 'push_unique_active_owner', 'payment_tables_server_only',
]);

export function validateSecuritySchema(rows) {
  if (!Array.isArray(rows) || rows.length !== securityCheckIDs.length)
    throw new Error('Security schema evidence is incomplete.');
  const seen = new Set();
  for (const row of rows) {
    if (!row || !securityCheckIDs.includes(row.check_id) || seen.has(row.check_id) || typeof row.passed !== 'boolean')
      throw new Error('Security schema evidence is malformed.');
    seen.add(row.check_id);
  }
  const failed = rows.filter(row => !row.passed).map(row => row.check_id);
  if (failed.length) throw new Error(`Security schema gate blocked: ${failed.join(', ')}.`);
  return securityCheckIDs.length;
}

export async function verifySecuritySchema(env = process.env, request = fetch) {
  const ref = env.SUPABASE_PROJECT_REF;
  const token = env.SUPABASE_ACCESS_TOKEN;
  if (!ref || !/^[a-z]{20}$/.test(ref) || !token)
    throw new Error('SUPABASE_PROJECT_REF and SUPABASE_ACCESS_TOKEN are required for the read-only security schema gate.');
  let response;
  try {
    response = await request(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ query: securitySchemaSQL, read_only: true }),
      signal: AbortSignal.timeout(20_000),
      redirect: 'error',
    });
  } catch {
    // Never echo request headers, provider bodies, or exception messages.
    throw new Error('Security schema lookup failed or timed out; upload remains blocked.');
  }
  if (!response.ok) throw new Error(`Security schema lookup returned HTTP ${response.status}; upload remains blocked.`);
  let rows;
  try { rows = await response.json(); }
  catch { throw new Error('Security schema lookup returned invalid evidence.'); }
  return validateSecuritySchema(rows);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const count = await verifySecuritySchema();
    console.log(`PASS: ${count} read-only security schema checks. Staging and device acceptance remain separate.`);
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
