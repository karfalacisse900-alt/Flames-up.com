const {CLOUDFLARE_API_TOKEN:token,CLOUDFLARE_ACCOUNT_ID:account}=process.env;
if(!token||account!=='2ca88b3551321681a5f9434814f38ec8')throw Error('Expected Captro account credentials unavailable');
const r=await fetch(`https://api.cloudflare.com/client/v4/accounts/${account}/workers/scripts/flames-up-api/deployments`,{
  headers:{Authorization:`Bearer ${token}`},signal:AbortSignal.timeout(20000)});
if(!r.ok)throw Error('Deployment lookup HTTP '+r.status);
const data=await r.json();const versions=data.result?.deployments?.[0]?.versions;
if(versions?.length!==1||versions[0].version_id!=='3e268d98-a9ff-4d7b-8f5a-284323d86bde'||versions[0].percentage!==100)
  throw Error('Production changed since review; inspect the new baseline before deploying.');
console.log('Verified maintenance Worker 3e268d98-a9ff-4d7b-8f5a-284323d86bde from run 39329583253; resume forward repair.');
const settings=await fetch(`https://api.cloudflare.com/client/v4/accounts/${account}/workers/scripts/flames-up-api/settings`,{
  headers:{Authorization:`Bearer ${token}`},signal:AbortSignal.timeout(20000)});
if(!settings.ok)throw Error('Settings lookup HTTP '+settings.status);
const bindings=(await settings.json()).result?.bindings;
if(!Array.isArray(bindings))throw Error('Missing binding inventory');
// Existing settings stay untouched. Do not let a previously configured value
// accidentally authorize destructive cleanup or financial recovery mutations.
for(const name of ['CAPTRO_ACCOUNT_CLEANUP_MANIFEST','CAPTRO_PAYMENT_RECOVERY_ACTIONS'])
  if(bindings.some(b=>b.name===name && (b.type!=='plain_text'||b.text!=='blocked')))
    throw Error('Sensitive action gate requires review: '+name);
console.log('Destructive cleanup and recovery actions remain disabled.');
