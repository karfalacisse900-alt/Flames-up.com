import assert from 'node:assert/strict';
import {createPrivateKey,sign} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

export const SUPPORT_PROFILE_NAME='Captro_App_Store_Support_Return_v1';
const originalProfile='RSYRZK54QT'; // Read-only Apple audit 39402862574.
export function validateSupportAssociation(value) {
  assert.deepEqual(Object.keys(value),['applinks']);
  assert.equal(value.applinks.details.length,1);
  const entry=value.applinks.details[0];
  assert.deepEqual(entry.appIDs,['56C9MBK53P.com.captro.app']);
  assert.equal(entry.components.length,1);
  assert.equal(entry.components[0]['/'],'/support-creator/return');
  assert.deepEqual(entry.components[0]['?'],{purchase_id:'????????-????-????-????-????????????'});
}
export async function supportSigningProfile(api,apply=false) {
  const list=await api('GET','bundleIds?filter%5Bidentifier%5D=com.captro.app&limit=2');
  assert.equal(list.data?.length,1);
  const bundle=list.data[0];assert.equal(bundle.attributes.identifier,'com.captro.app');
  const capabilities=await api('GET',`bundleIds/${bundle.id}/bundleIdCapabilities`);
  const profiles=await api('GET',`bundleIds/${bundle.id}/profiles?limit=200`);
  assert.ok(!profiles.links?.next,'Profile list requires reviewed pagination');
  const original=profiles.data.find(p=>p.id===originalProfile);
  assert.equal(original?.attributes.profileType,'IOS_APP_STORE','Original signing identity is required');
  const certificates=await api('GET',`profiles/${originalProfile}/relationships/certificates`);
  const ids=certificates.data.map(c=>c.id).sort();
  assert.ok(ids.length>0&&ids.length<=3,'Reuse existing distribution certificate(s) only');
  let capable=capabilities.data.some(c=>c.attributes.capabilityType==='ASSOCIATED_DOMAINS');
  if(!capable) {
    assert.equal(apply,true,'Associated Domains is not configured');
    await api('POST','bundleIdCapabilities',{data:{type:'bundleIdCapabilities',attributes:{capabilityType:'ASSOCIATED_DOMAINS'},
      relationships:{bundleId:{data:{type:'bundleIds',id:bundle.id}}}}});
    capable=(await api('GET',`bundleIds/${bundle.id}/bundleIdCapabilities`)).data.some(c=>c.attributes.capabilityType==='ASSOCIATED_DOMAINS');
    assert.ok(capable,'Apple has not confirmed Associated Domains');
  }
  let profile=profiles.data.find(p=>p.attributes.name===SUPPORT_PROFILE_NAME);
  if(!profile) {
    assert.equal(apply,true,'Support return signing profile is not configured');
    profile=(await api('POST','profiles',{data:{type:'profiles',attributes:{name:SUPPORT_PROFILE_NAME,profileType:'IOS_APP_STORE'},
      relationships:{bundleId:{data:{type:'bundleIds',id:bundle.id}},certificates:{data:ids.map(id=>({type:'certificates',id}))}}}})).data;
  }
  assert.equal(profile.attributes.profileState,'ACTIVE');
  assert.equal(profile.attributes.profileType,'IOS_APP_STORE');
  assert.ok(Date.parse(profile.attributes.expirationDate)>Date.now()+86400_000);
  const linked=await api('GET',`profiles/${profile.id}/relationships/bundleId`);
  assert.equal(linked.data.id,bundle.id);
  const signedBy=await api('GET',`profiles/${profile.id}/relationships/certificates`);
  assert.deepEqual(signedBy.data.map(c=>c.id).sort(),ids,'Do not replace signing certificates');
  return profile;
}
async function main() {
  assert.equal(process.env.GITHUB_ACTIONS,'true');
  const mode=process.argv[2];assert.ok(['--apply','--download'].includes(mode));
  const env=name=>{assert.ok(process.env[name],name+' is required');return process.env[name];};
  const key=createPrivateKey(Buffer.from(env('APP_STORE_CONNECT_API_KEY_BASE64'),'base64'));
  const now=Math.floor(Date.now()/1000),encode=o=>Buffer.from(JSON.stringify(o)).toString('base64url');
  const input=encode({alg:'ES256',kid:env('APP_STORE_CONNECT_API_KEY_ID'),typ:'JWT'})+'.'+encode({iss:env('APP_STORE_CONNECT_API_ISSUER_ID'),iat:now,exp:now+600,aud:'appstoreconnect-v1'});
  const token=input+'.'+sign('sha256',Buffer.from(input),{key,dsaEncoding:'ieee-p1363'}).toString('base64url');
  const api=async(method,path,body)=>{
    assert.ok(method==='GET'||(mode==='--apply'&&method==='POST'&&['profiles','bundleIdCapabilities'].includes(path)));
    const response=await fetch('https://api.appstoreconnect.apple.com/v1/'+path,{method,redirect:'error',
      headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(30000)});
    const result=await response.json();
    if(!response.ok)throw Error('Apple signing API HTTP '+response.status+' '+(result.errors?.[0]?.code??'unknown'));
    return result;
  };
  const aasa=await fetch('https://captro-site.pages.dev/.well-known/apple-app-site-association',{redirect:'error',signal:AbortSignal.timeout(20000)});
  assert.equal(aasa.status,200);assert.match(aasa.headers.get('content-type')??'',/application\/json/);
  validateSupportAssociation(await aasa.json());
  const profile=await supportSigningProfile(api,mode==='--apply');
  const data=Buffer.from(profile.attributes.profileContent,'base64');
  let xml;
  try { xml=execFileSync(process.platform==='darwin'?'security':'openssl',
    process.platform==='darwin'?['cms','-D']:['cms','-verify','-inform','DER','-noverify'],
    {input:data,encoding:'utf8',stdio:['pipe','pipe','pipe'],maxBuffer:2*1024*1024}); }
  catch { throw Error('Could not validate signed provisioning profile'); }
  assert.match(xml,/<key>application-identifier<\/key>\s*<string>56C9MBK53P\.com\.captro\.app<\/string>/);
  assert.match(xml,/<key>com\.apple\.developer\.associated-domains<\/key>/);
  assert.match(xml,/<key>com\.apple\.developer\.applesignin<\/key>\s*<array>\s*<string>Default<\/string>/);
  if(mode==='--download') {
    const target=resolve(process.argv[3]??'');
    assert.equal(target,resolve(env('RUNNER_TEMP'),'captro.mobileprovision'),'Only write the ephemeral build profile');
    await writeFile(target,data,{mode:0o600});
  }
  console.log(JSON.stringify({supportReturnSigning:true,mode,profile:SUPPORT_PROFILE_NAME,profileID:profile.id,
    associatedDomains:true,bundle:'com.captro.app',certificateReused:true,paymentActivation:false}));
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url))await main();
