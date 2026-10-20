import { createPrivateKey, sign } from 'node:crypto';
import { execFileSync } from 'node:child_process';
// Read-only: no tester invitations, agreements, public releases, or billing changes.
const env = name => { const value = process.env[name]; if (!value) throw Error(name + ' is required'); return value; };
const key = createPrivateKey(Buffer.from(env('APP_STORE_CONNECT_API_KEY_BASE64'), 'base64'));
const now = Math.floor(Date.now() / 1000);
const encode = object => Buffer.from(JSON.stringify(object)).toString('base64url');
const input = encode({alg:'ES256',kid:env('APP_STORE_CONNECT_API_KEY_ID'),typ:'JWT'}) + '.' + encode({iss:env('APP_STORE_CONNECT_API_ISSUER_ID'),iat:now,exp:now+600,aud:'appstoreconnect-v1'});
const token = input + '.' + sign('sha256',Buffer.from(input),{key,dsaEncoding:'ieee-p1363'}).toString('base64url');
async function get(path) {
  const response = await fetch('https://api.appstoreconnect.apple.com/v1/' + path,{headers:{Authorization:'Bearer '+token},signal:AbortSignal.timeout(30000)});
  const result = await response.json();
  if (!response.ok) throw Error('App Store Connect HTTP '+response.status+': '+(result.errors?.[0]?.code ?? 'unknown'));
  return result;
}
const apps = await get('apps?' + new URLSearchParams({'filter[bundleId]':'com.captro.app',limit:'1'}));
const app = apps.data?.[0]; if (!app) throw Error('Captro app not found');
const builds = await get('builds?' + new URLSearchParams({'filter[app]':app.id,sort:'-uploadedDate',limit:'4',include:'buildBetaDetail,betaGroups,preReleaseVersion'}));
const included = builds.included ?? [];
for (const build of builds.data ?? []) {
  const detailID = build.relationships?.buildBetaDetail?.data?.id;
  const detail = included.find(item=>item.type==='buildBetaDetails'&&item.id===detailID);
  const versionID = build.relationships?.preReleaseVersion?.data?.id;
  const version = included.find(item=>item.type==='preReleaseVersions'&&item.id===versionID);
  const groups = build.relationships?.betaGroups?.data ?? [];
  console.log(JSON.stringify({build:build.attributes.version,version:version?.attributes?.version,uploaded:build.attributes.uploadedDate,processing:build.attributes.processingState,expired:build.attributes.expired,beta:detail?.attributes,groups:groups.map(g=>included.find(item=>item.type==='betaGroups'&&item.id===g.id)?.attributes?.name ?? 'assigned group')}));
}
// Read-only signing audit. Decode profiles in memory; never log profile contents,
// certificates, private keys or the bearer. This does not enable a capability.
const bundleIDs = await get('bundleIds?' + new URLSearchParams({'filter[identifier]':'com.captro.app',limit:'2'}));
if (bundleIDs.data?.length !== 1) throw Error('Expected one exact Captro bundle registration');
const bundle = bundleIDs.data[0];
const capabilities = await get(`bundleIds/${bundle.id}/bundleIdCapabilities?limit=200`);
const profiles = await get(`bundleIds/${bundle.id}/profiles?limit=200`);
console.log(JSON.stringify({signingAudit:{bundle:'com.captro.app',
  associatedDomainsRegistered:capabilities.data?.some(c=>c.attributes.capabilityType==='ASSOCIATED_DOMAINS'),
  profileCount:profiles.data?.length ?? 0}}));
for (const profile of profiles.data ?? []) {
  const a = profile.attributes;
  if (a.profileType !== 'IOS_APP_STORE') continue;
  let xml;
  try { xml = execFileSync('openssl',['cms','-verify','-inform','DER','-noverify'],
    {input:Buffer.from(a.profileContent,'base64'),encoding:'utf8',stdio:['pipe','pipe','pipe'],maxBuffer:2*1024*1024}); }
  catch { throw Error('Could not decode distribution profile for signing audit'); }
  console.log(JSON.stringify({distributionProfile:{id:profile.id,name:a.name,state:a.profileState,expires:a.expirationDate,
    associatedDomains:/<key>com\.apple\.developer\.associated-domains<\/key>/.test(xml),
    appleSignIn:/<key>com\.apple\.developer\.applesignin<\/key>/.test(xml)}}));
}
