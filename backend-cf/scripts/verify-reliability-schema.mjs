// Metadata only: no customer rows, provider calls or destructive operations.
const query=`
with tables(name) as (values ('app_payment_recovery'),('app_purchase_reconciliation'),('app_payment_recovery_events'),
 ('app_admin_operations'),('app_admin_appeals'),('app_account_cleanup_jobs')),
 funcs(signature) as (values ('captro_validate_checkout(uuid)'),('captro_claim_purchase_reconciliation(integer)'),
 ('captro_renew_purchase_reconciliation(uuid,uuid)'),('captro_finish_purchase_reconciliation(uuid,uuid,text)'),
 ('captro_claim_payment_recovery(uuid,text,text,text)'),('captro_admin_execute(text,jsonb)'),('captro_restore_pending_account(text)'))
select 'private_tables' check_id, count(c.oid)=6 and bool_and(c.relrowsecurity and
 not has_table_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE,DELETE') and
 not has_table_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,DELETE')) passed
from tables t left join pg_class c on c.oid=to_regclass('public.'||t.name)
union all select 'server_rpcs',count(*)=7 and bool_and(to_regprocedure('public.'||signature) is not null and
 has_function_privilege('service_role',to_regprocedure('public.'||signature),'EXECUTE') and
 not has_function_privilege('authenticated',to_regprocedure('public.'||signature),'EXECUTE') and
 not has_function_privilege('anon',to_regprocedure('public.'||signature),'EXECUTE')) from funcs
union all select 'clock_expiration_disabled', coalesce((select regexp_replace(p.prosrc,'[[:space:]]','','g')='select0;'
 from pg_proc p where p.oid=to_regprocedure('public.captro_release_expired_purchase_holds()')),false)
union all select 'capacity_requires_review',exists(select 1 from information_schema.columns where table_schema='public'
 and table_name='app_purchasables' and column_name='booking_capacity' and is_nullable='YES' and column_default is null)
union all select 'approval_dates_guard',exists(select 1 from pg_trigger where tgname='captro_guard_purchase_approval' and tgenabled='O');`;
const {SUPABASE_PROJECT_REF:ref,SUPABASE_ACCESS_TOKEN:token}=process.env;
if(ref!=='cclgvxukwccvtgrbcwie'||!token)throw Error('Captro schema verification credentials unavailable');
const r=await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`,{
 method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},
 body:JSON.stringify({query,read_only:true}),signal:AbortSignal.timeout(20000)});
if(!r.ok)throw Error('Schema verification HTTP '+r.status);
const rows=await r.json();
if(!Array.isArray(rows)||rows.length!==5||rows.some(r=>r.passed!==true))throw Error('Reliability schema gate failed: '+JSON.stringify(rows));
console.log('PASS: five coordinated reliability schema assertions');
