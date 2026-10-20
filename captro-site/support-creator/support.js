export function parseUSD(text) {
  if (!/^\d{1,3}(?:\.\d{1,2})?$/.test(text.trim())) return null;
  const [whole, fraction = ''] = text.trim().split('.');
  const units = BigInt(whole) * 100n + BigInt(fraction.padEnd(2, '0'));
  return units >= 200n && units <= 20000n ? Number(units) : null;
}

const $ = id => document.getElementById(id);
const config = window.CAPTRO_SUPPORT_CONFIG || {};
const fragment = new URLSearchParams(location.hash.slice(1));
const supplied = fragment.get('handoff');
// Remove the narrowly scoped bearer before images, requests or navigations.
if (location.hash) history.replaceState(null, '', location.pathname + location.search);
window.addEventListener('hashchange', () => {
  if (/^#handoff=[a-f0-9]{64}(?:&|$)/.test(location.hash)) location.reload();
});
const storageKey = 'captro.support.handoff';
let token;
try {
  const cached = JSON.parse(sessionStorage.getItem(storageKey) || 'null');
  token = supplied || (cached?.until > Date.now() ? cached.token : null);
  if (supplied && /^[a-f0-9]{64}$/.test(supplied)) sessionStorage.setItem(storageKey, JSON.stringify({ token: supplied, until: Date.now() + 2 * 3600_000 }));
} catch { token = supplied; }
let amount = null, busy = false, purchaseId = null, checking = false;
const setStatus = text => { $('status').textContent = text; };
const setBusy = value => {
  busy = value; $('amounts').disabled = value || purchaseId !== null;
  $('checkout').disabled = value || amount === null; $('retry').disabled = value;
};
function select(value) {
  amount = value;
  document.querySelectorAll('[data-amount]').forEach(b => b.setAttribute('aria-pressed', String(Number(b.dataset.amount) === value)));
  $('checkout').disabled = busy || amount === null;
}
async function request(path, data = {}) {
  if (!token || !/^[a-f0-9]{64}$/.test(token)) throw new Error('link');
  const url = new URL(config.apiBaseURL);
  if (url.protocol !== 'https:' || !['flames-up-api.karfalacisse900.workers.dev','api.flames-up.com'].includes(url.hostname)) throw new Error('config');
  const response = await fetch(url.href.replace(/\/$/, '') + '/creator-support/web/' + path, {
    method: 'POST', credentials: 'omit', referrerPolicy: 'no-referrer', cache: 'no-store',
    headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ token, ...data }), signal: AbortSignal.timeout(15000),
  });
  if (!response.ok) throw new Error(response.status === 401 ? 'link' : 'request');
  return response.json();
}
function showReturn(id) {
  if (typeof id !== 'string' || !/^[a-f0-9-]{36}$/i.test(id)) return;
  if (config.universalLinksVerified === true) {
$('app-return').href = 'https://captro-site.pages.dev/support-creator/return?purchase_id=' + encodeURIComponent(id);
    $('app-return').hidden = false;
  } else $('manual-return').hidden = false;
}
async function checkStatus() {
  if (checking) return;
  checking = true; $('check-status').disabled = true;
  try {
    const result = await request('status');
    // A different creator handoff can replace this tab's short-lived context.
    // Never show its receipt as the outcome of an older checkout return.
    if (location.pathname === '/support-creator/return') {
      const expected = new URLSearchParams(location.search).getAll('purchase_id');
      if (expected.length !== 1 || expected[0] !== result.id) {
        setStatus('This browser no longer has the matching checkout context. Return to Captro to check this payment.');
        $('support-form').hidden = true; $('app-return').hidden = true; $('manual-return').hidden = false;
        return 'context_mismatch';
      }
    }
    purchaseId = result.id || purchaseId;
    const money = Number.isSafeInteger(result.amount) ? new Intl.NumberFormat(undefined, { style: 'currency', currency: 'USD' }).format(result.amount / 100) : '';
    const messages = { confirmed: `Support confirmed${money ? ': ' + money : ''}. Thank you.`, refunded: 'This support payment was refunded.',
      partially_refunded: 'This support payment was partially refunded.', cancelled: 'Checkout ended without a confirmed payment.',
      expired: 'Checkout expired without a confirmed payment.', not_started: 'No payment has been started.',
      disputed: 'This payment is disputed. Its outcome is being reviewed.', under_review: 'Payment received and under review. Please do not pay again.' };
    const cancelled = new URLSearchParams(location.search).get('cancelled') === '1';
    setStatus(messages[result.status] || (cancelled ? 'Checkout closed. No payment is confirmed yet.' : 'Confirming payment. Please check again shortly.'));
    if (['confirmed','refunded','partially_refunded','cancelled','expired','disputed','under_review'].includes(result.status)) {
      $('support-form').hidden = true;
    }
    showReturn(result.id);
    return result.status;
  } catch (error) {
    setStatus(error.message === 'link' ? 'This secure link has expired. Return to Captro to check your payment.' : 'Could not verify payment. Check again before starting another payment.');
  } finally { checking = false; $('check-status').disabled = false; $('check-status').hidden = false; }
}
async function load() {
  $('retry').hidden = true; setBusy(true);
  // Turning off new checkouts must not hide the outcome of an existing payment.
  // The status API still requires the scoped bearer and revalidates its owner.
  if (location.pathname === '/support-creator/return' && config.apiBaseURL) {
    try { await checkStatus(); } finally { setBusy(false); }
    return;
  }
  if (!config.enabled || !config.apiBaseURL) {
    setStatus('Creator support is not available yet. No payment has been started.'); setBusy(false); return;
  }
  try {
    const data = await request('session');
    $('title').textContent = 'Support ' + data.creator.display_name;
    $('username').textContent = '@' + data.creator.username;
    $('avatar-fallback').textContent = Array.from(data.creator.display_name || '?')[0];
    if (data.creator.avatar_url) {
      const avatar = new URL(data.creator.avatar_url);
      if (avatar.protocol === 'https:') {
        $('avatar').referrerPolicy = 'no-referrer'; $('avatar').src = avatar.href;
        $('avatar').onload = () => { $('avatar').hidden = false; $('avatar-fallback').hidden = true; };
        $('avatar').onerror = () => { $('avatar').hidden = true; $('avatar-fallback').hidden = false; };
      }
    }
    purchaseId = data.purchase?.id || null;
    let currentStatus = data.purchase?.status;
    if (purchaseId) { amount = data.purchase.amount; currentStatus = await checkStatus(); }
    else {
      $('support-form').hidden = false; setStatus('');
      const suggested = Number(fragment.get('amount'));
      if (Number.isSafeInteger(suggested) && suggested >= 200 && suggested <= 20000) {
        select(suggested);
        if (![200,500,1000,2000].includes(suggested)) $('custom-amount').value = `${Math.floor(suggested / 100)}.${String(suggested % 100).padStart(2, '0')}`;
      }
    }
    if (purchaseId && currentStatus === 'confirming') { $('support-form').hidden = false; select(data.purchase.amount); }
  } catch (error) {
    setStatus(error.message === 'link' ? 'This secure link has expired. Open Support again in Captro.' : 'Could not load secure support. Please retry.');
    $('retry').hidden = false;
  } finally { setBusy(false); }
}
document.querySelectorAll('[data-amount]').forEach(b => b.addEventListener('click', () => { $('custom-amount').value = ''; select(Number(b.dataset.amount)); }));
$('custom-amount').addEventListener('input', e => select(parseUSD(e.target.value)));
$('retry').addEventListener('click', load);
$('check-status').addEventListener('click', checkStatus);
$('support-form').addEventListener('submit', async e => {
  e.preventDefault(); if (busy || amount === null) return; setBusy(true); setStatus('Preparing secure checkout…');
  try {
    const result = await request('checkout', { amount, currency: 'USD' }); purchaseId = result.purchase?.id || purchaseId;
    if (!result.checkout_url) { await checkStatus(); return; }
    const url = new URL(result.checkout_url);
    if (url.protocol !== 'https:' || url.hostname !== 'checkout.stripe.com' || url.username || url.password) throw new Error('url');
    location.assign(url.href);
  } catch {
    setStatus('Could not confirm checkout creation. Check status or retry; the same payment request will be reused.');
    $('check-status').hidden = false;
  } finally { setBusy(false); }
});
load();
