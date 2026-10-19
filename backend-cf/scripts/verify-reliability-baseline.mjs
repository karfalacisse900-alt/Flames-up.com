const {CLOUDFLARE_API_TOKEN:token,CLOUDFLARE_ACCOUNT_ID:account}=process.env;
if(!token||account!=='2ca88b3551321681a5f9434814f38ec8')throw Error('Expected Captro account credentials unavailable');
const r=await fetch(`https://api.cloudflare.com/client/v4/accounts/${account}/workers/scripts/flames-up-api/deployments`,{
  headers:{Authorization:`Bearer ${token}`},signal:AbortSignal.timeout(20000)});
if(!r.ok)throw Error('Deployment lookup HTTP '+r.status);
const data=await r.json();const versions=data.result?.deployments?.[0]?.versions;
if(versions?.length!==1||versions[0].version_id!=='a25d5a5a-4088-4ced-85bd-13a5f83d3549'||versions[0].percentage!==100)
  throw Error('Production changed since review; inspect the new baseline before deploying.');
console.log('Verified scoped Profile production baseline a25d5a5a-4088-4ced-85bd-13a5f83d3549');
