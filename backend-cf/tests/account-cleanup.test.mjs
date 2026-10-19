import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {PGlite} from '@electric-sql/pglite';
import {runAccountCleanup} from '../src/account-cleanup.ts';

test('each mandatory cleanup failure preserves the phase and supports a later retry',async()=>{
  for(let phase=0;phase<5;phase++) {
    let fail=true;const writes=[];let called=0;
    const steps=Array.from({length:5},(_,i)=>async()=>{assert.equal(i,phase);called++;if(fail)throw Error('private provider response');return true;});
    const checkpoint=async(p,e)=>{writes.push([p,e]);return true;};
    await assert.rejects(runAccountCleanup({phase,lease_token:'fixture'},steps,checkpoint));
    assert.deepEqual(writes,[[phase,'CLEANUP_STEP_FAILED']]);
    fail=false;await runAccountCleanup({phase,lease_token:'fixture'},steps,checkpoint);
    assert.deepEqual(writes[1],[phase+1,null]);assert.equal(called,2);
  }
});
test('bounded media/post batches never claim phase completion before enumeration is empty',async()=>{
  const writes=[];let remaining=10051;
  while(remaining>0) await runAccountCleanup({phase:0,lease_token:'fixture'},[async()=>{remaining-=Math.min(50,remaining);return false;}],async(p,e)=>{writes.push(p);return true;});
  assert.ok(writes.length>200);assert.ok(writes.every(p=>p===0));
  await runAccountCleanup({phase:0,lease_token:'fixture'},[async()=>true],async(p)=>{writes.push(p);return true;});
  assert.equal(writes.at(-1),1);
});
test('cleanup SQL denies clients, serializes restore, retains Auth ID, scrubs phones only at completion',async()=>{
  const db=new PGlite();try {
    await db.exec(`create role anon;create role authenticated;create role service_role;
      create table app_users(id text primary key,supabase_user_id uuid,email text,phone text,phone_verified boolean,email_verified boolean,
      username text,full_name text,avatar_url text,cover_url text,bio text,city text,is_private boolean,is_verified boolean,profile jsonb,counts jsonb,metadata jsonb,updated_at timestamptz);`);
    await db.exec(readFileSync(new URL('../../supabase/migrations/20261019013048_retryable_account_cleanup.sql',import.meta.url),'utf8'));
    const one=async(sql,args=[])=>(await db.query(sql,args)).rows[0];
    await db.exec(`insert into app_users(id,supabase_user_id,email,phone,phone_verified,email_verified,metadata) values
      ('fixture','00000000-0000-4000-8000-000000000001','fixture@example.invalid','fixture-phone',true,true,
       jsonb_build_object('status','deletion_pending','deletion_scheduled_at',now()-interval '1 day'));`);
    let job=await one("select * from captro_claim_account_cleanup('fixture')");
    assert.equal(job.phase,0);assert.ok(job.lease_token);
    assert.equal((await one("select * from captro_claim_account_cleanup('fixture')")).lease_token,null);
    await assert.rejects(db.query("select captro_restore_pending_account('fixture')"),/CLEANUP_ALREADY_STARTED/);
    await assert.rejects(db.exec("set role authenticated;select * from app_account_cleanup_jobs"),/permission denied/);await db.exec('reset role');
    for(let phase=0;phase<5;phase++) {
      if(phase)job=await one("select * from captro_claim_account_cleanup('fixture')");
      assert.equal(job.phase,phase);
      assert.ok(job.auth_user_id);
      assert.equal((await one('select captro_checkpoint_account_cleanup($1,$2,$3,null) ok',['fixture',job.lease_token,phase+1])).ok,true);
    }
    const user=await one("select * from app_users where id='fixture'");
    assert.equal(user.metadata.status,'deleted');assert.equal(user.phone,null);assert.equal(user.email,null);
    assert.equal(user.phone_verified,false);assert.equal(user.email_verified,false);assert.equal(user.supabase_user_id,null);
    assert.equal((await one("select auth_user_id from app_account_cleanup_jobs where user_id='fixture'")).auth_user_id,null);
  }finally{await db.close();}
});
