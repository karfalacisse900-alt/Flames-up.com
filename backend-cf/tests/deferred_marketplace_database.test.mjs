import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {PGlite} from '@electric-sql/pglite';
test('platform payment issues access independently of seller setup and appends immutable pending ledger', async()=>{
 const db=new PGlite();
 try {
 await db.exec(`create role anon; create role authenticated; create role service_role; create schema auth; create table auth.users(id uuid primary key); create table app_posts(id uuid primary key); create table app_group_chat_members(id text,group_id text,user_id text,role text,legacy_created_at timestamptz,created_at timestamptz,updated_at timestamptz,primary key(group_id,user_id));`);
 for(const f of ['20260904193517_captro_commerce_entitlements.sql','20260904221545_stripe_connect_creator_earnings.sql','20260904231905_stripe_native_payments.sql','20260908224758_isolate_stripe_connected_accounts_by_mode.sql','20260925120000_seller_identity_verification.sql','20260926214527_deferred_marketplace_settlement.sql','20260926222000_marketplace_release_controls.sql','20260926235356_finance_category_reports.sql','20260927012001_commerce_ended_event_guard.sql']) await db.exec(readFileSync(new URL('../../supabase/migrations/'+f,import.meta.url),'utf8'));
 const one=async(sql,args=[])=>(await db.query(sql,args)).rows[0];
 const seller=(await one('insert into auth.users values(gen_random_uuid()) returning id')).id;
 const buyer=(await one('insert into auth.users values(gen_random_uuid()) returning id')).id;
 const post=(await one('insert into app_posts values(gen_random_uuid()) returning id')).id;
 await db.exec("insert into app_payment_environment(id,stripe_mode) values(true,'test')");
 const item=(await one("insert into app_purchasables(post_id,creator_id,creator_app_user_id,content_type,fulfillment_type,payment_model,title,capacity) values($1,$2,'seller','event','ticket','paid','Five dollar ticket',3) returning id",[post,seller])).id;
 const price=(await one("insert into app_prices(purchasable_id,unit_amount,currency) values($1,500,'USD') returning id",[item])).id;
 const begin=(key,quantity=1)=>one("select * from captro_begin_marketplace_purchase_v2($1,'buyer',$2,$3,$4,$5,'{}',0,0,0,'native')",[buyer,item,price,quantity,key]);
 // Exact production defect: an active status must not override an explicit past end.
 await db.query("update app_purchasables set ends_at=now()-interval '1 day' where id=$1",[item]);
 await assert.rejects(begin('expired-event-attempt'),/EVENT_ENDED/);
 assert.equal((await one('select count(*)::int n from app_purchases')).n,0);
 assert.equal((await one('select quantity_committed from app_purchasables where id=$1',[item])).quantity_committed,0);
 await db.query("update app_purchasables set starts_at=now()+interval '1 day',ends_at=now()+interval '2 days' where id=$1",[item]);
 const first=await begin('new-buyer-one');
 assert.equal(first.total_amount,500);assert.equal(first.connected_account_id,null);assert.equal(first.settlement_model,'deferred');
 assert.equal((await begin('new-buyer-one')).id,first.id);
 await assert.rejects(begin('new-buyer-one',2),/IDEMPOTENCY_CONFLICT/);
 assert.equal((await one('select count(*)::int n from app_entitlements')).n,0);
 await db.query("update app_purchases set provider_payment_id='pi_test_newbuyer' where id=$1",[first.id]);
 const confirm=(amount=500,transfer=null)=>one("select * from captro_confirm_marketplace_purchase($1,'evt_test',null,'pi_test_newbuyer','ch_test',$2,$3,45,0,'USD',now(),'digest')",[first.id,transfer,amount]);
 await assert.rejects(confirm(5),/AMOUNT_MISMATCH/);await assert.rejects(confirm(500,'tr_early'),/PREMATURE_TRANSFER/);
 assert.equal((await one('select confirmed_quantity from app_purchasables where id=$1',[item])).confirmed_quantity,0);
 await confirm();await confirm();
 assert.equal((await one("select pending from app_finance_pool_totals where category='event' and stripe_mode='test'")).pending,455);
 await db.exec('set role authenticated');await assert.rejects(db.exec('select * from app_finance_pool_totals'),/permission denied/);await db.exec('reset role');
 assert.equal((await one('select confirmed_quantity from app_purchasables where id=$1',[item])).confirmed_quantity,1);
 const earning=await one('select * from app_creator_earnings');assert.equal(earning.status,'pending');assert.equal(earning.creator_amount,455);assert.equal(earning.provider_transfer_id,null);
 assert.equal((await one('select count(*)::int n from app_commerce_tickets')).n,1);
 assert.equal((await one("select amount from captro_ledger_balances($1) where account='pending'",[seller])).amount,455);
 assert.equal((await one('select count(*)::int n from app_marketplace_ledger')).n,4);
 await assert.rejects(db.exec('update app_marketplace_ledger set amount=999'),/IMMUTABLE/);
 await assert.rejects(db.exec('delete from app_marketplace_ledger'),/IMMUTABLE/);
 const two=await begin('new-buyer-two',2);assert.equal(two.total_amount,1000);
 await assert.rejects(begin('sold-out-three'),/CAPACITY_REACHED/);
 await db.exec('set role authenticated');await assert.rejects(db.exec('select * from app_marketplace_ledger'),/permission denied/);await assert.rejects(confirm(),/permission denied/);await db.exec('reset role');
 await one("select * from captro_record_marketplace_refund('pi_test_newbuyer','re_test',500,455,0,'evt_refund','succeeded','','digest')");
 assert.equal((await one('select status from app_entitlements')).status,'refunded');
 assert.equal((await one("select amount from captro_ledger_balances($1) where account='pending'",[seller])).amount,0);
 await confirm();assert.equal((await one('select status from app_entitlements')).status,'refunded');
 assert.equal((await one("select gross from app_finance_pool_totals where category='event'")).gross,0);
 assert.equal((await one('select confirmed_quantity from app_purchasables where id=$1',[item])).confirmed_quantity,0);

 // Later completion/review/transfer is distinct from buyer confirmation.
 await db.query("update app_purchases set provider_payment_id='pi_two' where id=$1",[two.id]);
 await one("select * from captro_confirm_marketplace_purchase($1,'evt_two',null,'pi_two','ch_two',null,1000,59,0,'USD',null,'digest')",[two.id]);
 const review=()=>db.query("select captro_review_earning_release($1,'admin','Confirmed event completion',now())",[two.id]);
 await assert.rejects(review(),/FULFILLMENT_NOT_COMPLETED/);
 assert.equal((await one('select captro_confirm_fulfillment($1,$2) as ok',[two.id,seller])).ok,false);
 assert.equal((await one('select captro_confirm_fulfillment($1,$2) as ok',[two.id,buyer])).ok,true);
 await db.query("update app_purchasables set starts_at=now()-interval '2 hours',ends_at=now()-interval '1 hour' where id=$1",[item]);
 await review();
 const account=await one("insert into app_connected_accounts(user_id,app_user_id,provider_account_id,stripe_mode,status,details_submitted,charges_enabled,transfers_enabled,payouts_enabled,eligible_debit_card_exists) values($1,'seller','acct_release','test','ready',true,false,true,true,true) returning id",[seller]);
 const claim=()=>one("select * from captro_claim_earning_transfer($1,$2,'acct_release',gen_random_uuid())",[two.id,account.id]);
 await assert.rejects(claim(),/IDENTITY_REQUIRED/);
 await db.query("insert into app_seller_identity_verifications(user_id,app_user_id,stripe_mode,connected_account_id,status) values($1,'seller','test',$2,'verified')",[seller,account.id]);
 const release=await claim();assert.equal(release.amount,941);
 assert.equal((await claim())?.id,null,'concurrent request cannot claim an active lease');
 const finish=()=>one("select captro_finish_earning_transfer($1,'tr_later',941,'acct_release') as reverse",[two.id]);
 assert.equal((await finish()).reverse,false);await finish();
 assert.equal((await one("select amount from captro_ledger_balances($1) where account='transferred'",[seller])).amount,941);
 await db.query("insert into app_payouts(connected_account_id,creator_id,provider_payout_id,currency,amount,status) values($1,$2,'po_later','USD',941,'pending')",[account.id,seller]);
 await db.exec("update app_payouts set status='paid' where provider_payout_id='po_later'");
 const count=(await one('select count(*)::int n from app_marketplace_ledger')).n;
 await db.exec("update app_payouts set status='paid' where provider_payout_id='po_later'");
 await db.query("insert into app_payouts(connected_account_id,creator_id,provider_payout_id,currency,amount,status) values($1,$2,'po_later','USD',941,'paid') on conflict(provider_payout_id) do update set status=excluded.status",[account.id,seller]);
 assert.equal((await one('select count(*)::int n from app_marketplace_ledger')).n,count);
 assert.equal((await one("select amount from captro_ledger_balances($1) where account='paid_out'",[seller])).amount,941);
 assert.equal((await one("select amount from captro_ledger_balances($1) where account='transferred'",[seller])).amount,0);
 assert.equal((await one("select paid_out from app_finance_order_totals where order_id=$1",[two.id])).paid_out,941);
 assert.equal((await one("select count(*)::int n from app_marketplace_ledger where stripe_object_id='po_later' and order_id is null")).n,0);
 await db.exec("update app_payouts set status='failed' where provider_payout_id='po_later'");
 assert.equal((await one("select available from app_finance_order_totals where order_id=$1",[two.id])).available,941);
 assert.equal((await one("select paid_out from app_finance_order_totals where order_id=$1",[two.id])).paid_out,0);
 await db.exec("update app_payouts set status='paid' where provider_payout_id='po_later'");
 assert.equal((await one("select paid_out from app_finance_order_totals where order_id=$1",[two.id])).paid_out,941);
 assert.deepEqual((await db.query("select captro_finance_category(x) as category from unnest(array['event','club','meetup','deal','group','offer']) x")).rows.map(x=>x.category),['event','club','meetup','deal','group_access','local_offer']);
 // FIFO order attribution must never consume another seller, currency or mode.
 await db.query("update app_purchasables set capacity=null,starts_at=now()+interval '1 day',ends_at=now()+interval '2 days' where id=$1",[item]);
 const extra=[];
 for(const suffix of ['a','b']){
  const p=await begin('pool-allocation-'+suffix);extra.push(p);
  await db.query('update app_purchases set provider_payment_id=$2 where id=$1',[p.id,'pi_pool_'+suffix]);
  await one("select * from captro_confirm_marketplace_purchase($1,$2,null,$3,$4,null,500,45,0,'USD',null,'digest')",[p.id,'evt_pool_'+suffix,'pi_pool_'+suffix,'ch_pool_'+suffix]);
  await db.query("update app_creator_earnings set status='transferred',provider_transfer_id=$2 where purchase_id=$1",[p.id,'tr_pool_'+suffix]);
 }
 const otherSeller=(await one('insert into auth.users values(gen_random_uuid()) returning id')).id;
 for(const [key,owner,currency,mode] of [['other-seller',otherSeller,'USD','test'],['other-currency',seller,'EUR','test'],['other-mode',seller,'USD','live']]){
  await db.query("insert into app_marketplace_ledger(entry_key,seller_id,event_type,account,amount,currency,metadata) values($1,$2,'OPENING_BALANCE','transferred',999,$3,jsonb_build_object('stripe_mode',$4::text))",[key,owner,currency,mode]);
 }
 await db.query("insert into app_payouts(connected_account_id,creator_id,provider_payout_id,currency,amount,status) values($1,$2,'po_partial','USD',500,'paid')",[account.id,seller]);
 const allocations=(await db.query("select order_id,amount from app_marketplace_ledger where stripe_object_id='po_partial' and account='paid_out' order by amount desc")).rows;
 assert.deepEqual(allocations.map(x=>x.amount),[455,45]);
 assert.ok(allocations.every(x=>extra.some(p=>p.id===x.order_id)));
 assert.equal((await one("select sum(amount)::int n from app_marketplace_ledger where seller_id=$1 and account='transferred'",[otherSeller])).n,999);
 assert.equal((await one("select sum(amount)::int n from app_marketplace_ledger where currency='EUR' and account='transferred'")).n,999);
 assert.equal((await one("select sum(amount)::int n from app_marketplace_ledger where metadata->>'stripe_mode'='live' and account='transferred'")).n,999);
 await db.exec("update app_payouts set status='failed' where provider_payout_id='po_partial'");
 assert.equal((await one("select sum(available)::int n from app_finance_order_totals where order_id=any($1::uuid[])",[extra.map(p=>p.id)])).n,910);
 await assert.rejects(db.exec("update app_payouts set amount=1 where provider_payout_id='po_partial'"),/SNAPSHOT_IMMUTABLE/);
 for(const role of ['anon','authenticated']){
  await db.exec('set role '+role);
  await assert.rejects(db.exec('select * from app_finance_order_totals'),/permission denied/);
  await assert.rejects(db.exec('select * from app_finance_ledger'),/permission denied/);
  await db.exec('reset role');
 }
 assert.equal((await one("select available from app_finance_seller_totals where seller_id=$1 and currency='USD' and stripe_mode='test'",[seller])).available,910);
 assert.equal((await one("select available from app_finance_seller_totals where seller_id=$1 and currency='USD' and stripe_mode='live'",[seller])).available,999);
 const ticket=await one('select t.* from app_commerce_tickets t join app_entitlements e on e.id=t.entitlement_id where e.purchase_id=$1',[two.id]);
 const validate=(owner=seller)=>one("select captro_validate_pass('ticket',$1,$2,1) result",[ticket.id,owner]);
 await assert.rejects(validate(buyer),/PASS_INVALID/);
 assert.equal((await validate()).result.status,'valid');
 assert.equal((await one('select status from app_commerce_tickets where id=$1',[ticket.id])).status,'active');
 await one("select * from captro_consume_ticket($1,$2,1,'check-in')",[ticket.id,seller]);
 await assert.rejects(validate(),/ALREADY_USED/);
 await assert.rejects(one("select * from captro_consume_ticket($1,$2,1,'duplicate')",[ticket.id,seller]),/ALREADY_USED/);
 const refunded=await one('select t.* from app_commerce_tickets t join app_entitlements e on e.id=t.entitlement_id where e.purchase_id=$1',[first.id]);
 await assert.rejects(one("select captro_validate_pass('ticket',$1,$2,1)",[refunded.id,seller]),/PASS_REFUNDED/);
 }finally{await db.close();}
});
