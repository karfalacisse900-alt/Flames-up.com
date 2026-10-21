import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {PGlite} from '@electric-sql/pglite';

test('support shares durable payment ledger, zero commission and no entitlement', async t => {
 const db=new PGlite();
 try {
  await db.exec(`create role anon; create role authenticated; create role service_role; create schema auth;
    create table auth.users(id uuid primary key); create table app_posts(id uuid primary key);
    create table app_group_chat_members(id text,group_id text,user_id text,role text,legacy_created_at timestamptz,created_at timestamptz,updated_at timestamptz,primary key(group_id,user_id));`);
  for(const file of ['20260904193517_captro_commerce_entitlements.sql','20260904221545_stripe_connect_creator_earnings.sql',
   '20260904231905_stripe_native_payments.sql','20260908224758_isolate_stripe_connected_accounts_by_mode.sql',
   '20260925120000_seller_identity_verification.sql','20260926214527_deferred_marketplace_settlement.sql',
   '20260926222000_marketplace_release_controls.sql','20260926235356_finance_category_reports.sql',
   '20260927012001_commerce_ended_event_guard.sql','20261016214657_additional_commerce_lifecycle.sql',
   '20261017002255_reliable_payment_reconciliation.sql','20261017002807_payment_recovery_resolution.sql',
   '20261019234129_creator_support_test_contract.sql','20261021000708_creator_earnings_categories.sql']) await db.exec(readFileSync(new URL('../../supabase/migrations/'+file,import.meta.url),'utf8'));
  const one=async(sql,args=[])=>(await db.query(sql,args)).rows[0];
  const seller=(await one('insert into auth.users values(gen_random_uuid()) returning id')).id;
  const buyer=(await one('insert into auth.users values(gen_random_uuid()) returning id')).id;
  await db.exec("insert into app_payment_environment(id,stripe_mode) values(true,'test')");
  const account=await one(`insert into app_connected_accounts(user_id,app_user_id,provider_account_id,stripe_mode,status,details_submitted,
    transfers_enabled,payouts_enabled,payout_schedule) values($1,'seller','acct_support','test','ready',true,true,true,'manual') returning *`,[seller]);
  await db.query("insert into app_creator_support_enrollments(creator_id,enabled_for_test,reviewed_by) values($1,true,'isolated-test')",[seller]);
  const key='12345678-1234-4234-8234-123456789012',hash='a'.repeat(64);
  const issue=()=>one("select * from captro_issue_support_handoff($1,'buyer',$2,'seller',$3,$4)",[buyer,seller,key,hash]);
  const h=await issue(); assert.equal((await issue()).id,h.id);
  const begin=amount=>one('select * from captro_begin_creator_support($1,$2,$3)',[hash,amount,account.id]);
  const p=await begin(500); assert.equal((await begin(500)).id,p.id);
  await assert.rejects(begin(501),/IDEMPOTENCY_CONFLICT/);
  await assert.rejects(begin(1),/AMOUNT_INVALID/);
  assert.equal(p.platform_fee_amount,0); assert.equal(p.service_fee_amount,0); assert.equal(p.post_id,null);
  await one('select * from captro_validate_checkout($1)',[p.id]);
  await db.query("update app_purchases set provider_checkout_id='cs_support' where id=$1",[p.id]);
  const confirm=(event='evt_support',amount=500)=>one("select * from captro_confirm_marketplace_purchase($1,$2,'cs_support','pi_support','ch_support',null,$3,59,0,'USD',null,'digest')",[p.id,event,amount]);
  await assert.rejects(confirm('evt_wrong',501),/AMOUNT_MISMATCH/);
  await confirm(); await confirm('evt_replay');
  assert.equal((await one('select count(*)::int n from app_payments')).n,1);
  assert.equal((await one('select count(*)::int n from app_creator_earnings')).n,1);
  assert.equal((await one('select count(*)::int n from app_entitlements')).n,0);
  const earning=await one('select * from app_creator_earnings');
  assert.equal(earning.creator_amount,441); assert.equal(earning.processing_amount,59);
  assert.equal(earning.platform_fee,0); assert.equal(earning.status,'pending'); assert.equal(earning.processing_cost_known,true);
  assert.ok((await one('select count(*)::int n from app_marketplace_ledger')).n>0);
  const totals=await one('select * from app_finance_order_totals where order_id=$1',[p.id]);
  assert.equal(Number(totals.gross),500); assert.equal(Number(totals.captro_fee),0);
  assert.equal((await one("select captro_finance_category('creator_support') as category")).category,'creator_support');
  assert.equal(Number(totals.processing_fee),59); assert.equal(Number(totals.pending),441);
  const pool = () => one("select * from app_creator_finance_pools where seller_id=$1 and category='creator_support' and stripe_mode='test' and currency='USD'",[seller]);
  assert.equal(Number((await pool()).transactions),1);
  assert.equal(Number((await pool()).gross_received),500);
  assert.equal(Number((await pool()).processing_fee),59);
  assert.equal(Number((await pool()).creator_net),441);
  assert.equal(Number((await pool()).captro_fee),0);
  assert.equal(Number((await pool()).available),0);
  await t.test('unknown processor fee never looks like a zero fee or available money',async()=>{
    await db.query('update app_creator_earnings set processing_cost_known=false where purchase_id=$1',[p.id]);
    assert.equal((await pool()).processing_fee,null); assert.equal((await pool()).creator_net,null);
    assert.equal(Number((await pool()).available),0);
    await db.query('update app_creator_earnings set processing_cost_known=true where purchase_id=$1',[p.id]);
  });
  await assert.rejects(db.query("update app_purchases set platform_fee_amount=1 where id=$1",[p.id]),/captro_support_snapshot/);
  await assert.rejects(db.query("update app_purchases set stripe_mode='live' where id=$1",[p.id]),/captro_support_snapshot/);
  await t.test('existing dispute hold moves net earnings once and prevents payout release',async()=>{
    await db.query("update app_creator_earnings set status='disputed',disputed_amount=441 where purchase_id=$1",[p.id]);
    await db.query("update app_creator_earnings set status='disputed',disputed_amount=441 where purchase_id=$1",[p.id]);
    assert.equal(Number((await one("select sum(amount) n from app_marketplace_ledger where order_id=$1 and account='held'",[p.id])).n),441);
    assert.equal(Number((await pool()).held),441);
    assert.equal(Number((await pool()).pending),441);
    assert.equal(Number((await pool()).available),0);
    await assert.rejects(one("select * from captro_claim_earning_transfer($1,$2,'acct_support',gen_random_uuid(),false)",[p.id,account.id]),/RELEASE_NOT_ELIGIBLE/);
    // Simulate the existing verified provider resolution path in this isolated DB.
    await db.query("update app_creator_earnings set status='pending',disputed_amount=0 where purchase_id=$1",[p.id]);
    assert.equal(Number((await one("select sum(amount) n from app_marketplace_ledger where order_id=$1 and account='held'",[p.id])).n),0);
  });
  await t.test('combined category payout uses existing FIFO once, preserves creator/mode isolation and failed payout recovery',async()=>{
    await db.exec('begin');
    try {
    // Isolated fixtures model the already-verified transfer transition. No Stripe calls.
    const post=(await one('insert into app_posts values(gen_random_uuid()) returning id')).id;
    const item=await one("insert into app_purchasables(post_id,creator_id,creator_app_user_id,content_type,fulfillment_type,payment_model,title) values($1,$2,'seller','event','ticket','paid','Paid event') returning *",[post,seller]);
    const price=await one("insert into app_prices(purchasable_id,unit_amount,currency) values($1,1000,'USD') returning *",[item.id]);
    const event=await one("select * from captro_begin_marketplace_purchase_v2($1,'buyer',$2,$3,1,'event-payout','{}',0,0,0,'checkout')",[buyer,item.id,price.id]);
    await db.query("update app_purchases set provider_checkout_id='cs_event' where id=$1",[event.id]);
    await one("select * from captro_confirm_marketplace_purchase($1,'evt_event','cs_event','pi_event','ch_event',null,1000,60,0,'USD',null,'digest')",[event.id]);
    await db.query("update app_creator_earnings set status='transferred' where purchase_id in ($1,$2)",[p.id,event.id]);
    assert.equal(Number((await pool()).available),441);
    const other=(await one('insert into auth.users values(gen_random_uuid()) returning id')).id;
    const otherAccount=await one("insert into app_connected_accounts(user_id,app_user_id,provider_account_id,stripe_mode) values($1,'other','acct_other','test') returning *",[other]);
    const liveAccount=await one("insert into app_connected_accounts(user_id,app_user_id,provider_account_id,stripe_mode) values($1,'seller','acct_live','live') returning *",[seller]);
    for(const [owner,acct,provider] of [[other,otherAccount.id,'po_other'],[seller,liveAccount.id,'po_live']])
      await db.query("insert into app_payouts(creator_id,connected_account_id,provider_payout_id,currency,amount,status) values($1,$2,$3,'USD',50,'paid')",[owner,acct,provider]);
    const payout=await one("insert into app_payouts(creator_id,connected_account_id,provider_payout_id,currency,amount,fee_amount,status) values($1,$2,'po_combined','USD',1381,17,'pending') returning *",[seller,account.id]);
    let allocations=(await db.query('select * from app_creator_finance_payouts where payout_id=$1 order by category',[payout.id])).rows;
    assert.equal(allocations.length,2);
    assert.deepEqual(allocations.map(r=>[r.category,Number(r.attributed_amount)]),[['creator_support',441],['event',940]]);
    assert.equal(allocations.reduce((sum,r)=>sum+Number(r.attributed_amount),0),1381);
    assert.ok(allocations.every(r=>r.seller_id===seller&&r.stripe_mode==='test'&&Number(r.payout_fee)===17));
    await db.query("update app_payouts set status='failed' where id=$1",[payout.id]);
    assert.equal(Number((await pool()).available),441); assert.equal(Number((await pool()).paid_out),0);
    await db.query("update app_payouts set status='pending' where id=$1",[payout.id]);
    await db.query("update app_payouts set status='paid' where id=$1",[payout.id]);
    const entries=(await one('select count(*)::int n from app_marketplace_ledger')).n;
    await db.query("update app_payouts set status='paid' where id=$1",[payout.id]);
    assert.equal((await one('select count(*)::int n from app_marketplace_ledger')).n,entries);
    allocations=(await db.query('select * from app_creator_finance_payouts where payout_id=$1',[payout.id])).rows;
    assert.equal(allocations.reduce((sum,r)=>sum+Number(r.attributed_amount),0),1381);
    assert.equal(Number((await pool()).paid_out),441); assert.equal(Number((await pool()).pending),0);
    assert.equal(Number((await pool()).creator_net),441);
    const ownCategories=await one("select sum(paid_out)::bigint paid from app_creator_finance_pools where seller_id=$1 and stripe_mode='test'",[seller]);
    assert.equal(Number(ownCategories.paid),1381);
    } finally { await db.exec('rollback'); } // Restore independent fixture, not production history.
  });
  await t.test('partial/full refund replay uses existing recovery, no entitlement or duplicate payment',async()=>{
    const refund=(id,amount,reversal)=>one("select * from captro_record_marketplace_refund('pi_support',$1,$2,$3,0,$1,'succeeded','','digest')",[id,amount,reversal]);
    await refund('re_partial',100,88); await refund('re_partial',100,88);
    assert.equal(Number((await pool()).refunded),100);
    assert.equal((await one('select status from app_purchases where id=$1',[p.id])).status,'partially_refunded');
    await refund('re_rest',400,353); await confirm('evt_old_success');
    assert.equal((await one('select status from app_purchases where id=$1',[p.id])).status,'refunded');
    assert.equal((await one('select count(*)::int n from app_refunds')).n,2);
    assert.equal((await one('select count(*)::int n from app_entitlements')).n,0);
    assert.equal(Number((await pool()).gross_received),500);
    assert.equal(Number((await pool()).refunded),500);
  });
  await t.test('legacy commerce still requires genuine posts and issues its existing entitlement',async()=>{
    const post=(await one('insert into app_posts values(gen_random_uuid()) returning id')).id;
    const item=await one("insert into app_purchasables(post_id,creator_id,creator_app_user_id,content_type,fulfillment_type,payment_model,title) values($1,$2,'seller','event','ticket','free','Event') returning *",[post,seller]);
    const price=await one("insert into app_prices(purchasable_id,unit_amount,currency) values($1,0,'USD') returning *",[item.id]);
    const ordinary=await one("select * from captro_begin_marketplace_purchase_v2($1,'buyer',$2,$3,1,'legacy-valid','{}',0,0,0,'checkout')",[buyer,item.id,price.id]);
    assert.equal(ordinary.status,'confirmed');
    assert.equal((await one('select count(*)::int n from app_entitlements')).n,1);
  });
  await t.test('client roles cannot enroll creators, create support or inspect handoffs',async()=>{
    await db.exec('set role authenticated');
    await assert.rejects(issue(),/permission denied/);
    await assert.rejects(begin(500),/permission denied/);
    await assert.rejects(db.exec('select * from app_creator_support_handoffs'),/permission denied/);
    await assert.rejects(db.exec('update app_creator_support_enrollments set enabled_for_test=true'),/permission denied/);
    for(const view of ['app_creator_finance_orders','app_creator_finance_pools','app_creator_finance_payouts'])
      await assert.rejects(db.exec('select * from '+view),/permission denied/);
    await db.exec('reset role');
  });
 } finally { await db.close(); }
});
