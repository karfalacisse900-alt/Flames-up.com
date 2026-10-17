// Tokens remain in this page's memory only. No analytics, storage or token-bearing navigation.
export function recoveryContext(hash) {
  const params = new URLSearchParams(hash.replace(/^#/, ''));
  if (params.has('error') || params.has('error_code')) return { error: true, token: '' };
  const token = params.get('access_token') || '';
  if (params.get('type') !== 'recovery' || !token || token.length > 8192) return { error: true, token: '' };
  return { error: false, token };
}
export function passwordProblem(password, confirmation) {
  if (password.length < 12 || password.length > 128) return 'Use a password with 12–128 characters.';
  if (password !== confirmation) return 'The passwords do not match.';
  return '';
}
export function startRecoveryPage(window, document) {
  let { token } = recoveryContext(window.location.hash);
  // Drop both query and fragment before any network activity. Never display provider error text.
  const get = (id) => document.getElementById(id);
  const reset = get('reset-form'), request = get('request-form'), status = get('status');
  try {
    window.history.replaceState(null, '', window.location.pathname);
  } catch {
    token = '';
    status.textContent = 'This browser cannot start secure recovery. Open the newest email link directly in Chrome, Edge or Safari.';
    status.dataset.error = 'true';
    return;
  }
  let busy = false;
  function message(value, error = false) { status.textContent = value; status.dataset.error = String(error); }
  function clear() { token = ''; reset.reset(); reset.hidden = true; }
  function requestMode(text) { clear(); request.hidden = false; message(text, true); }
  async function post(action, body) {
    const controller = new AbortController();
    const timer = window.setTimeout(() => controller.abort(), 15000);
    try {
      const response = await window.fetch(`/auth/reset-password/api/${action}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        credentials: 'omit', cache: 'no-store', referrerPolicy: 'no-referrer',
        body: JSON.stringify(body), signal: controller.signal,
      });
      let data;
      try { data = await response.json(); } catch { throw new Error('unexpected'); }
      return { ok: response.ok && data?.ok === true, status: response.status };
    } finally { window.clearTimeout(timer); }
  }
  function setBusy(value) {
    busy = value;
    for (const button of document.querySelectorAll('button')) button.disabled = value;
  }
  if (token) { reset.hidden = false; message('Enter your new password below. Keep this page open until you finish.'); }
  else requestMode('This link is missing, expired or unsupported. Request a fresh email below.');
  reset.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (busy || !token) return;
    const password = get('password').value;
    const problem = passwordProblem(password, get('confirm-password').value);
    if (problem) { message(problem, true); return; }
    setBusy(true); message('Updating your password…');
    try {
      const result = await post('confirm', { access_token: token, password });
      if (result.ok) {
        clear(); request.hidden = true; get('success').hidden = false;
        message('Password updated.'); get('intro').hidden = true;
      } else if ([401,403].includes(result.status)) {
        requestMode('This reset link cannot be used. Request a fresh email or contact support if your account is restricted.');
      } else if (result.status === 429) message('Too many attempts. Wait a few minutes before trying again.', true);
      else if (result.status === 400) message('The password was not accepted. Check the requirements and try a different password.', true);
      else message('The update could not be confirmed. Try signing in with your new password before requesting another reset.', true);
    } catch {
      message('The update could not be confirmed because the connection failed. Try signing in with your new password before requesting another reset.', true);
    } finally { reset.reset(); setBusy(false); }
  });
  request.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (busy) return;
    setBusy(true); message('Requesting your reset email…');
    try {
      const result = await post('request', { email: get('email').value.trim() });
      if (result.ok) message('If that email belongs to a Captro account, a reset email has been requested. Check Inbox and Spam. Use only the newest link.');
      else if (result.status === 429) message('Too many requests. Wait a few minutes before trying again.', true);
      else message('The email request failed. Please try again later.', true);
    } catch { message('Could not reach account recovery. Check your connection and try again.', true); }
    finally { setBusy(false); }
  });
  get('cancel').addEventListener('click', () => { if (!busy) requestMode('Reset cancelled. No password change was requested.'); });
  window.addEventListener('pagehide', clear);
  window.addEventListener('pageshow', (event) => { if (event.persisted) requestMode('For your security, request a fresh link after leaving this page.'); });
  get('startup-help').hidden = true;
}
if (typeof window !== 'undefined' && typeof document !== 'undefined') startRecoveryPage(window, document);
