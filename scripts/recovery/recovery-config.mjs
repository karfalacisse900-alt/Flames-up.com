import { writeFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
export const target = 'https://captro-site.pages.dev/auth/reset-password/';
const template = '<h2>Reset your Captro password</h2><p>Follow the secure link below to choose a new password.</p><p><a href="{{ .ConfirmationURL }}">Reset password</a></p><p>If you did not request this email, you can ignore it. Never share this link or a verification code.</p>';
export function repairPlan(config) {
  const allowed = String(config.uri_allow_list || '').split(',').map(s=>s.trim()).filter(Boolean);
  if (!allowed.includes(target)) allowed.push(target);
  const existing = config.mailer_templates_recovery_content || '';
  return {
    uri_allow_list: allowed.join(','),
    // Preserve a correct template. Blank uses the provider's default ConfirmationURL.
    mailer_templates_recovery_content: !existing || (existing.includes('.ConfirmationURL') && !existing.includes('.SiteURL')) ? existing : template,
  };
}
export async function configureRecovery({ token, project, apply = false, fetcher = fetch, saveBackup = async () => {}, wait = ms => new Promise(resolve => setTimeout(resolve, ms)) }) {
  if (!token || project !== 'cclgvxukwccvtgrbcwie') throw Error('Expected Captro project and management authentication are required.');
  const url = `https://api.supabase.com/v1/projects/${project}/config/auth`;
  async function configRequest(method = 'GET', body) {
    const response = await fetcher(url, { method, headers:{ Authorization:`Bearer ${token}`, 'Content-Type':'application/json' }, body:body ? JSON.stringify(body) : undefined, redirect:'error', signal:AbortSignal.timeout(20000) });
    if (!response.ok) throw Error(`Auth configuration request failed (HTTP ${response.status}).`);
    return response.json();
  }
  const before = await configRequest();
  const planned = repairPlan(before);
  const changed = Object.keys(planned).filter(key => planned[key] !== (before[key] || ''));
  const summary = { resetRedirectExplicitlyAllowed: String(before.uri_allow_list || '').split(',').map(s=>s.trim()).includes(target), recoveryTemplateUsesBrokenSiteURL: (before.mailer_templates_recovery_content || '').includes('.SiteURL'), changedFields:changed, applied:false };
  if (apply && changed.length) {
    // Only these two non-credential fields; never persist the full Auth configuration.
    await saveBackup(Object.fromEntries(Object.keys(planned).map(k=>[k,before[k] ?? ''])));
    await configRequest('PATCH', Object.fromEntries(changed.map(k=>[k,planned[k]])));
    const verified = await configRequest();
    for (const key of changed) if (verified[key] !== planned[key]) throw Error('Recovery configuration verification failed.');
    summary.applied = true;
  }
  // An invalid synthetic token tests the redirect without consuming a real email link.
  const probe = new URL(`https://${project}.supabase.co/auth/v1/verify`);
  probe.searchParams.set('type','recovery'); probe.searchParams.set('token','captro-invalid-redirect-probe'); probe.searchParams.set('redirect_to',target);
  // Auth configuration may take a few seconds to reach serving instances. Re-read,
  // never repeat the configuration mutation or consume a real recovery credential.
  summary.redirectProbeMatches = false;
  for (let attempt = 0; attempt < (apply ? 5 : 1); attempt++) {
    if (attempt) await wait(1000 * 2 ** (attempt - 1));
    const response = await fetcher(probe, { redirect:'manual', signal:AbortSignal.timeout(15000) });
    let destination = '';
    try { const parsed = new URL(response.headers.get('location')); destination = parsed.origin + parsed.pathname; } catch {}
    summary.redirectProbeMatches = destination === target;
    summary.redirectProbeAttempts = attempt + 1;
    if (summary.redirectProbeMatches) break;
  }
  if (apply && !summary.redirectProbeMatches) throw Error('Provider redirect did not match the repaired recovery page.');
  return summary;
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const summary = await configureRecovery({ token:process.env.SUPABASE_ACCESS_TOKEN, project:process.env.SUPABASE_PROJECT_REF, apply:process.argv.includes('--apply'), saveBackup: data=>writeFile('recovery-redirect-backup.json',JSON.stringify(data,null,2),{mode:0o600}) });
    console.log(JSON.stringify(summary));
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
