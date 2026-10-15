import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import ts from 'typescript';
import * as writing from '../src/creation-intent.ts';
import { retiredPostInputError } from '../src/retired-posting.ts';
import { orderPostMediaAssets } from '../src/post-media.ts';
import { rankVisibleFeedWindow } from '../src/feed-relevance.ts';
import { validatedStampVariant } from '../src/stamp-style.ts';
import { creatorEventDetails, isEventPostType, validateCreatorEvent } from '../src/post-objects.ts';

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
    'supabaseReadVisiblePosts', 'isVideoMediaUrl', 'postPayload', 'feedPostPayload',
  ].map(fn).join('\n');
  const code = functions + '\n' + handler('post', '/posts', 'publish') + '\n'
    + handler('get', '/posts/feed', 'feed') + '\n' + handler('get', '/posts/:postId', 'details');
  const normalizeMedia = (images, image) => [...new Set([...array(images), image].map(clean).filter(Boolean))];
  const bindings = {
    ...writing, retiredPostInputError, orderPostMediaAssets, rankVisibleFeedWindow,
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
        if (key === 'or') return condition.includes(row.id) || condition.includes(row.legacy_post_id);
        const value = key.startsWith('metadata->>') ? row.metadata?.[key.slice(11)] : row[key];
        if (condition.startsWith('eq.')) return value === condition.slice(3);
        if (condition.startsWith('ilike.')) return clean(value).toLowerCase() === condition.slice(6).toLowerCase();
        if (condition.startsWith('in.(')) return condition.slice(4, -1).split(',').includes(value);
        throw Error(`Unhandled test filter ${key}`);
      }));
      return rows.slice(query.offset || 0, (query.offset || 0) + query.limit);
    },
  };
  const js = ts.transpileModule(code, { compilerOptions: { target: ts.ScriptTarget.ES2022 } }).outputText;
  const routes = vm.runInNewContext(`${js}\n({publish, feed, details, read: supabaseReadVisiblePosts})`, bindings);
  function context({ viewerId = author.id, body = {}, scope = 'for_you', skip = 0, id = '', limit = 20 } = {}) {
    return { viewerId, env: {}, set() {}, get() {},
      req: { json: async () => body, query: key => ({ scope, skip: String(skip), limit: String(limit) })[key], param: () => id },
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

test('media metadata missing dimensions is not misclassified as a retired text-only post on the server', async () => {
  const h = harness();
  const upload = h.media();
  delete upload.media_dimensions;
  const result = await h.publish(h.context({ body: upload }));
  assert.equal(result.status, 200);
  assert.equal((await h.feed(h.context())).value[0].images.length, 1);
  const textOnly = await h.publish(h.context({ body: { content: 'Legacy draft text' } }));
  assert.equal(textOnly.status, 400);
  assert.equal(textOnly.value.code, 'POST_MEDIA_REQUIRED');
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
