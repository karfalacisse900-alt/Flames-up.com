import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {PGlite} from '@electric-sql/pglite';

test('review migration enforces interval resources, approval dates and provider-owned release', async t=>{
 const db=new PGlite();
 try {
  await db.exec(`create role anon; create role authenticated; create role service_role; create schema auth;
    create table auth.users(id uuid primary key); create table app_posts(id uuid primary key);
    create table app_group_chat_members(id text,group_id text,user_id text,role text,legacy_created_at timestamptz,created_at timestamptz,updated_at timestamptz,primary key(group_id,user_id));`);
  for(const f of ['20260904193517_captro_commerce_entitlements.sql','20260904221545_stripe_connect_creator_earnings.sql','20260904231905_stripe_native_payments.sql','20260908224758_isolate_stripe_connected_accounts_by_mode.sql','20260925120000_seller_identity_verification.sql','20260926214527_deferred_marketplace_settlement.sql','20260926222000_marketplace_release_controls.sql','20260926235356_finance_category_reports.sql','20260927012001_commerce_ended_event_guard.sql','20261016214657_additional_commerce_lifecycle.sql']) {
    await db.exec(readFileSync(new URL('../../supabase/migrations/'+f,import.meta.url),'utf8'));
  }
  const one=async(sql,args=[])=>(await db.query(sql,args)).rows[0];
  await db.exec(readFileSync(new URL('../../supabase/migrations/20261017002255_reliable_payment_reconciliation.sql',import.meta.url),'utf8'));
  await db.exec(readFileSync(new URL('../../supabase/migrations/20261017002807_payment_recovery_resolution.sql',import.meta.url),'utf8'));
  const seller=(await one('insert into auth.users values(gen_random_uuid()) returning id')).id;
  const buyer=(await one('insert into auth.users values(gen_random_uuid()) returning id')).id;
  await db.exec("insert into app_payment_environment(id,stripe_mode) values(true,'test')");
  const item=async(type='booking',fulfillment='reservation',paid=true,approval=false,capacity=1)=>{
    const post=(await one('insert into app_posts values(gen_random_uuid()) returning id')).id;
    const row=await one("insert into app_purchasables(post_id,creator_id,creator_app_user_id,content_type,fulfillment_type,payment_model,title,approval_required,booking_capacity) values($1,$2,'seller',$3,$4,$5,'Fixture',$6,$7) returning *",[post,seller,type,fulfillment,paid?'paid':'free',approval,capacity]);
    const price=(await one("insert into app_prices(purchasable_id,unit_amount,currency) values($1,$2,'USD') returning id",[row.id,paid?1000:0])).id;
    return {...row,price};
  };
  const begin=(row,key,starts='2035-01-01T10:00:00Z',ends='2035-01-01T11:00:00Z',price=row.price)=>one("select * from captro_begin_marketplace_purchase_v2($1,'buyer',$2,$3,1,$4,$5,0,0,0,'checkout')",[buyer,row.id,price,'fixture-'+key,JSON.stringify({startsAt:starts,endsAt:ends})]);

  await t.test('different overlapping starts share capacity across tiers; adjacent intervals succeed',async()=>{
    const row=await item(); const first=await begin(row,'first');
    const price2=(await one("insert into app_prices(purchasable_id,unit_amount,currency) values($1,1000,'USD') returning id",[row.id])).id;
    await assert.rejects(begin(row,'overlap','2035-01-01T10:01:00Z','2035-01-01T11:01:00Z',price2),/SLOT_UNAVAILABLE/);
    await begin(row,'adjacent','2035-01-01T11:00:00Z','2035-01-01T12:00:00Z');
    await one("select * from captro_cancel_purchase_hold($1,'')",[first.id]);
    await begin(row,'released','2035-01-01T10:00:00Z','2035-01-01T11:00:00Z');
  });
  await t.test('multi-capacity uses peak occupancy and respects actual UTC intervals across DST offsets',async()=>{
    const row=await item('booking','reservation',true,false,2);
    await begin(row,'a','2035-11-04T01:00:00-04:00','2035-11-04T02:00:00-04:00');
    await begin(row,'b','2035-11-04T01:00:00-05:00','2035-11-04T02:00:00-05:00');
    await begin(row,'long','2035-11-04T00:30:00-04:00','2035-11-04T02:30:00-05:00');
    await assert.rejects(begin(row,'over','2035-11-04T01:01:00-04:00','2035-11-04T01:30:00-04:00'),/SLOT_UNAVAILABLE/);
  });
  await t.test('approval after event end or offer expiry rolls back inventory and entitlement',async()=>{
    for(const [type,fulfillment,field] of [['event','ticket','ends_at'],['deal','redemption','expires_at']]) {
      for(const paid of [false,true]) {
        const row=await item(type,fulfillment,paid,true); const purchase=await begin(row,type+paid);
        assert.equal(purchase.status,'approval_pending');
        await db.query(`update app_purchasables set ${field}=now()-interval '1 minute' where id=$1`,[row.id]);
        await assert.rejects(one('select * from captro_decide_purchase($1,$2,true)',[purchase.id,seller]),/EXPIRED|ENDED/);
        assert.equal((await one('select status from app_purchases where id=$1',[purchase.id])).status,'approval_pending');
        assert.equal((await one('select quantity_committed from app_purchasables where id=$1',[row.id])).quantity_committed,0);
        assert.equal((await one('select count(*)::int n from app_entitlements where purchase_id=$1',[purchase.id])).n,0);
      }
    }
  });
  await t.test('valid approval succeeds; checkout revalidates changed price and dates',async()=>{
    const row=await item('event','ticket',true,true); const purchase=await begin(row,'valid-approval');
    assert.equal((await one('select * from captro_decide_purchase($1,$2,true)',[purchase.id,seller])).status,'payment_pending');
    await one('select * from captro_validate_checkout($1)',[purchase.id]);
    await db.query('update app_prices set active=false where id=$1',[row.price]);
    await assert.rejects(one('select * from captro_validate_checkout($1)',[purchase.id]),/PRICE_UNAVAILABLE/);
  });
  await t.test('elapsed hosted hold survives new purchases and accepts delayed paid confirmation exactly once',async()=>{
    const row=await item('event','ticket');const purchase=await begin(row,'late-paid');
    await db.query("update app_purchases set hold_expires_at=now()-interval '1 hour',provider_payment_id='pi_late' where id=$1",[purchase.id]);
    await begin(row,'another-buyer');
    assert.equal((await one('select status from app_purchases where id=$1',[purchase.id])).status,'payment_pending');
    const confirm=()=>one("select * from captro_confirm_marketplace_purchase($1,'evt_late',null,'pi_late','ch_late',null,1000,40,0,'USD',null,'digest')",[purchase.id]);
    await confirm();await confirm();
    assert.equal((await one('select count(*)::int n from app_entitlements where purchase_id=$1',[purchase.id])).n,1);
  });
  await t.test('already-released verified payment creates one durable recovery, never unreserved access',async()=>{
    const row=await item('event','ticket');const purchase=await begin(row,'legacy-expired');
    await one("select * from captro_cancel_purchase_hold($1,'')",[purchase.id]);
    const record=(amount=1000)=>one("select captro_record_late_payment($1,'pi_recovery','evt_recovery',$2,'USD')",[purchase.id,amount]);
    await record();await record();await assert.rejects(record(100),/MISMATCH/);
    assert.equal((await one('select count(*)::int n from app_payment_recovery where purchase_id=$1',[purchase.id])).n,1);
    assert.equal((await one('select count(*)::int n from app_entitlements where purchase_id=$1',[purchase.id])).n,0);
    await db.exec('set role authenticated');await assert.rejects(record(),/permission denied/);await db.exec('reset role');
  });
  await t.test('operator recovery is owned, capacity-safe and idempotent; recording a case is never completion',async()=>{
    const row=await item('event','ticket');await db.query('update app_purchasables set capacity=1 where id=$1',[row.id]);
    const paid=await begin(row,'operator-paid');await one("select * from captro_cancel_purchase_hold($1,'')",[paid.id]);
    await one("select captro_record_late_payment($1,'pi_operator','evt_operator',1000,'USD')",[paid.id]);
    const competing=await begin(row,'operator-occupied');
    const claim=await one("select * from captro_claim_payment_recovery($1,'admin-a','fulfill','Verified provider payment')",[paid.id]);
    await assert.rejects(one("select * from captro_claim_payment_recovery($1,'admin-b','refund','Another operator attempt')",[paid.id]),/BUSY/);
    const fulfill=()=>one("select * from captro_resolve_payment_recovery($1,'admin-a',$2,'fulfilled','pi_operator','ch_operator',40)",[paid.id,claim.lease_token]);
    await assert.rejects(fulfill(),/CAPACITY_REACHED/);
    assert.equal((await one('select status from app_payment_recovery where purchase_id=$1',[paid.id])).status,'needs_review');
    await one("select * from captro_cancel_purchase_hold($1,'')",[competing.id]);
    await fulfill();await fulfill();
    assert.equal((await one('select count(*)::int n from app_entitlements where purchase_id=$1',[paid.id])).n,1);
    assert.equal((await one('select quantity_committed from app_purchasables where id=$1',[row.id])).quantity_committed,1);
    await assert.rejects(begin(row,'cannot-resell'),/CAPACITY_REACHED/);
    const refundItem=await item('event','ticket'),refund=await begin(refundItem,'operator-refund');
    await one("select * from captro_cancel_purchase_hold($1,'')",[refund.id]);
    await one("select captro_record_late_payment($1,'pi_refund','evt_refund',1000,'USD')",[refund.id]);
    const old=await one("select * from captro_claim_payment_recovery($1,'admin-a','refund','Buyer requested full refund')",[refund.id]);
    await db.query("update app_payment_recovery set lease_until=now()-interval '1 second' where purchase_id=$1",[refund.id]);
    await assert.rejects(one("select * from captro_claim_payment_recovery($1,'admin-b','fulfill','Cannot switch after refund')",[refund.id]),/REFUND_IN_FLIGHT/);
    const fresh=await one("select * from captro_claim_payment_recovery($1,'admin-b','refund','Reconciled lost refund response')",[refund.id]);
    await assert.rejects(one("select * from captro_resolve_payment_recovery($1,'admin-a',$2,'refunded','re_fixture',null,0)",[refund.id,old.lease_token]),/LEASE_LOST/);
    const finish=()=>one("select * from captro_resolve_payment_recovery($1,'admin-b',$2,'refunded','re_fixture',null,0)",[refund.id,fresh.lease_token]);
    await finish();await finish();
    assert.equal((await one('select count(*)::int n from app_payments where purchase_id=$1',[refund.id])).n,1);
    assert.equal((await one('select count(*)::int n from app_entitlements where purchase_id=$1',[refund.id])).n,0);
    assert.equal((await one('select count(*)::int n from app_payment_recovery_events where purchase_id=$1',[refund.id])).n,3);
    await db.exec('set role authenticated');
    await assert.rejects(finish(),/permission denied/);await db.exec('reset role');
  });
  await t.test('unreviewed historical capacity gates only new bookings and preserves existing commitments',async()=>{
    const row=await item('booking','reservation',true,false,3); await begin(row,'reviewed-first');
    await db.query('update app_purchasables set booking_capacity=null where id=$1',[row.id]);
    await assert.rejects(begin(row,'unreviewed-new'),/CAPACITY_REVIEW_REQUIRED/);
    assert.equal((await one('select sum(quantity_committed)::int n from app_booking_slots where purchasable_id=$1',[row.id])).n,1);
  });
  await t.test('durable leases progress beyond forty unresolved jobs; backoff, restart and stale completion are safe',async()=>{
    const row=await item('event','ticket'); const ids=[];
    for(let i=0;i<97;i++) ids.push((await begin(row,'queue-'+i)).id);
    await db.query("update app_purchases set hold_expires_at=now()-interval '1 hour' where id=any($1::uuid[])",[ids]);
    const visited=new Set();
    for(let batch=0;batch<4;batch++) {
      const claimed=(await db.query('select * from captro_claim_purchase_reconciliation(40)')).rows;
      for(const job of claimed) {
        assert.ok(!visited.has(job.purchase.id),'Backoff must make room for unattempted work');visited.add(job.purchase.id);
        assert.equal((await one('select captro_renew_purchase_reconciliation($1,$2) ok',[job.purchase.id,job.token])).ok,true);
        await assert.rejects(one("select captro_finish_purchase_reconciliation($1,$2,'released')",[job.purchase.id,job.token]),/TERMINAL_NOT_VERIFIED/);
        assert.equal((await one("select captro_finish_purchase_reconciliation($1,$2,'processing') ok",[job.purchase.id,job.token])).ok,true);
        assert.equal((await one("select captro_finish_purchase_reconciliation($1,$2,'processing') ok",[job.purchase.id,job.token])).ok,false);
      }
    }
    assert.ok(ids.every(id=>visited.has(id)),'Every new purchase progresses despite >40 old unresolved purchases');
    const id=ids[0]; await db.query("update app_purchase_reconciliation set next_attempt_at=now()-interval '1 second',attempt_count=8,first_seen_at=now()-interval '2 days' where purchase_id=$1",[id]);
    const old=await one('select * from captro_claim_purchase_reconciliation(1)');
    assert.equal((await db.query('select * from captro_claim_purchase_reconciliation(1)')).rows.length,0,'Live lease cannot be reclaimed');
    await db.query("update app_purchase_reconciliation set lease_until=now()-interval '1 second' where purchase_id=$1",[id]);
    const fresh=await one('select * from captro_claim_purchase_reconciliation(1)');assert.notEqual(old.token,fresh.token);
    assert.equal((await one("select captro_finish_purchase_reconciliation($1,$2,'processing') ok",[id,old.token])).ok,false);
    await one("select captro_finish_purchase_reconciliation($1,$2,'transient_failure')",[id,fresh.token]);
    const state=await one('select *,extract(epoch from next_attempt_at-now())::int delay from app_purchase_reconciliation where purchase_id=$1',[id]);
    assert.equal(state.needs_attention,true);assert.ok(state.delay>=120&&state.delay<=21660);
    assert.equal((await one('select status from app_purchases where id=$1',[id])).status,'payment_pending');
    await db.exec('set role authenticated');
    await assert.rejects(db.query('select * from captro_claim_purchase_reconciliation(40)'),/permission denied/);
    await db.exec('reset role');
  });
  await t.test('dashboard canonical status works against metadata-only schema',async()=>{
    await db.exec("create table app_users(metadata jsonb); insert into app_users values('{\"status\":\"suspended\"}'),('{\"status\":\"active\"}');");
    assert.equal((await one("select count(*)::int n from app_users where metadata->>'status'='suspended'")).n,1);
    await assert.rejects(db.query("select count(*) from app_users where status='suspended'"),/does not exist/);
  });
 } finally { await db.close(); }
});
