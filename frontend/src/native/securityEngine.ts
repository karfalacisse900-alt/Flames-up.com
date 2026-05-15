export type UrlAssessment = {
  allowed: boolean;
  safeUrl: string;
  reason: string;
  riskScore: number;
};

type NativeSecurityEngine = {
  normalizeTextSignal?: (value: string) => string;
  fingerprintSignal?: (value: string) => string;
  assessUrl?: (value: string) => string | UrlAssessment;
};

declare global {
  // Installed by the native C++ JSI security engine when a development build includes it.
  // Expo Go and web use the safe TypeScript fallback below.
  var __FlamesSecurityEngine: NativeSecurityEngine | undefined;
}

const BLOCKED_CONTROL_OR_HTML = /[\u0000-\u001F\u007F<>"'`\\]/;
const SHORTENER_HOSTS = new Set([
  'bit.ly',
  'cutt.ly',
  'goo.gl',
  'is.gd',
  'lnkd.in',
  'ow.ly',
  'rebrand.ly',
  'shorturl.at',
  't.co',
  'tiny.cc',
  'tinyurl.com',
]);

function compactHost(hostname: string): string {
  return hostname.trim().toLowerCase().replace(/\.+$/, '');
}

function isPrivateOrLocalHost(hostname: string): boolean {
  const host = compactHost(hostname);
  if (!host || host === 'localhost' || host.endsWith('.local')) return true;
  if (/^(0|10|127)\./.test(host)) return true;
  if (/^169\.254\./.test(host)) return true;
  if (/^192\.168\./.test(host)) return true;
  const match172 = host.match(/^172\.(\d+)\./);
  if (match172) {
    const block = Number(match172[1]);
    if (block >= 16 && block <= 31) return true;
  }
  return false;
}

function hex32(value: number): string {
  return (value >>> 0).toString(16).padStart(8, '0');
}

function fallbackFingerprint(value: string): string {
  const normalized = fallbackNormalizeTextSignal(value);
  let a = 0x811c9dc5;
  let b = 0x45d9f3b;

  for (let i = 0; i < normalized.length; i += 1) {
    const code = normalized.charCodeAt(i);
    a = Math.imul(a ^ code, 0x01000193);
    b = Math.imul(b ^ (code + i), 0x27d4eb2d);
  }

  return `${hex32(a)}${hex32(b)}`;
}

function fallbackNormalizeTextSignal(value: string): string {
  return String(value || '')
    .normalize('NFKC')
    .toLowerCase()
    .replace(/https?:\/\/\S+/g, ' ')
    .replace(/[^a-z0-9@._ -]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 512);
}

function parseNativeAssessment(output: string | UrlAssessment | undefined): UrlAssessment | null {
  if (!output) return null;
  if (typeof output !== 'string') return output;
  try {
    const parsed = JSON.parse(output);
    if (parsed && typeof parsed === 'object') return parsed as UrlAssessment;
  } catch {}
  return null;
}

function fallbackAssessUrl(value: string): UrlAssessment {
  const raw = String(value || '').trim();
  if (!raw) return { allowed: false, safeUrl: '', reason: 'empty', riskScore: 0 };
  if (BLOCKED_CONTROL_OR_HTML.test(raw)) {
    return { allowed: false, safeUrl: '', reason: 'unsafe_characters', riskScore: 95 };
  }

  try {
    const withProtocol = /^https?:\/\//i.test(raw) ? raw : `https://${raw}`;
    const url = new URL(withProtocol);
    const protocol = url.protocol.toLowerCase();
    const hostname = compactHost(url.hostname);

    if (protocol !== 'http:' && protocol !== 'https:') {
      return { allowed: false, safeUrl: '', reason: 'blocked_protocol', riskScore: 100 };
    }
    if (!hostname || url.username || url.password) {
      return { allowed: false, safeUrl: '', reason: 'invalid_host', riskScore: 90 };
    }
    if (isPrivateOrLocalHost(hostname)) {
      return { allowed: false, safeUrl: '', reason: 'private_or_local_host', riskScore: 90 };
    }

    let riskScore = protocol === 'http:' ? 20 : 0;
    if (SHORTENER_HOSTS.has(hostname)) riskScore += 25;
    if (url.pathname.length > 180 || url.search.length > 240) riskScore += 10;

    return {
      allowed: true,
      safeUrl: url.toString(),
      reason: riskScore > 0 ? 'allowed_with_caution' : 'allowed',
      riskScore,
    };
  } catch {
    return { allowed: false, safeUrl: '', reason: 'malformed_url', riskScore: 90 };
  }
}

export function normalizeTextSignal(value: string): string {
  try {
    const nativeValue = global.__FlamesSecurityEngine?.normalizeTextSignal?.(value);
    if (typeof nativeValue === 'string') return nativeValue;
  } catch {}
  return fallbackNormalizeTextSignal(value);
}

export function fingerprintSignal(value: string): string {
  try {
    const nativeValue = global.__FlamesSecurityEngine?.fingerprintSignal?.(value);
    if (typeof nativeValue === 'string' && nativeValue.length >= 8) return nativeValue;
  } catch {}
  return fallbackFingerprint(value);
}

export function assessExternalUrl(value?: string | null): UrlAssessment {
  const raw = String(value || '');
  try {
    const nativeValue = parseNativeAssessment(global.__FlamesSecurityEngine?.assessUrl?.(raw));
    if (nativeValue) return nativeValue;
  } catch {}
  return fallbackAssessUrl(raw);
}
