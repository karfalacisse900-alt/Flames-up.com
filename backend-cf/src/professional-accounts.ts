import { discussionLinks } from './tea-conversations.ts';

export const PROFESSIONAL_CATEGORIES = {
  creator: ['musician', 'performer', 'artist', 'photographer', 'filmmaker', 'freelancer', 'other_creative'],
  business: ['coffee_bakery', 'street_food', 'shop', 'small_brand', 'service', 'other_business'],
} as const;
export type ProfessionalRole = keyof typeof PROFESSIONAL_CATEGORIES;
export class ProfessionalError extends Error {
  code: string;
  status: number;
  constructor(code: string, status = 400, message = 'Check the details and try again.') { super(message); this.code = code; this.status = status; }
}
export const professionalRole = (value: unknown): ProfessionalRole => {
  if (value !== 'creator' && value !== 'business') throw new ProfessionalError('PROFESSIONAL_INVALID');
  return value;
};
const uuid = /^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i;
const identifier = (value: unknown) => {
  if (typeof value !== 'string' || !/^[\w-]{1,120}$/.test(value)) throw new ProfessionalError('PROFESSIONAL_INVALID');
  return value;
};
function text(value: unknown, max: number, required = false) {
  if (typeof value !== 'string' || [...value].length > max || /[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(value) || (required && !value.trim())) throw new ProfessionalError('PROFESSIONAL_INVALID');
  return value.trim();
}
function only(value: any, keys: string[]) {
  if (!value || typeof value !== 'object' || Array.isArray(value) || Object.keys(value).some(k => !keys.includes(k))) throw new ProfessionalError('PROFESSIONAL_INVALID');
}
export function professionalPublicData(role: ProfessionalRole, value: any, complete: boolean) {
  // Existing native JSONEncoder uses snake_case; web uses the canonical camelCase DTO.
  if (value && typeof value === 'object') {
    value = { ...value };
    for (const [native, web] of [['display_name','displayName'],['portfolio_post_ids','portfolioPostIds']]) {
      if (native in value) { if (web in value) throw new ProfessionalError('PROFESSIONAL_INVALID'); value[web]=value[native]; delete value[native]; }
    }
  }
  only(value, ['displayName', 'category', 'description', 'links', 'pickup', 'area', 'portfolioPostIds']);
  const displayName = text(value.displayName, 80, complete), description = text(value.description, 500, complete);
  const category = text(value.category, 40, complete);
  if (category && !(PROFESSIONAL_CATEGORIES[role] as readonly string[]).includes(category)) throw new ProfessionalError('PROFESSIONAL_INVALID');
  const links = discussionLinks(value.links);
  if (typeof value.pickup !== 'boolean' || (role === 'creator' && value.pickup)) throw new ProfessionalError('PROFESSIONAL_INVALID');
  const area = text(value.area, 120, role === 'business' && complete);
  const portfolioPostIds = value.portfolioPostIds ?? [];
  if (!Array.isArray(portfolioPostIds) || portfolioPostIds.length > 9 || (role === 'business' && portfolioPostIds.length)) throw new ProfessionalError('PROFESSIONAL_INVALID');
  return { displayName, category, description, links, pickup: value.pickup, area, portfolioPostIds: [...new Set(portfolioPostIds.map(identifier))] };
}
export function professionalOperation(role: ProfessionalRole, action: string, value: any) {
  const review = ['request_changes', 'approve', 'decline', 'suspend', 'restore', 'remove'].includes(action);
  if (!review && !['save', 'submit', 'edit_public'].includes(action)) throw new ProfessionalError('PROFESSIONAL_INVALID');
  only(value, review ? ['id', 'version', 'reason', 'message', 'note'] : ['id', 'version', 'public', 'message']);
  if (!uuid.test(value.id ?? '') || !Number.isSafeInteger(value.version) || value.version < 0) throw new ProfessionalError('PROFESSIONAL_INVALID');
  return {
    id: value.id.toLowerCase(), version: value.version,
    ...(review ? { reason: text(value.reason, 800, true), message: text(value.message, 1500, action !== 'approve'), note: text(value.note ?? '', 2000) }
      : { public: professionalPublicData(role, value.public, action !== 'save'), message: text(value.message ?? '', 1500) }),
  };
}
export function studioPathAllowed(method: string, path: string) {
  // Delegated Studio credentials cannot call admin, payment creation, account security, or publishing endpoints.
  if (method === 'GET') return /^\/api\/(auth\/me|professional\/me|media\/[\w-]+\/status|business-owner\/shops|business-owner\/[\w-]+\/(products|orders|earnings)(?:\/[\w-]+)?|commerce\/earnings\/(pools(?:\/creator_support)?|support-readiness)|users\/[\w-]+\/(posts|showcase))$/.test(path);
  if (method === 'POST') return /^\/api\/(professional\/(creator|business)\/edit_public|professional\/studio-signout|media\/(upload-intent|complete)|business-owner\/shops|business-owner\/[\w-]+\/(products|pickup)|business-orders\/[\w-]+\/action)$/.test(path);
  return method === 'PUT' && /^\/api\/(users\/me\/showcase|posts\/[\w-]+\/(visibility|pin|event))$/.test(path);
}
export async function professionalHash(value: string) {
  return [...new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value)))].map(x => x.toString(16).padStart(2, '0')).join('');
}
function randomToken() { return [...crypto.getRandomValues(new Uint8Array(32))].map(x => x.toString(16).padStart(2, '0')).join(''); }
export function studioOrigin(env: any) {
  if (!env.CAPTRO_STUDIO_ORIGIN) return null;
  const url = new URL(env.CAPTRO_STUDIO_ORIGIN);
  const local = env.ENVIRONMENT !== 'production' && ['localhost', '127.0.0.1'].includes(url.hostname);
  if ((url.protocol !== 'https:' && !local) || url.username || url.password || url.pathname !== '/' || url.search || url.hash) throw new ProfessionalError('STUDIO_NOT_CONFIGURED', 503);
  return url.origin;
}
type Dependencies = {
  auth: any; actor(c: any): string; admin(c: any, write: boolean): Promise<void>;
  limit(c: any): Promise<Response | null | undefined>;
  rpc(c: any, name: string, body: any): Promise<any>;
  query(c: any, table: string, options: any): Promise<any[]>;
  eq(value: string): string; portfolio(c: any, ids: string[]): Promise<void>;
};
export function mountProfessionalAccounts(api: any, d: Dependencies) {
  const wrap = (fn: (c: any) => Promise<Response>) => async (c: any) => {
    c.header('Cache-Control', 'private, no-store');
    try { const limit = await d.limit(c); return limit ?? await fn(c); }
    catch (error) {
      const code = error instanceof ProfessionalError ? error.code : String((error as Error)?.message || '');
      const status = error instanceof ProfessionalError ? error.status : code.includes('FORBIDDEN') ? 403 : code.includes('CONFLICT') ? 409 : code.includes('SESSION_INVALID') ? 401 : 503;
      return c.json({ code: /^(PROFESSIONAL_|STUDIO_)[A-Z_]+$/.test(code) ? code : 'PROFESSIONAL_REQUEST_FAILED',
        detail: status === 403 ? 'This account cannot perform that action.' : status === 409 ? 'This application or role changed. Reload before trying again.' : status === 401 ? 'This Studio sign-in expired. Open Studio from Captro Settings again.' : error instanceof ProfessionalError ? error.message : 'Could not complete the request. Your account has not been changed.' }, status);
    }
  };
  const readBody = async (c: any) => {
    const raw = await c.req.text();
    if (new TextEncoder().encode(raw).length > 16_000) throw new ProfessionalError('PROFESSIONAL_INVALID', 413);
    try { return JSON.parse(raw); } catch { throw new ProfessionalError('PROFESSIONAL_INVALID'); }
  };
  const rows = (c: any, table: string, target: string) => d.query(c, table, { filters: { user_id: d.eq(target) }, limit: 2 });
  api.get('/professional/me', d.auth, wrap(async c => {
    const actor = d.actor(c);
    const [applications, roles] = await Promise.all([rows(c, 'app_professional_applications', actor), rows(c, 'app_professional_roles', actor)]);
    return c.json({ applications: applications.map(({ decided_by, ...safe }: any) => safe), roles, studioURL: roles.length ? studioOrigin(c.env) : null });
  }));
  api.post('/professional/:role/:action', d.auth, wrap(async c => {
    const role = professionalRole(c.req.param('role')), action = c.req.param('action');
    if (!['save', 'submit', 'edit_public'].includes(action)) throw new ProfessionalError('PROFESSIONAL_INVALID');
    const data = professionalOperation(role, action, await readBody(c));
    if ('public' in data) await d.portfolio(c, data.public!.portfolioPostIds);
    const { id, ...patch } = data;
    const result = await d.rpc(c, 'captro_professional_mutate', { p_actor: d.actor(c), p_target: d.actor(c), p_role: role, p_action: action, p_data: patch, p_id: id });
    if (result.error) throw new ProfessionalError(result.error, result.error.endsWith('FORBIDDEN') ? 403 : 409);
    return c.json(result);
  }));
  api.get('/admin/professional', d.auth, wrap(async c => {
    await d.admin(c, false);
    const status = c.req.query('status') || 'under_review', role = c.req.query('role'), offset = Number(c.req.query('offset') || '0');
    if (!['draft', 'under_review', 'needs_changes', 'approved', 'declined'].includes(status) || !Number.isSafeInteger(offset) || offset < 0 || offset > 100000) throw new ProfessionalError('PROFESSIONAL_INVALID');
    const items = await d.query(c, 'app_professional_applications', { filters: { status: d.eq(status), ...(role ? { role: d.eq(professionalRole(role)) } : {}) }, order: 'updated_at.asc,user_id.asc,role.asc', offset, limit: 26 });
    return c.json({ items: items.slice(0, 25), nextOffset: items.length > 25 ? offset + 25 : null });
  }));
  api.get('/admin/professional/:target/:role', d.auth, wrap(async c => {
    await d.admin(c, false);
    const target = identifier(c.req.param('target')), role = professionalRole(c.req.param('role'));
    const filters = { user_id: d.eq(target), role: d.eq(role) };
    const [applications, roles, history] = await Promise.all([
      d.query(c, 'app_professional_applications', { filters, limit: 1 }), d.query(c, 'app_professional_roles', { filters, limit: 1 }),
      d.query(c, 'app_professional_audit', { filters: { target_id: d.eq(target), role: d.eq(role) }, select: 'id,actor_id,action,reason,internal_note,result,created_at', order: 'created_at.desc,id.desc', limit: 50 }),
    ]);
    if (!applications.length) throw new ProfessionalError('PROFESSIONAL_NOT_FOUND', 404);
    return c.json({ application: applications[0], role: roles[0] ?? null, history });
  }));
  api.post('/admin/professional/:target/:role/:action', d.auth, wrap(async c => {
    await d.admin(c, true);
    const role = professionalRole(c.req.param('role')), action = c.req.param('action');
    if (!['request_changes', 'approve', 'decline', 'suspend', 'restore', 'remove'].includes(action)) throw new ProfessionalError('PROFESSIONAL_INVALID');
    const { id, ...data } = professionalOperation(role, action, await readBody(c));
    const result = await d.rpc(c, 'captro_professional_mutate', { p_actor: d.actor(c), p_target: identifier(c.req.param('target')), p_role: role, p_action: action, p_data: data, p_id: id });
    if (result.error) throw new ProfessionalError(result.error, result.error.endsWith('FORBIDDEN') ? 403 : 409);
    return c.json(result);
  }));
  api.post('/professional/studio-handoff', d.auth, wrap(async c => {
    if (c.get('studioSession')) throw new ProfessionalError('PROFESSIONAL_FORBIDDEN', 403);
    const origin = studioOrigin(c.env);
    if (!origin) throw new ProfessionalError('STUDIO_NOT_CONFIGURED', 503, 'Captro Studio has not been published yet. Your approved account is unchanged.');
    const token = randomToken();
    await d.rpc(c, 'captro_studio_session', { p_action: 'issue', p_hash: await professionalHash(token), p_user: d.actor(c) });
    return c.json({ url: `${origin}/#handoff=${token}`, expiresIn: 60 });
  }));
  api.post('/professional/studio-session', wrap(async c => {
    const origin = studioOrigin(c.env);
    if (!origin || c.req.header('Origin') !== origin) throw new ProfessionalError('PROFESSIONAL_FORBIDDEN', 403);
    const body = await readBody(c); only(body, ['handoff']);
    if (!/^[a-f0-9]{64}$/.test(body.handoff ?? '')) throw new ProfessionalError('STUDIO_SESSION_INVALID', 401);
    const token = 'studio_' + randomToken();
    const result = await d.rpc(c, 'captro_studio_session', { p_action: 'exchange', p_hash: await professionalHash(body.handoff), p_session_hash: await professionalHash(token) });
    return c.json({ access_token: token, expires_in: result.expires_in });
  }));
  api.post('/professional/studio-signout', d.auth, wrap(async c => {
    const hash = c.get('studioSession');
    if (hash) await d.rpc(c, 'captro_studio_session', { p_action: 'revoke', p_hash: hash });
    return c.json({ ok: true });
  }));
}
