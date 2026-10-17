// Isolated local acceptance check. Never accepts a database URL or production host.
// Start a disposable postgres:17 container WITHOUT publishing a port, then pass
// its name (must start captro-additional-review-) as argv[2]. Uses fixture data only.
import {execFileSync, spawn} from 'node:child_process';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const container=process.argv[2];
assert.match(container??'',/^captro-additional-review-[a-z0-9-]+$/);
const docker=(args,options={})=>execFileSync('wsl',['docker',...args],{encoding:'utf8',...options});
const info=JSON.parse(docker(['inspect',container]))[0];
assert.equal(info.Config.Image,'postgres:17');
assert.equal(Object.keys(info.HostConfig.PortBindings??{}).length,0,'No exposed database ports allowed');
assert.equal((info.Mounts??[]).filter(x=>x.Type!=='tmpfs').length,0,'No persistent mounts allowed');
function sql(database,input) {
  return docker(['exec','-i',container,'psql','-X','-qAt','-v','ON_ERROR_STOP=1','-U','postgres','-d',database],{input});
}
const baseline=['20260904193517_captro_commerce_entitlements.sql','20260904221545_stripe_connect_creator_earnings.sql','20260904231905_stripe_native_payments.sql','20260908224758_isolate_stripe_connected_accounts_by_mode.sql','20260925120000_seller_identity_verification.sql','20260926214527_deferred_marketplace_settlement.sql','20260926222000_marketplace_release_controls.sql','20260926235356_finance_category_reports.sql','20260927012001_commerce_ended_event_guard.sql'];
const migration=name=>readFileSync(new URL('../../supabase/migrations/'+name,import.meta.url),'utf8');
sql('postgres','create role anon; create role authenticated; create role service_role;');
const seller='10000000-0000-4000-8000-000000000001',buyer='10000000-0000-4000-8000-000000000002';
const post='10000000-0000-4000-8000-000000000003',item='10000000-0000-4000-8000-000000000004',price='10000000-0000-4000-8000-000000000005';
const begin=(key,start,end)=>`select id from captro_begin_marketplace_purchase_v2('${buyer}','buyer','${item}','${price}',1,'fixture-${key}','{"startsAt":"2035-01-01T${start}:00Z","endsAt":"2035-01-01T${end}:00Z"}',0,0,0,'checkout');`;
async function race(database,first,second) {
  // Separate PostgreSQL connections. Start B only after A has acquired its locks,
  // then keep A's transaction open briefly so B must contend with that transaction.
  const args=['docker','exec','-i',container,'psql','-X','-qAt','-v','ON_ERROR_STOP=1','-U','postgres','-d',database];
  const a=spawn('wsl',args,{stdio:['pipe','pipe','pipe']});
  let out='',err='';let launched=false;
  const bDone=new Promise((resolve,reject)=>{
    a.on('error',reject);
    a.stdout.on('data',data=>{
      out+=data;
      if(!launched&&out.includes('LOCKED')) {
        launched=true;
        const b=spawn('wsl',args,{stdio:['pipe','pipe','pipe']});let output='',error='';
        b.on('error',reject);b.stdout.on('data',x=>output+=x);b.stderr.on('data',x=>error+=x);
        b.on('close',code=>resolve({code,output,error}));b.stdin.end(second);
      }
    });
    a.stderr.on('data',data=>err+=data);
    a.on('close',code=>{if(!launched)reject(Error(`First transaction failed ${code}: ${err}`));});
  });
  const aDone=new Promise(resolve=>a.on('close',code=>resolve(code)));
  a.stdin.end(`begin;\n${first}\n\\echo LOCKED\nselect pg_sleep(1);\ncommit;\n`);
  const result=await bDone;assert.equal(await aDone,0,err);return result;
}
for(const patched of [false,true]) {
  const database=patched?'review_after':'review_before';
  sql('postgres',`create database ${database};`);
  sql(database,`create schema auth; create table auth.users(id uuid primary key); create table app_posts(id uuid primary key);
    create table app_group_chat_members(id text,group_id text,user_id text,role text,legacy_created_at timestamptz,created_at timestamptz,updated_at timestamptz,primary key(group_id,user_id));`);
  for(const file of baseline)sql(database,migration(file));
  if(patched)sql(database,migration('20261016214657_additional_commerce_lifecycle.sql'));
  sql(database,`insert into auth.users values('${seller}'),('${buyer}'); insert into app_posts values('${post}');
    insert into app_payment_environment(id,stripe_mode) values(true,'test');
    insert into app_purchasables(id,post_id,creator_id,creator_app_user_id,content_type,fulfillment_type,payment_model,title)
      values('${item}','${post}','${seller}','seller','booking','reservation','paid','Fixture');
    insert into app_prices(id,purchasable_id,unit_amount,currency) values('${price}','${item}',1000,'USD');`);
  if(patched)sql(database,`update app_purchasables set booking_capacity=1 where id='${item}';`); // explicitly reviewed fixture, never a migration default
  const result=await race(database,begin('first','10:00','11:00'),begin('overlap','10:01','11:01'));
  assert.equal(result.code,patched?3:0,result.error);
  if(patched)assert.match(result.error,/CAPTRO_BOOKING_SLOT_UNAVAILABLE/);
  const held=Number(sql(database,`select sum(quantity_committed) from app_booking_slots where purchasable_id='${item}';`).trim());
  assert.equal(held,patched?1:2);
  console.log(`${patched?'AFTER':'BEFORE'}: concurrent overlapping capacity-one requests -> ${held} reservations`);
  if(patched) {
    sql(database,begin('adjacent','11:00','12:00'));
    assert.equal(Number(sql(database,`select sum(quantity_committed) from app_booking_slots where purchasable_id='${item}';`).trim()),2);
    console.log('AFTER: adjacent interval accepted');
    // The old local expiry helper competes with a verified delayed confirmation.
    const purchase=sql(database,"select id from app_purchases where idempotency_key='fixture-first';").trim();
    sql(database,`update app_purchases set hold_expires_at=now()-interval '1 hour',provider_payment_id='pi_fixture' where id='${purchase}';`);
    const confirm=`select status from captro_confirm_marketplace_purchase('${purchase}','evt_fixture',null,'pi_fixture','ch_fixture',null,1000,40,0,'USD',null,'digest');`;
    const paid=await race(database,`select captro_release_expired_purchase_holds();`,confirm);
    assert.equal(paid.code,0,paid.error);assert.match(paid.output,/confirmed/);
    sql(database,confirm);
    assert.equal(Number(sql(database,`select count(*) from app_entitlements where purchase_id='${purchase}';`).trim()),1);
    console.log('AFTER: elapsed-hold release/confirmation overlap + replay -> one entitlement');
  }
}
console.log('All isolated PostgreSQL acceptance checks passed. Provider interactions were mocked, not charged.');
