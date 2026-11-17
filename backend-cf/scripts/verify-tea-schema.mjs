import assert from 'node:assert/strict';
const {SUPABASE_PROJECT_REF:ref,SUPABASE_ACCESS_TOKEN:token}=process.env;
assert.equal(ref,'cclgvxukwccvtgrbcwie');assert.ok(token);
const query=`
select c.relname check_id,c.relrowsecurity and has_table_privilege('service_role',c.oid,'SELECT,INSERT,UPDATE,DELETE')
 and not has_table_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,DELETE')
 and not has_table_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE,DELETE') passed
from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public'
and c.relname in ('app_tea_conversations','app_tea_replies','app_tea_follows')
union all
select p.proname,not p.prosecdef and has_function_privilege('service_role',p.oid,'EXECUTE')
 and not has_function_privilege('anon',p.oid,'EXECUTE') and not has_function_privilege('authenticated',p.oid,'EXECUTE')
from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
and p.proname in ('captro_tea_read','captro_tea_write','captro_tea_author_visible','captro_tea_post_json',
'captro_tea_note_capabilities','captro_tea_note_fields','captro_tea_note_write','captro_tea_note_apply','captro_tea_note_applications')
union all
select 'app_tea_applications',c.relrowsecurity and has_table_privilege('service_role',c.oid,'SELECT,INSERT,DELETE')
 and not has_table_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,DELETE')
 and not has_table_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE,DELETE')
from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='app_tea_applications'
union all
select 'note_columns', count(*)=2 from information_schema.columns where table_schema='public'
 and table_name='app_tea_conversations' and column_name in ('borough','primary_action');`;
const r=await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`,{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:JSON.stringify({query,read_only:true}),signal:AbortSignal.timeout(20000)});
assert.ok(r.ok,'Tea schema inspection failed');const rows=await r.json();
assert.equal(rows.length,14);assert.ok(rows.every(r=>r.passed===true));
console.log('PASS: Tea tables enforce RLS and all Tea tables/functions are service-role-only.');
