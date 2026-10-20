import test from 'node:test';
import assert from 'node:assert/strict';
import {supportSigningProfile,SUPPORT_PROFILE_NAME,validateSupportAssociation} from '../../scripts/app-store/support-link-signing.mjs';
function fixture(){
 let enabled=false,created=false;const writes=[];
 const profile={id:'new',attributes:{name:SUPPORT_PROFILE_NAME,profileType:'IOS_APP_STORE',profileState:'ACTIVE',expirationDate:'2035-01-01T00:00:00Z'}};
 const api=async(method,path,body)=>{
  if(method==='POST'){writes.push({path,body});if(path==='bundleIdCapabilities'){enabled=true;return {};}assert.equal(path,'profiles');created=true;return {data:profile};}
  if(path.startsWith('bundleIds?'))return {data:[{id:'bundle',attributes:{identifier:'com.captro.app'}}]};
  if(path.endsWith('/bundleIdCapabilities'))return {data:enabled?[{attributes:{capabilityType:'ASSOCIATED_DOMAINS'}}]:[]};
  if(path.endsWith('/profiles?limit=200'))return {data:[{id:'RSYRZK54QT',attributes:{profileType:'IOS_APP_STORE'}},...(created?[profile]:[])]};
  if(path.endsWith('/relationships/certificates'))return {data:[{id:'existing-certificate'}]};
  if(path.endsWith('/relationships/bundleId'))return {data:{id:'bundle'}};
  throw Error('Unexpected endpoint');
 };
 return {api,writes};
}
test('return signing is opt-in, scoped, idempotent and reuses certificates without deleting anything',async()=>{
 const f=fixture();await assert.rejects(supportSigningProfile(f.api,false),/not configured/);assert.equal(f.writes.length,0);
 await supportSigningProfile(f.api,true);await supportSigningProfile(f.api,true);await supportSigningProfile(f.api,false);
 assert.deepEqual(f.writes.map(w=>w.path),['bundleIdCapabilities','profiles']);
 assert.equal(f.writes[0].body.data.attributes.capabilityType,'ASSOCIATED_DOMAINS');
 assert.deepEqual(f.writes[1].body.data.relationships.certificates.data,[{type:'certificates',id:'existing-certificate'}]);
});
test('wrong association or signing identity stops before distribution',async()=>{
 for(const value of [{}, {applinks:{details:[{appIDs:['wrong'],components:[]}]}}])assert.throws(()=>validateSupportAssociation(value));
 const f=fixture();await supportSigningProfile(f.api,true);
 await assert.rejects(supportSigningProfile(async(m,p,b)=>p==='profiles/new/relationships/bundleId'?{data:{id:'wrong'}}:f.api(m,p,b)),/Expected values/);
});
