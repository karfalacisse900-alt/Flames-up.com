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
      create table public.app_group_chat_members(id text,group_id text,user_id text,role text,legacy_created_at timestamptz,created_at timestamptz,updated_at timestamptz,primary key(group_id,user_id));`);
    for (const file of ['20260904193517_captro_commerce_entitlements.sql', '20260904221545_stripe_connect_creator_earnings.sql',
      '20260904221847_stripe_connect_fk_indexes.sql', '20260904231905_stripe_native_payments.sql',
      '20260908224758_isolate_stripe_connected_accounts_by_mode.sql', '20260912214322_captro_custom_payout_accounts.sql',
      '20260912225447_allow_unused_legacy_express_payout_migration.sql',
      '20260925120000_seller_identity_verification.sql']) {
      await db.exec(readFileSync(new URL(`../../supabase/migrations/${file}`, import.meta.url), 'utf8'));
    }
    const one = async (sql, params = []) => (await db.query(sql, params)).rows[0];
    const seller = (await one('insert into auth.users values(gen_random_uuid()) returning id')).id;
    const buyer = (await one('insert into auth.users values(gen_random_uuid()) returning id')).id;
    const post = (await one('insert into app_posts values(gen_random_uuid()) returning id')).id;
    await db.exec("insert into app_payment_environment(id,stripe_mode) values(true,'test')");
    const testConnected = await one(`insert into app_connected_accounts(user_id,app_user_id,provider_account_id,stripe_mode,status,details_submitted,
      charges_enabled,transfers_enabled,payouts_enabled,eligible_debit_card_exists)
      values($1,'seller','acct_fixture','test','ready',true,false,true,true,true) returning id`, [seller]);
    await db.query(`insert into app_seller_identity_verifications(user_id,app_user_id,stripe_mode,connected_account_id,provider_session_id,status)
      values($1,'seller','test',$2,'vs_fixture','processing')`, [seller,testConnected.id]);
    await assert.rejects(db.query(`insert into app_seller_identity_verifications(user_id,app_user_id,stripe_mode,connected_account_id)
      values($1,'seller','test',$2)`, [seller,testConnected.id]), /duplicate key/);
    assert.equal((await one('select status from app_seller_identity_verifications where user_id=$1', [seller])).status, 'processing');
    await db.query(`insert into app_connected_accounts(user_id,app_user_id,provider_account_id,stripe_mode,status,details_submitted,
      charges_enabled,transfers_enabled,payouts_enabled,eligible_debit_card_exists)
      values($1,'seller','acct_live_fixture','live','ready',true,false,true,true,true)`, [seller]);
    const legacyPayoutUser = (await one('insert into auth.users values(gen_random_uuid()) returning id')).id;
    const legacyPayout = await one(`insert into app_connected_accounts(user_id,app_user_id,provider_account_id,stripe_mode,account_type,status,details_submitted,
      charges_enabled,transfers_enabled,payouts_enabled,eligible_debit_card_exists)
      values($1,'legacy-payout','acct_legacyupgrade','test','express','restricted',true,false,true,true,false) returning id`, [legacyPayoutUser]);
    const protectedLegacyUser = (await one('insert into auth.users values(gen_random_uuid()) returning id')).id;
    const protectedLegacy = await one(`insert into app_connected_accounts(user_id,app_user_id,provider_account_id,stripe_mode,account_type,status,
      details_submitted,charges_enabled,transfers_enabled,payouts_enabled,eligible_debit_card_exists,payout_card)
      values($1,'legacy-card','acct_legacycard','test','express','ready',true,false,true,true,true,'{"id":"card_protected"}'::jsonb) returning id`, [protectedLegacyUser]);
    const item = (await one(`insert into app_purchasables(post_id,creator_id,creator_app_user_id,content_type,
      fulfillment_type,payment_model,title,capacity) values($1,$2,'seller','event','ticket','paid','Test event',2) returning id`, [post,seller])).id;
    const price = (await one(`insert into app_prices(purchasable_id,unit_amount,currency) values($1,2000,'USD') returning id`, [item])).id;
    const begin = key => one(`select * from captro_begin_marketplace_purchase_v2($1,'buyer',$2,$3,1,$4,'{}',150,0,0,'native')`, [buyer,item,price,key]);
    const first = await begin('request-one');
    assert.equal(first.creator_amount,2000); assert.equal(first.total_amount,2150);
    assert.equal(first.connected_account_id,testConnected.id, 'the purchase must use the account from the configured Stripe mode');
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
    const refund = (event, reversed = 2000, status = 'succeeded') => one(`select * from captro_record_marketplace_refund('pi_fixture','re_fixture',2150,$2,150,$1,$3,'','digest')`,[event,reversed,status]);
    await refund('evt_refund',0);
    assert.equal((await one('select refunded_amount from app_creator_earnings')).refunded_amount,0, 'never claim transfer recovery before it occurs');
    assert.equal((await one('select status from app_entitlements')).status,'refunded', 'refund must revoke access even if recovery fails');
    await refund('evt_refund_recovered'); await refund('evt_refund_replayed');
    await refund('evt_refund_stale',0,'pending');
    await confirm(2150,'evt_payment_after_refund');
    await assert.rejects(confirm(100,'evt_wrong_after_refund'), /AMOUNT_MISMATCH/);
    assert.equal((await one('select quantity_committed from app_purchasables where id=$1',[item])).quantity_committed,1);
    assert.equal((await one('select count(*)::int n from app_refunds')).n,1);
    assert.equal((await one('select status from app_entitlements')).status,'refunded');
    assert.equal((await one('select refunded_amount from app_creator_earnings')).refunded_amount,2000);
    assert.equal((await one('select status from app_refunds')).status,'succeeded');
    const record = status => one(`select captro_record_stripe_webhook_event('evt_delivery','payment_intent.succeeded',null,$1,'digest','timeout')`, [status]);
    await record('failed');
    assert.equal((await one("select status from app_payment_webhook_events where provider_event_id='evt_delivery'")).status, 'failed');
    await record('processed');
    await record('failed');
    const delivered = await one("select * from app_payment_webhook_events where provider_event_id='evt_delivery'");
    assert.equal(delivered.status, 'processed');
    assert.equal(delivered.error_code, null);
    const upgradeLegacyPayout = () => one(`select public.captro_upgrade_untouched_payout_account(
      $1,$2,'legacy-payout','test','acct_legacyupgrade','acct_captromigrated'
    ) as upgraded`, [legacyPayout.id, legacyPayoutUser]);
    await db.exec('set role authenticated');
    await assert.rejects(upgradeLegacyPayout(), /permission denied/,
      'only the service role may atomically replace an untouched legacy payout profile');
    await assert.rejects(db.exec('select * from public.app_retired_connected_accounts'), /permission denied/);
    await assert.rejects(db.exec('select * from app_payout_requests'), /permission denied/);
    await assert.rejects(db.exec('select * from app_payment_reconciliation_issues'), /permission denied/);
    await assert.rejects(record('processed'), /permission denied/);
    await db.exec('set role service_role');
    assert.equal((await upgradeLegacyPayout()).upgraded, true,
      'the service role can replace an abandoned Express profile even after its owner started onboarding');
    const protectedUpgrade = () => one(`select public.captro_upgrade_untouched_payout_account(
      $1,$2,'legacy-card','test','acct_legacycard','acct_replacementcard'
    ) as upgraded`, [protectedLegacy.id, protectedLegacyUser]);
    assert.equal((await protectedUpgrade()).upgraded, false,
      'a legacy profile with a payout card must never be remapped automatically');
    await db.exec('reset role');
    const upgradedPayout = await one('select provider_account_id, account_type, status, details_submitted, transfers_enabled, payouts_enabled, eligible_debit_card_exists from app_connected_accounts where id=$1', [legacyPayout.id]);
    assert.deepEqual(upgradedPayout, {
      provider_account_id: 'acct_captromigrated', account_type: 'custom', status: 'onboarding',
      details_submitted: false, transfers_enabled: false, payouts_enabled: false, eligible_debit_card_exists: false
    });
    const retiredPayout = await one(`select provider_account_id, stripe_mode, replacement_provider_account_id,
      migrated_to_connected_account_id, retirement_reason from public.app_retired_connected_accounts
      where provider_account_id='acct_legacyupgrade' and stripe_mode='test'`);
    assert.deepEqual(retiredPayout, {
      provider_account_id: 'acct_legacyupgrade', stripe_mode: 'test', replacement_provider_account_id: 'acct_captromigrated',
      migrated_to_connected_account_id: legacyPayout.id, retirement_reason: 'captro_managed_payout_account_upgrade'
    });
    // Execute the actual free-club membership path with a restricted seller.
    // This must not create Stripe accounts for the buyer or require seller KYC.
    await db.query("update app_connected_accounts set status='restricted',transfers_enabled=false,payouts_enabled=false where user_id=$1", [seller]);
    const freePost = (await one('insert into app_posts values(gen_random_uuid()) returning id')).id;
    const freeClub = (await one("insert into app_purchasables(post_id,creator_id,creator_app_user_id,content_type,fulfillment_type,payment_model,title,private_config) values($1,$2,'seller','club','membership','free','Free club','{\"group_chat_id\":\"test-group\"}') returning id", [freePost,seller])).id;
    const freePrice = (await one("insert into app_prices(purchasable_id,unit_amount,currency) values($1,0,'USD') returning id", [freeClub])).id;
    const join = key => one("select * from captro_begin_marketplace_purchase_v2($1,'buyer',$2,$3,1,$4,'{}',0,0,0,'native')", [buyer,freeClub,freePrice,key]);
    const joined = await join('free-join-one');
    assert.equal(joined.status,'confirmed');
    assert.equal(joined.total_amount,0);
    assert.equal((await join('free-join-one')).id,joined.id);
    assert.equal((await join('free-join-again')).id,joined.id);
    assert.equal((await one("select count(*)::int n from app_group_chat_members where group_id='test-group' and user_id='buyer'")).n,1);
    assert.equal((await one('select count(*)::int n from app_connected_accounts where user_id=$1',[buyer])).n,0);
    await assert.rejects(one("select * from captro_begin_marketplace_purchase_v2($1,'seller',$2,$3,1,'own-join-test','{}',0,0,0,'native')", [seller,freeClub,freePrice]), /CREATOR_CANNOT_PURCHASE/);
    await assert.rejects(begin('restricted-seller-test'), /PAYOUTS_NOT_READY/);
  } finally { await db.close(); }
});
