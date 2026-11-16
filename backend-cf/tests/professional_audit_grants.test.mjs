import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '@electric-sql/pglite';

test('audit hardening removes inherited destructive grants but preserves append/read', async t => {
  const db = new PGlite(); t.after(() => db.close());
  await db.exec(`create role anon; create role authenticated; create role service_role;
    alter default privileges in schema public grant all on tables to service_role;
    create table app_professional_audit(id integer primary key);
    revoke update on app_professional_audit from service_role;`);
  const privileges = async () => (await db.query(`select
    has_table_privilege('service_role','app_professional_audit','DELETE') as del,
    has_table_privilege('service_role','app_professional_audit','TRUNCATE') as trunc,
    has_table_privilege('service_role','app_professional_audit','UPDATE') as upd,
    has_table_privilege('service_role','app_professional_audit','SELECT') as read,
    has_table_privilege('service_role','app_professional_audit','INSERT') as append`)).rows[0];
  assert.equal((await privileges()).del, true, 'reproduces the production default grant');
  await db.exec(readFileSync(new URL('../../supabase/migrations/20261116020500_professional_audit_grants.sql', import.meta.url), 'utf8'));
  assert.deepEqual(await privileges(), { del:false, trunc:false, upd:false, read:true, append:true });
  await db.exec('set role service_role; insert into app_professional_audit values(1);');
  for (const sql of ['delete from app_professional_audit', 'truncate app_professional_audit', 'update app_professional_audit set id=2'])
    await assert.rejects(db.exec(sql), /permission denied/);
  assert.equal((await db.query('select count(*)::int as n from app_professional_audit')).rows[0].n,1);
});
