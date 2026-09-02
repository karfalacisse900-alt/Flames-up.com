import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';
import ts from 'typescript';
import { DIRECT_VIDEO_MAX_BYTES, orderPostMediaAssets, streamProcessingState, streamUID } from '../src/post-media.ts';

const worker = readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8');
const ios = (path) => readFileSync(new URL(`../../ios_native/MIRA/Sources/MIRANative/${path}`, import.meta.url), 'utf8');
const cleanText = (value) => String(value ?? '').trim();

test('Stream needs confirmed encoding completion and never treats an error as ready', () => {
  for (const state of ['pendingupload', 'queued', 'encoding', 'inprogress', '']) {
    assert.equal(streamProcessingState({ status: { state }, readyToStream: false }), 'processing');
  }
  assert.equal(streamProcessingState({ status: { state: 'ready' }, readyToStream: false }), 'processing');
  assert.equal(streamProcessingState({ status: { state: 'ready' }, readyToStream: true }), 'ready');
  assert.equal(streamProcessingState({ status: { state: 'error' }, readyToStream: true }), 'failed');
  assert.equal(streamProcessingState(null), 'processing');
  assert.equal(DIRECT_VIDEO_MAX_BYTES, 200_000_000);
});

test('Stream HLS references resolve to the same provider ID for posters', () => {
  for (const reference of [
    'cfstream:abc123xyz',
    'https://videodelivery.net/abc123xyz/manifest/video.m3u8',
    'https://customer-example.cloudflarestream.com/abc123xyz/manifest/video.m3u8',
  ]) assert.equal(streamUID(reference), 'abc123xyz');
  assert.equal(streamUID('https://imagedelivery.net/stream-sunset/photo/public'), '');
  assert.equal(streamUID('https://videodelivery.net.attacker.test/abc123xyz'), '');
});

test('mixed-media cover/order is determined by selection, not database row order', () => {
  const image = { id: 'image', media_type: 'image' };
  const video = { id: 'video', media_type: 'video' };
  assert.deepEqual(orderPostMediaAssets([image, video], ['video', 'image']), [video, image]);
});

function approvalFunction(rows) {
  const start = worker.indexOf('async function approvedMediaAssetsForPost(');
  const end = worker.indexOf('async function supabaseAdminDeleteSafe', start);
  const context = vm.createContext({
    supabasePrimaryConfigured: () => true,
    supabaseAdminQueryRows: async (_c, table, query) => {
      assert.equal(table, 'app_media_assets');
      assert.equal(query.filters.user_id, 'eq.owner');
      return rows;
    },
    supabaseMediaAssetToLegacy: (asset) => asset,
    postgrestEqFilter: (value) => `eq.${value}`,
    postgrestInFilter: (ids) => `in.(${ids.join(',')})`,
    normalizeMediaModerationStatus: cleanText, cleanText, orderPostMediaAssets,
  });
  vm.runInContext(ts.transpileModule(worker.slice(start, end), { compilerOptions: { target: ts.ScriptTarget.ES2022 } }).outputText, context);
  return context.approvedMediaAssetsForPost;
}

test('approved owner videos can publish, in order, without weakening moderation', async () => {
  const video = { id: 'video', media_type: 'video', moderation_status: 'approved', upload_status: 'uploaded' };
  const image = { ...video, id: 'image', media_type: 'image' };
  const result = await approvalFunction([image, video])({}, 'owner', ['video', 'image'], []);
  assert.equal(result.ok, true);
  assert.deepEqual(Array.from(result.assets, (asset) => asset.id), ['video', 'image']);
  for (const moderation_status of ['rejected', 'review_required', 'failed', 'pending_moderation']) {
    const blocked = await approvalFunction([{ ...video, moderation_status }])({}, 'owner', ['video'], []);
    assert.equal(blocked.ok, false);
    assert.equal(blocked.status, 409);
  }
  assert.equal((await approvalFunction([])({}, 'owner', ['other-user-video'], [])).status, 404);
});

function completeRoute(video, assetOverrides = {}) {
  let handler;
  const events = [];
  const asset = { id: 'media', storage_key: 'abc123xyz', storage_provider: 'stream', media_type: 'video', moderation_status: 'uploading', upload_status: 'uploading', ...assetOverrides };
  const context = vm.createContext({
    api: { post: (_path, _auth, fn) => { handler = fn; } }, authMiddleware: () => {},
    rejectLargeRequest: () => null, requireSupabasePrimaryDatabase: () => null,
    getUserId: () => 'owner', enforceRateLimit: async () => null,
    publicId: cleanText, cleanText, cleanMultilineText: cleanText,
    postgrestEqFilter: (value) => `eq.${value}`,
    normalizeMediaModerationStatus: cleanText,
    supabaseReadMediaAsset: async (_c, id, userId) => {
      assert.equal(id, 'media'); assert.equal(userId, 'owner'); return asset;
    },
    cloudflareAccountId: () => 'account', cloudflareStreamToken: () => 'test-token',
    fetch: async () => ({ ok: true, json: async () => ({ success: true, result: video }) }),
    streamProcessingState, POST_VIDEO_MAX_SECONDS: 60,
    now: () => '2026-09-02T00:00:00Z',
    clampNumber: (v, min, max, fallback) => Math.min(max, Math.max(min, Number(v) || fallback)),
    clampFloat: (v) => Number(v) || 0,
    supabaseAdminPatchRows: async () => { events.push('patch'); },
    supabaseInsertModerationEvent: async () => {},
    createMediaModerationJob: async (_c, _id, _user, _caption, options) => {
      assert.equal(options.enqueue, true); events.push('moderation'); return 'job';
    },
  });
  const start = worker.indexOf("api.post('/media/complete'");
  const end = worker.indexOf("api.get('/media/:mediaId/status'", start);
  vm.runInContext(ts.transpileModule(worker.slice(start, end), { compilerOptions: { target: ts.ScriptTarget.ES2022 } }).outputText, context);
  return { events, run: () => handler({ env: {}, req: { json: async () => ({ media_id: 'media' }) }, json: (body, status = 200) => ({ body, status }) }) };
}

test('real completion route waits for Stream before starting moderation', async () => {
  const pending = completeRoute({ status: { state: 'encoding' }, readyToStream: false });
  assert.equal((await pending.run()).body.upload_status, 'processing');
  assert.deepEqual(pending.events, []);
  const failed = completeRoute({ status: { state: 'error' } });
  assert.equal((await failed.run()).body.moderation_status, 'failed');
  assert.deepEqual(failed.events, []);
  const ready = completeRoute({ status: { state: 'ready' }, readyToStream: true, duration: 10, input: { width: 1080, height: 1350 } });
  assert.equal((await ready.run()).body.moderation_status, 'pending_moderation');
  assert.deepEqual(ready.events, ['patch', 'moderation']);
  const repeated = completeRoute({}, { moderation_status: 'pending_moderation', upload_status: 'uploaded' });
  assert.equal((await repeated.run()).status, 202);
  assert.deepEqual(repeated.events, []);
});

test('post creation accepts both kinds; Home remains post-only paging', () => {
  const composer = ios('Screens/NotificationLibrarySearchCreateViews.swift');
  assert.match(composer, /matching: \.any\(of: \[\.images, \.videos\]\)/);
  assert.doesNotMatch(composer, /Feed posts are photo-only/);
  assert.doesNotMatch(worker, /FEED_POSTS_PHOTO_ONLY/);
  const home = ios('Screens/MainFeedView.swift');
  const topBar = home.slice(home.indexOf('private var homeTopBar'), home.indexOf('private func homeSectionButton'));
  assert.match(topBar, /square\.and\.pencil/);
  assert.doesNotMatch(topBar, /bell|NotificationNativeView/);
  assert.match(home, /selectedMediaIndex: \.constant\(0\),\s*showsCoverMediaOnly: true/);
  assert.match(home, /scenePhase != \.active \|\| detailPost != nil/);
  const pager = ios('Screens/CaptroFeedMediaPager.swift');
  assert.match(pager, /isVideoMuted = true/);
  assert.match(pager, /shouldPlay: isVideoActive && !isVideoPaused/);
  assert.match(pager, /mediaURLs.count > 1 && !showsCoverMediaOnly/);
  assert.match(pager, /if currentMediaIsVideo \{\s*isVideoPaused.toggle\(\)/);
  assert.match(ios('Screens/PostDetailNativeView.swift'), /TabView\(selection: \$selectedIndex\)/);
});
