import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import ts from 'typescript';
import * as writing from '../src/creation-intent.ts';
import { orderPostMediaAssets } from '../src/post-media.ts';
import { rankVisibleFeedWindow } from '../src/feed-relevance.ts';
import { validatedStampVariant } from '../src/stamp-style.ts';
import { creatorEventDetails, isEventPostType, validateCreatorEvent } from '../src/post-objects.ts';
import * as pagination from '../src/feed-pagination.ts';

// Run production handlers/mappers against isolated records. These are contract
// tests, not a claim that a real upload, production database or iPhone was tested.
const source = readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8');
const ast = ts.createSourceFile('index.ts', source, ts.ScriptTarget.Latest, true);
function fn(name) {
  const node = ast.statements.find(n => ts.isFunctionDeclaration(n) && n.name?.text === name);
  assert.ok(node, `active function ${name}`);
  return node.getText(ast);
}
function handler(method, path, name) {
  for (const statement of ast.statements) {
    if (!ts.isExpressionStatement(statement) || !ts.isCallExpression(statement.expression)) continue;
    const call = statement.expression;
    if (call.expression.getText(ast) === `api.${method}` && call.arguments[0]?.text === path)
      return `const ${name} = ${call.arguments.at(-1).getText(ast)};`;
  }
  throw Error(`Missing route ${method} ${path}`);
}
const clean = value => String(value ?? '').trim();
const array = value => Array.isArray(value) ? value : [];
const object = value => value && typeof value === 'object' && !Array.isArray(value) ? value : {};
const postId = number => `00000000-0000-4000-8000-${String(number).padStart(12, '0')}`;
const author = { id: 'author', supabase_user_id: postId(1), city: 'New York', username: 'test-author', profile: {} };
const viewer = { id: 'reader', supabase_user_id: postId(2), city: 'New York', username: 'test-reader', profile: {} };
const video = 'https://videodelivery.net/testvideo123/manifest/video.m3u8';
const photo = 'https://imagedelivery.net/testaccount/testphoto/public';

function splitConditions(value) {
  let depth = 0;
  let start = 0;
  const parts = [];
  for (let i = 0; i < value.length; i++) {
    if (value[i] === '(') depth++;
    if (value[i] === ')') depth--;
    if (value[i] === ',' && depth === 0) { parts.push(value.slice(start, i)); start = i + 1; }
  }
  return [...parts, value.slice(start)];
}
function matchesExpression(row, expression) {
  for (const operator of ['or', 'and']) if (expression.startsWith(`${operator}(`)) {
    const matches = splitConditions(expression.slice(operator.length + 1, -1)).map(part => matchesExpression(row, part));
    return operator === 'or' ? matches.some(Boolean) : matches.every(Boolean);
  }
  const [, field, operator, expected] = expression.match(/^([^.]+)\.([^.]+)\.(.*)$/) || [];
  const value = field?.startsWith('metadata->>') ? row.metadata?.[field.slice(11)] : row[field];
  if (operator === 'is') return expected === 'null' ? value == null : value != null;
  if (operator === 'eq') return value === expected;
  if (operator === 'lt') return value != null && value < expected;
  if (operator === 'lte') return value != null && value <= expected;
  if (operator === 'ilike') return clean(value).toLowerCase() === expected.toLowerCase();
  if (operator === 'in') return expected.slice(1, -1).split(',').includes(value);
  throw Error(`Unhandled fixture expression ${expression}`);
}

function harness({ initial = [], following = [], blocked = [], insertFailure = false } = {}) {
  const posts = initial.map(row => ({ ...row }));
  const assets = new Map();
  const queries = [];
  const trace = [];
  let sequence = 10;
  const functions = [
    'normalizeVisibility', 'supabaseUserStatus', 'supabaseAppPostVisibleToViewer',
    'supabaseAppPostMedia', 'supabaseAppPostToLegacy', 'supabasePrimaryPostCreatePayload',
    'supabaseExistingPostByClientRequest', 'approvedMediaAssetsForPost',
    'supabaseReadVisiblePosts', 'supabaseReadFeedPageV2', 'isVideoMediaUrl', 'postPayload', 'feedPostPayload',
  ].map(fn).join('\n');
  const code = functions + '\n' + handler('post', '/posts', 'publish') + '\n'
    + handler('get', '/posts/feed', 'feed') + '\n' + handler('get', '/posts/:postId', 'details')
    + '\n' + handler('get', '/posts/world-board', 'world');
  const normalizeMedia = (images, image) => [...new Set([...array(images), image].map(clean).filter(Boolean))];
  const bindings = {
    ...writing, ...pagination, orderPostMediaAssets, rankVisibleFeedWindow,
    validatedStampVariant, creatorEventDetails, isEventPostType, validateCreatorEvent,
    URL, Headers, Response, console: { warn() {}, error() {} },
    cleanText: clean, cleanMultilineText: clean, publicId: clean,
    parseJsonArray: array, parseJsonObject: object, safeMediaReference: clean,
    safeExternalUrl: clean, sanitizeMediaReferences: normalizeMedia,
    sanitizeMediaTypes: (types, count) => Array.from({ length: count }, (_, i) => types?.[i] || 'image'),
    sanitizeMediaDimensions: array, feedMediaDimensions: (_, __, dimensions) => dimensions,
    sanitizePostEditorOverlays: array, sanitizeTaggedUsers: array,
    validateMediaWritingOverlays: () => [], sanitizeAutoCategoryTags: array,
    normalizeCategoryScoresPayload: object, normalizeCategorySource: clean,
    normalizeCategoryStatus: clean, normalizeDiscoverCategory: value => clean(value) || 'other',
    normalizeSecondaryCategoriesPayload: array,
    DEFAULT_DISCOVER_CATEGORY: 'other', normalizePostResponseConfig: () => null,
    DEFAULT_FEED_MEDIA_RATIO: { feed_width: 1080, feed_height: 1350, feed_aspect_ratio: 0.8 },
    FEED_MEDIA_WIDTH: 1080, FEED_MEDIA_HEIGHT: 1350, FEED_MEDIA_ASPECT_RATIO: 0.8,
    publicUsernameFor: value => value.username,
    feedDeliveryUrl: url => url, posterDeliveryUrl: url => url,
    cloudflareImageProxyFallbackUrl: () => '',
    normalizeAppleMapKitProvider: clean, looksLikePrivatePlace: () => false,
    normalizeDisplayLocationSource: value => clean(value) || 'none',
    normalizeDisplayLocationVisibility: value => clean(value) || 'public',
    normalizeDisplayLocationLabel: (city, region, country, fallback) => fallback || [city, region, country].filter(Boolean).join(', '),
    autoCategoryFromBody: () => ({ primary_category: 'other' }),
    mediaBackupIdsFromReferences: () => [], parseMediaAssetIds: body => array(body.media_asset_ids),
    normalizeMediaModerationStatus: clean, normalizeMediaAssetType: clean,
    supabaseMediaAssetToLegacy: value => value, mediaAssetPublicUrl: (_, value) => value.public_url,
    clampNumber: (value, min, max, fallback) => Math.max(min, Math.min(max, Number(value ?? fallback))),
    clampFloat: (value, min, max, fallback) => Math.max(min, Math.min(max, Number(value ?? fallback))),
    toPgTime: value => value, now: () => '2026-10-14T12:00:00.000Z',
    uuid: () => postId(sequence++), isUuidText: value => /^[0-9a-f-]{36}$/.test(String(value)) ? value : null,
    postgrestEqFilter: value => `eq.${value}`, postgrestInFilter: values => `in.(${values.join(',')})`,
    postgrestSearchTerm: clean, SUPABASE_APP_POST_SELECT: '*',
    getUserId: c => c.viewerId, getClientRequestId: (_, body) => body.client_request_id || '',
    getOptionalUserId: async c => c.viewerId, clientIp: () => '127.0.0.1',
    requirePhoneVerified: async () => null, rejectLargeRequest: () => null,
    requireSupabasePrimaryDatabase: () => null, supabasePrimaryConfigured: () => true,
    enforceRateLimit: async () => null, enforceUserRestriction: async () => null,
    getSupabaseAppUserRowByAnyId: async (_, id) => id === author.id ? author : viewer,
    supabaseAppUserToLegacyUser: value => value,
    screenCaptroText: async () => 'approved', validateCommerceInput: () => null,
    getErrorCode: error => error.message, runBackgroundTask: () => {},
    writeSupabasePrimaryPostPlace: async () => {}, recordAbuseSignals: async () => {},
    supabaseIncrementAppUserPostCount: async () => {},
    supabasePostCommentCount: async () => 0, supabasePostCommentCounts: async () => new Map(),
    supabaseRelatedInteractionUserIds: async (_, id) => [id, id === author.id ? author.supabase_user_id : viewer.supabase_user_id],
    supabaseBlockedUserIds: async () => new Set(blocked),
    supabaseUsersByAnyIds: async () => new Map([[author.id, author], [author.supabase_user_id, author], [viewer.id, viewer]]),
    supabaseFollowingUserIds: async () => new Set(following),
    supabaseAppPostMatchesCategory: () => true, supabaseHydratePostResponses: async () => {},
    attachPublicPostObjects: async () => {}, attachPublicCommerce: async () => {},
    overlaySupabaseViewerEngagement: async (_, rows) => rows,
    supabaseAdminPatchRows: async () => [],
    supabaseAdminInsertRows: async (_, table, rows) => {
      assert.equal(table, 'app_posts');
      if (insertFailure) throw Error('TEST_DATABASE_UNAVAILABLE');
      posts.unshift(...rows);
      trace.push({ stage: 'database_insert', id: rows[0].id, status: rows[0].status, mediaCount: rows[0].media.length });
      return rows;
    },
    supabaseAdminQueryRows: async (_, table, query) => {
      queries.push({ table, ...query });
      if (table === 'app_media_assets') return [...assets.values()].filter(row => query.filters.id.includes(row.id));
      if (table === 'app_follows') return following.map(id => ({ app_following_id: id, status: 'active' }));
      assert.equal(table, 'app_posts');
      const filters = query.filters || {};
      let rows = posts.filter(row => Object.entries(filters).every(([key, condition]) => {
        if (query.order === pagination.feedKeysetOrder)
          return matchesExpression(row, key === 'or' ? `or${condition}` : `${key}.${condition}`);
        if (key === 'or') return condition.includes(row.id) || condition.includes(row.legacy_post_id);
        const value = key.startsWith('metadata->>') ? row.metadata?.[key.slice(11)] : row[key];
        if (condition.startsWith('eq.')) return value === condition.slice(3);
        if (condition.startsWith('ilike.')) return clean(value).toLowerCase() === condition.slice(6).toLowerCase();
        if (condition.startsWith('in.(')) return condition.slice(4, -1).split(',').includes(value);
        throw Error(`Unhandled test filter ${key}`);
      }));
      if (query.order === pagination.feedKeysetOrder) rows.sort((a, b) => {
        for (const field of ['legacy_created_at', 'created_at', 'id']) {
          if (a[field] == null && b[field] != null) return 1;
          if (a[field] != null && b[field] == null) return -1;
          if (a[field] !== b[field]) return a[field] < b[field] ? 1 : -1;
        }
        return 0;
      });
      return rows.slice(query.offset || 0, (query.offset || 0) + query.limit);
    },
  };
  const js = ts.transpileModule(code, { compilerOptions: { target: ts.ScriptTarget.ES2022 } }).outputText;
  const routes = vm.runInNewContext(`${js}\n({publish, feed, details, world, read: supabaseReadVisiblePosts})`, bindings);
  function context({ viewerId = author.id, body = {}, scope = 'for_you', skip = 0, id = '', limit = 20, pagination: mode, cursor } = {}) {
    return { viewerId, env: { JWT_SECRET: 'isolated-feed-fixture-not-a-live-key' }, set() {}, get() {},
      req: { json: async () => body, query: key => ({ scope, skip: String(skip), limit: String(limit), pagination: mode, cursor })[key], param: () => id },
      json: (value, status = 200) => ({ value, status, headers: new Headers() }) };
  }
  function media(url = photo, state = 'approved', type = 'image') {
    const id = `media-${assets.size + 1}`;
    assets.set(id, { id, user_id: author.id, public_url: url, moderation_status: state, upload_status: 'uploaded', media_type: type });
    return { images: [url], media_types: [type], media_asset_ids: [id], media_dimensions: [{ media_id: id, width: 1080, height: 1350 }] };
  }
  return { ...routes, context, media, posts, queries, trace };
}

test('confirmed photo/video/carousel and stamp publication retains one canonical ID through insert, Home and Details', async () => {
  for (const post_type of ['general', 'club', 'event', 'meetup', 'deal', 'group', 'offer', 'local_offer', 'ticket', 'booking', 'party', 'place', 'guide', 'travel']) {
    for (const kind of ['photo', 'video', 'carousel']) {
      const h = harness();
      let upload = h.media(kind === 'video' ? video : photo, 'approved', kind === 'video' ? 'video' : 'image');
      if (kind === 'carousel') {
        const second = h.media(video, 'approved', 'video');
        upload = Object.fromEntries(Object.keys(upload).map(key => [key, [...upload[key], ...second[key]]]));
      }
      const body = { ...upload, post_type, title: 'Trace fixture', content: 'Preserved caption', client_request_id: 'trace-request' };
      const published = await h.publish(h.context({ body }));
      assert.equal(published.status, 200);
      const id = published.value.id;
      assert.equal(h.posts.length, 1);
      assert.equal(h.posts[0].id, id);
      assert.equal(h.posts[0].status, 'active');
      assert.equal(h.posts[0].editor_data.moderation.status, 'approved');
      assert.equal(h.posts[0].metadata.client_request_id, 'trace-request');
      assert.equal(published.value.images.length, upload.images.length);
      for (const viewerId of [author.id, viewer.id]) {
        const home = await h.feed(h.context({ viewerId }));
        const detail = await h.details(h.context({ viewerId, id }));
        assert.equal(home.status, 200);
        assert.equal(home.value[0]?.id, id);
        assert.equal(detail.value.id, id);
        assert.equal(home.value[0].images.length, upload.images.length);
      }
      const replay = await h.publish(h.context({ body }));
      assert.equal(replay.value.id, id);
      assert.equal(replay.value.idempotent_replay, true);
      assert.equal(h.posts.length, 1);
    }
  }
});

test('pending, rejected and review-required media cannot produce a successful post or Home entry', async () => {
  for (const state of ['pending', 'rejected', 'review_required']) {
    const h = harness();
    const result = await h.publish(h.context({ body: { ...h.media(photo, state), content: 'Caption' } }));
    assert.equal(result.status, 409);
    assert.equal(result.value.code, `MEDIA_${state.toUpperCase()}`);
    assert.equal(h.posts.length, 0);
  }
});

test('failed database insert reports failure and does not manufacture a successful Home post', async () => {
  const h = harness({ insertFailure: true });
  const result = await h.publish(h.context({ body: h.media() }));
  assert.equal(result.status, 503);
  assert.equal(result.value.code, 'SUPABASE_PRIMARY_WRITE_FAILED');
  assert.equal(h.posts.length, 0);
});

test('private posts remain author-only; Following and Around do not imply eligibility from successful publication', async () => {
  const h = harness();
  const published = await h.publish(h.context({ body: { ...h.media(), visibility: 'private' } }));
  assert.equal(published.status, 200);
  assert.equal((await h.feed(h.context())).value.length, 1);
  assert.equal((await h.feed(h.context({ viewerId: viewer.id }))).value.length, 0);
  assert.equal((await h.details(h.context({ viewerId: viewer.id, id: published.value.id }))).status, 404);
  assert.equal((await h.feed(h.context({ scope: 'following' }))).value.length, 0);
  assert.equal((await h.feed(h.context({ scope: 'around' }))).value.length, 0);
  assert.equal((await h.details(h.context({ id: published.value.id }))).status, 200);
});

test('public display city and actual following relationships admit eligible published posts', async () => {
  const h = harness({ following: [author.id] });
  const result = await h.publish(h.context({ body: {
    ...h.media(), display_city: 'New York', display_location_visibility: 'public',
  } }));
  for (const scope of ['around', 'following', 'for_you'])
    assert.equal((await h.feed(h.context({ viewerId: viewer.id, scope }))).value[0]?.id, result.value.id);
});

test('media without dimensions remains eligible and this cursor release preserves legacy publication compatibility', async () => {
  const h = harness();
  const upload = h.media();
  delete upload.media_dimensions;
  const result = await h.publish(h.context({ body: upload }));
  assert.equal(result.status, 200);
  assert.equal((await h.feed(h.context())).value[0].images.length, 1);
  const textOnly = await h.publish(h.context({ body: { content: 'Legacy draft text' } }));
  // The approved cursor release is based on the currently deployed Worker.
  // Retiring older writers is a separate change and must not be bundled here.
  assert.equal(textOnly.status, 200);
  assert.equal(textOnly.value.images.length, 0);
  assert.equal(textOnly.value.content, 'Legacy draft text');
});

test('blocked accounts and non-active records remain absent from the authorized Home page', async () => {
  const h = harness({ blocked: [author.id] });
  await h.publish(h.context({ body: h.media() }));
  assert.equal((await h.feed(h.context({ viewerId: viewer.id }))).value.length, 0);
  h.posts[0].status = 'under_review';
  assert.equal((await h.feed(h.context())).value.length, 0);
});

// Diagnostic reproduction of a pre-existing API contract flaw. Keep explicit
// until a separately reviewed pagination API can replace visible-count offsets.
test('documents raw-offset pagination overlap after access filtering (not a fixed regression)', async () => {
  const initial = Array.from({ length: 100 }, (_, i) => ({
    id: postId(100 + i), legacy_post_id: postId(100 + i), app_user_id: author.id,
    user_id: author.supabase_user_id, status: 'active', visibility: i % 2 ? 'public' : 'private',
    post_type: 'general', media: [{ url: photo, type: 'image' }], metadata: {},
  }));
  const h = harness({ initial });
  const first = (await h.feed(h.context({ viewerId: viewer.id }))).value;
  const second = (await h.feed(h.context({ viewerId: viewer.id, skip: first.length }))).value;
  const overlap = second.filter(post => first.some(previous => previous.id === post.id));
  assert.equal(first.length, 20);
  assert.equal(second.length, 20);
  assert.equal(overlap.length, 10, 'Existing returned-count cursor repeats 10 already accepted IDs');
});

test('documents premature end when an authorization-filtered raw window contains no visible posts', async () => {
  const initial = Array.from({ length: 41 }, (_, i) => ({
    id: postId(200 + i), legacy_post_id: postId(200 + i), app_user_id: author.id,
    user_id: author.supabase_user_id, status: 'active', visibility: i === 40 ? 'public' : 'private',
    post_type: 'general', media: [{ url: photo, type: 'image' }], metadata: {},
  }));
  const h = harness({ initial });
  assert.equal((await h.feed(h.context({ viewerId: viewer.id }))).value.length, 0);
  assert.equal((await h.details(h.context({ viewerId: viewer.id, id: postId(240) }))).status, 200);
});

function feedRows(count, visibility) {
  return Array.from({ length: count }, (_, i) => ({
    id: postId(10_000 - i), legacy_post_id: postId(10_000 - i), app_user_id: author.id,
    user_id: author.supabase_user_id, status: 'active', visibility: visibility(i),
    post_type: 'general', media: [{ url: photo, type: 'image' }], metadata: {},
    created_at: '2020-01-01T00:00:00.000Z', legacy_created_at: '2020-01-01T00:00:00.000Z',
  }));
}

test('real publication writes the ordering timestamp and precedes older migrated records; null legacy rows retain their compatibility order', async () => {
  const initial = feedRows(28, () => 'public');
  const h = harness({ initial });
  const published = await h.publish(h.context({ body: { ...h.media(), client_request_id: 'new-among-migrated' } }));
  assert.equal(published.status, 200);
  const stored = h.posts.find(post => post.id === published.value.id);
  assert.equal(stored.legacy_created_at, stored.created_at, 'The production create mapper writes both timestamps');
  assert.ok(stored.legacy_created_at > initial[0].legacy_created_at);
  const first = await h.feed(h.context({ viewerId: viewer.id, pagination: 'v2', limit: 12 }));
  assert.ok(first.value.posts.some(post => post.id === published.value.id), 'A real new post is in the first authorized window');

  // A separate compatibility edge, not the actual POST /posts create behavior:
  // null legacy dates sort after dated records under the existing feed order.
  const nullLegacy = { ...stored, id: postId(30_000), legacy_post_id: postId(30_000), legacy_created_at: null };
  h.posts.push(nullLegacy);
  let cursor;
  const traversed = [];
  do {
    const page = await h.feed(h.context({ viewerId: viewer.id, pagination: 'v2', limit: 12, cursor }));
    assert.equal(page.status, 200);
    traversed.push(...page.value.posts.map(post => post.id));
    cursor = page.value.nextCursor;
  } while (cursor);
  assert.equal(traversed.at(-1), nullLegacy.id);
  assert.equal(new Set(traversed).size, initial.length + 2);
});

test('v2 actual feed handler traverses authorization-filtered windows without duplicate or skipped posts', async () => {
  const initial = feedRows(100, i => i % 2 ? 'public' : 'private');
  const h = harness({ initial });
  const ids = [];
  let cursor;
  let rounds = 0;
  do {
    const response = await h.feed(h.context({ viewerId: viewer.id, pagination: 'v2', cursor, limit: 12 }));
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('cache-control'), 'no-store');
    ids.push(...response.value.posts.map(post => post.id));
    assert.equal(response.value.hasMore, response.value.nextCursor !== null);
    assert.notEqual(response.value.nextCursor, cursor ?? '', 'Cursor advances or terminates');
    cursor = response.value.nextCursor;
    assert.ok(++rounds < 10);
  } while (cursor);
  assert.deepEqual(ids, initial.filter(post => post.visibility === 'public').map(post => post.id));
  assert.equal(new Set(ids).size, 50);
  for (const query of h.queries.filter(q => q.order === pagination.feedKeysetOrder)) {
    assert.equal(query.offset, undefined);
    assert.ok(query.limit <= 100);
  }
});

test('v2 empty bounded scan returns an opaque advancing continuation; final accessible post remains reachable', async () => {
  const initial = feedRows(125, i => i === 124 ? 'public' : 'private');
  const h = harness({ initial });
  const first = await h.feed(h.context({ viewerId: viewer.id, pagination: 'v2', limit: 12 }));
  assert.equal(first.value.posts.length, 0);
  assert.equal(first.value.hasMore, true);
  assert.ok(first.value.nextCursor);
  assert.ok(!first.value.nextCursor.includes(initial[95].id));
  const next = await h.feed(h.context({ viewerId: viewer.id, pagination: 'v2', limit: 12, cursor: first.value.nextCursor }));
  assert.equal(next.value.posts.length, 1);
  assert.equal(next.value.posts[0].id, initial[124].id);
  assert.equal(next.value.hasMore, false);
  assert.equal(next.value.nextCursor, null);
});

test('v2 ignores insertions ahead of the cursor, tolerates removed boundary rows, and rejects wrong account/scope', async () => {
  const initial = feedRows(35, () => 'public');
  const h = harness({ initial });
  const first = await h.feed(h.context({ viewerId: viewer.id, pagination: 'v2', limit: 12 }));
  const cursor = first.value.nextCursor;
  h.posts.splice(11, 1); // The opaque boundary contains values, not a DB lookup requirement.
  h.posts.unshift({ ...initial[0], id: postId(20_000), legacy_post_id: postId(20_000), created_at: new Date(Date.now() + 60_000).toISOString() });
  const next = await h.feed(h.context({ viewerId: viewer.id, pagination: 'v2', limit: 12, cursor }));
  assert.deepEqual(Array.from(next.value.posts, post => post.id), initial.slice(12, 24).map(post => post.id));
  for (const context of [{ viewerId: author.id, scope: 'for_you' }, { viewerId: viewer.id, scope: 'around' }]) {
    // Around lacks a city on these posts but must still validate token binding.
    const result = await h.feed(h.context({ ...context, pagination: 'v2', cursor }));
    assert.equal(result.status, 400);
    assert.equal(result.value.code, 'FEED_CURSOR_INVALID');
  }
});

test('v2 world-board uses identical authorized pagination and legacy callers still receive arrays', async () => {
  const h = harness({ initial: feedRows(30, i => i % 2 ? 'public' : 'private') });
  const response = await h.world(h.context({ viewerId: '', pagination: 'v2', limit: 12 }));
  assert.equal(response.status, 200);
  assert.equal(response.value.posts.length, 12);
  assert.ok(response.value.posts.every(post => post.visibility === 'public'));
  const legacy = await h.feed(h.context({ viewerId: viewer.id }));
  assert.ok(Array.isArray(legacy.value));
  const legacyWorld = await h.world(h.context({ viewerId: '' }));
  assert.ok(Array.isArray(legacyWorld.value));
});
