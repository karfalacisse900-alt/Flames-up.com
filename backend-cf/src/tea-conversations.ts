import { FeedCursorError, readFeedCursor, writeFeedCursor } from './feed-pagination.ts';

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export class DiscussionInputError extends Error {}

export function discussionLinks(value: unknown): string[] {
  if (!Array.isArray(value) || value.length > 3) throw new DiscussionInputError('Add up to three HTTPS links.');
  return [...new Set(value.map(raw => {
    if (typeof raw !== 'string' || raw.length > 2048 || /[\s\u0000-\u001f\u007f]/.test(raw)) throw new DiscussionInputError('Enter a valid HTTPS link.');
    let url: URL;
    try { url = new URL(raw); } catch { throw new DiscussionInputError('Enter a valid HTTPS link.'); }
    if (url.protocol !== 'https:' || url.username || url.password || url.port || !url.hostname.includes('.') ||
        url.hostname.endsWith('.') || url.hostname.endsWith('.local') || url.hostname.endsWith('.localhost') ||
        /^[\d.]+$/.test(url.hostname) || url.hostname.includes(':')) throw new DiscussionInputError('Enter a public HTTPS website link.');
    // Keep the actual destination (including signed query parameters). Never fetch
    // arbitrary URLs on the server or infer platform identity from a substring.
    return url.href;
  }))];
}

export function discussionInput(action: string, value: any) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new DiscussionInputError('Invalid post.');
  const allowed = action === 'create' ? ['request_id','title','body','links'] : action === 'edit'
    ? ['title','body','links','version'] : action === 'reply' ? ['request_id','body'] : ['following'];
  if (Object.keys(value).some(k => !allowed.includes(k))) throw new DiscussionInputError('Unsupported field.');
  const text = (key: string, max: number) => {
    if (typeof value[key] !== 'string' || !value[key].trim() || [...value[key]].length > max || /[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(value[key])) throw new DiscussionInputError('Check the ' + key + '.');
    return value[key].trim();
  };
  if (action === 'follow') {
    if (typeof value.following !== 'boolean') throw new DiscussionInputError('Invalid follow state.');
    return { following: value.following };
  }
  if (action === 'create' || action === 'reply') {
    if (typeof value.request_id !== 'string' || !uuid.test(value.request_id)) throw new DiscussionInputError('Invalid request identity.');
  }
  if (action === 'reply') return { requestID: value.request_id, body: text('body', 4000) };
  if (action === 'edit' && (!Number.isSafeInteger(value.version) || value.version < 1)) throw new DiscussionInputError('Refresh this post before editing.');
  return { title: text('title', 160), body: text('body', 8000), links: discussionLinks(value.links),
    ...(action === 'create' ? { requestID: value.request_id } : { version: value.version }) };
}

type Dependencies = {
  auth: any; optionalAuth: any;
  viewer: (c: any) => Promise<string>;
  limit: (c: any, write: boolean) => Promise<any>;
  restriction: (c: any, action: 'posting' | 'commenting') => Promise<any>;
  rpc: (c: any, name: string, body: Record<string, unknown>) => Promise<any>;
};

export function mountTeaConversations(api: any, deps: Dependencies) {
  async function handle(c: any, action: string) {
    c.header('Cache-Control', 'private, no-store');
    const write = ['create','edit','reply','follow'].includes(action);
    try {
      const limited = await deps.limit(c, write); if (limited) return limited;
      const viewer = await deps.viewer(c);
      if (write && !viewer) return c.json({ detail: 'Sign in to participate.', code: 'TEA_SIGN_IN' }, 401);
      const id = c.req.param('id');
      if (action !== 'list' && action !== 'create' && !uuid.test(id ?? '')) throw new DiscussionInputError('Invalid post.');
      if (write) {
        const denied = await deps.restriction(c, action === 'reply' ? 'commenting' : 'posting');
        if (denied) return denied;
        const data: any = discussionInput(action, await c.req.json().catch(() => null));
        return c.json(await deps.rpc(c, 'captro_tea_write', {
          p_actor: viewer, p_action: action, p_id: action === 'create' ? data.requestID : id, p_data: data,
        }));
      }
      if (action === 'detail') return c.json(await deps.rpc(c, 'captro_tea_read', { p_viewer: viewer, p_kind: action, p_id: id }));
      const secret = c.env.JWT_SECRET;
      const cursor = await readFeedCursor(secret, c.req.query('cursor'), { viewer, scope: 'tea-discussions-' + action, city: id ?? '' });
      const rows = await deps.rpc(c, 'captro_tea_read', { p_viewer: viewer, p_kind: action,
        p_id: id ?? null, p_before: cursor.boundary?.createdAt ?? null, p_boundary: cursor.boundary?.id ?? null, p_snapshot: cursor.snapshot });
      if (!Array.isArray(rows)) throw new Error('TEA_INVALID_RESPONSE');
      const items = rows.slice(0,20), last = items.at(-1);
      const nextCursor = rows.length > 20 && last ? await writeFeedCursor(secret, {
        ...cursor, boundary: { id: last.id, createdAt: last.createdAt, legacyCreatedAt: null },
      }) : null;
      return c.json({ items, nextCursor });
    } catch (error) {
      if (error instanceof DiscussionInputError || error instanceof FeedCursorError) return c.json({ detail: error instanceof DiscussionInputError ? error.message : 'Refresh to start again.', code: 'TEA_DISCUSSION_INVALID' },400);
      const message = error instanceof Error ? error.message : '';
      for (const [code,status,detail] of [
        ['TEA_DISCUSSION_FORBIDDEN',403,'You cannot change this post.'],
        ['TEA_DISCUSSION_UNAVAILABLE',404,'This post is no longer available.'],
        ['TEA_DISCUSSION_CONFLICT',409,'This post changed. Refresh before trying again.'],
      ] as const) if (message.includes(code)) return c.json({ code, detail },status);
      // Never log post text, link tokens, credentials or raw provider errors.
      console.warn(JSON.stringify({ event:'tea_discussion_failed', action, request_id:c.get('requestId') }));
      return c.json({ detail:'Could not load or save this discussion. Try again.', code:'TEA_DISCUSSION_FAILED' },503);
    }
  }
  api.get('/tea/conversations', deps.optionalAuth, (c: any) => handle(c,'list'));
  api.get('/tea/conversations/:id', deps.optionalAuth, (c: any) => handle(c,'detail'));
  api.get('/tea/conversations/:id/replies', deps.optionalAuth, (c: any) => handle(c,'replies'));
  api.post('/tea/conversations', deps.auth, (c: any) => handle(c,'create'));
  api.put('/tea/conversations/:id', deps.auth, (c: any) => handle(c,'edit'));
  api.post('/tea/conversations/:id/replies', deps.auth, (c: any) => handle(c,'reply'));
  api.put('/tea/conversations/:id/follow', deps.auth, (c: any) => handle(c,'follow'));
}
