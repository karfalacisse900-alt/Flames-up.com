import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { PGlite } from '@electric-sql/pglite';

// Isolated PostgreSQL execution tests, not payment-provider integration evidence.
test('native payment migrations enforce snapshots, idempotency, ticket issuance and refund capacity', async () => {
  const db = new PGlite();
  try {
    await db.exec(`create role anon; create role authenticated; create role service_role;
      create schema auth; create table auth.users(id uuid primary key);
      create table public.app_posts(id uuid primary key);
      create table public.app_group_chat_members(group_id text,user_id text,role text,joined_at timestamptz,primary key(group_id,user_id));`);
    for (const file of ['20260904193517_captro_commerce_entitlements.sql', '20260904221545_stripe_connect_creator_earnings.sql',
      '20260904221847_stripe_connect_fk_indexes.sql', '20260904231905_stripe_native_payments.sql']) {
      await db.exec(readFileSync(new URL(`../../supabase/migrations/${file}`, import.meta.url), 'utf8'));
    }
    const one = async (sql, params = []) => (await db.query(sql, params)).rows[0];
    const seller = (await one('insert into auth.users values(gen_random_uuid()) returning id')).id;
    const buyer = (await one('insert into auth.users values(gen_random_uuid()) returning id')).id;
    const post = (await one('insert into app_posts values(gen_random_uuid()) returning id')).id;
    await db.query(`insert into app_connected_accounts(user_id,app_user_id,provider_account_id,status,details_submitted,
      charges_enabled,payouts_enabled,eligible_debit_card_exists) values($1,'seller','acct_fixture','ready',true,true,true,true)`, [seller]);
    const item = (await one(`insert into app_purchasables(post_id,creator_id,creator_app_user_id,content_type,
      fulfillment_type,payment_model,title,capacity) values($1,$2,'seller','event','ticket','paid','Test event',2) returning id`, [post,seller])).id;
    const price = (await one(`insert into app_prices(purchasable_id,unit_amount,currency) values($1,2000,'USD') returning id`, [item])).id;
    const begin = key => one(`select * from captro_begin_marketplace_purchase_v2($1,'buyer',$2,$3,1,$4,'{}',150,0,0,'native')`, [buyer,item,price,key]);
    const first = await begin('request-one');
    assert.equal(first.creator_amount,2000); assert.equal(first.total_amount,2150);
    assert.equal(first.payment_interface,'native');
    assert.equal((await begin('request-one')).id,first.id);
    await assert.rejects(one(`select * from captro_begin_marketplace_purchase_v2($1,'buyer',$2,$3,2,'request-one','{}',150,0,0,'native')`, [buyer,item,price]), /IDEMPOTENCY_CONFLICT/);
    assert.equal((await one('select count(*)::int n from app_entitlements')).n,0);
    await db.query(`update app_purchases set provider_payment_id='pi_fixture', hold_expires_at=now()-interval '1 minute' where id=$1`,[first.id]);
    await db.exec('select captro_release_expired_purchase_holds()');
    assert.equal((await one('select status from app_purchases where id=$1',[first.id])).status,'payment_pending');
    const confirm = (amount,event='evt_fixture') => one(`select * from captro_confirm_marketplace_purchase($1,$2,null,'pi_fixture','ch_fixture','tr_fixture',$3,92,0,'USD',null,'digest')`,[first.id,event,amount]);
    await assert.rejects(confirm(100), /AMOUNT_MISMATCH/);
    await confirm(2150); await confirm(2150,'evt_second_delivery');
    assert.equal((await one('select count(*)::int n from app_creator_earnings')).n,1);
    assert.equal((await one('select creator_amount from app_creator_earnings')).creator_amount,2000);
    assert.equal((await one('select count(*)::int n from app_commerce_tickets')).n,1);
    await db.query('update app_prices set unit_amount=9000 where id=$1',[price]);
    assert.equal((await one('select item_amount from app_purchases where id=$1',[first.id])).item_amount,2000);
    await begin('request-two');
    const refund = event => one(`select * from captro_record_marketplace_refund('pi_fixture','re_fixture',2150,2000,150,$1,'succeeded','','digest')`,[event]);
    await refund('evt_refund'); await refund('evt_refund_replayed');
    assert.equal((await one('select quantity_committed from app_purchasables where id=$1',[item])).quantity_committed,1);
    assert.equal((await one('select count(*)::int n from app_refunds')).n,1);
    assert.equal((await one('select status from app_entitlements')).status,'refunded');
    assert.equal((await one('select refunded_amount from app_creator_earnings')).refunded_amount,2000);
    await db.exec('set role authenticated');
    await assert.rejects(db.exec('select * from app_payout_requests'), /permission denied/);
  } finally { await db.close(); }
});
