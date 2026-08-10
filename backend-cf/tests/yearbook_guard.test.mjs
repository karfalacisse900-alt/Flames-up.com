import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { test } from 'node:test';

const repoRoot = path.resolve(import.meta.dirname, '..', '..');

async function read(relativePath) {
  return readFile(path.join(repoRoot, relativePath), 'utf8');
}

test('Yearbook schema is migration-backed, constrained, indexed, and RLS protected', async () => {
  const migration = await read('supabase/migrations/20260807201500_yearbook_social_discovery.sql');

  for (const table of [
    'yearbook_profiles',
    'yearbook_prompt_answers',
    'yearbook_signatures',
    'yearbook_interest_signals',
  ]) {
    assert.match(migration, new RegExp(`create table if not exists public\\.${table}`, 'i'));
    assert.match(migration, new RegExp(`alter table public\\.${table} enable row level security`, 'i'));
    assert.match(migration, new RegExp(`revoke all on public\\.${table} from public, anon`, 'i'));
  }

  assert.match(migration, /references public\.app_users\(id\) on delete cascade/);
  assert.match(migration, /unique \(profile_user_id, signer_user_id\)/i);
  assert.match(migration, /not dating_enabled or age >= 18/i);
  assert.match(migration, /yearbook_profiles_discovery_idx/i);
  assert.match(migration, /yearbook_profiles_interests_gin_idx/i);
  assert.match(migration, /from_user_id = \(select private\.captro_current_app_user_id\(\)\)/i);
  assert.doesNotMatch(migration, /to_user_id = \(select private\.captro_current_app_user_id\(\)\)[\s\S]*for select/i);
});

test('Yearbook Worker routes require auth, Supabase primary storage, and block checks', async () => {
  const worker = await read('backend-cf/src/index.ts');
  const start = worker.indexOf('// Yearbook social discovery');
  const end = worker.indexOf('// Discover', start);
  const routes = worker.slice(start, end);

  assert.ok(start >= 0 && end > start, 'Yearbook route block must exist');
  for (const route of [
    '/yearbook/discover',
    '/yearbook/me',
    '/yearbook/profiles/:userId',
    '/yearbook/profiles/:userId/signatures',
    '/yearbook/profiles/:userId/interest',
  ]) {
    assert.match(routes, new RegExp(`api\\.(?:get|put|post|delete)\\('${route.replaceAll('/', '\\/')}', authMiddleware`));
  }
  assert.match(routes, /requireSupabasePrimaryDatabase\(c, 'yearbook_discover_read'\)/);
  assert.match(routes, /requireSupabasePrimaryDatabase\(c, 'yearbook_profile_write'\)/);
  assert.match(routes, /supabaseBlockPair\(c, signerId, targetId\)/);
  assert.match(routes, /supabaseBlockPair\(c, viewerId, targetId\)/);
  assert.doesNotMatch(routes, /c\.env\.DB|prepare\(|D1Database|KVNamespace/);
});

test('shared user hydration only selects real app_users columns', async () => {
  const worker = await read('backend-cf/src/index.ts');
  const start = worker.indexOf('async function supabaseUsersByAnyIds');
  const end = worker.indexOf('async function supabaseBlockedUserIds', start);
  const helper = worker.slice(start, end);

  assert.ok(start >= 0 && end > start, 'shared user hydration helper must exist');
  assert.match(helper, /is_verified,counts,profile,metadata/);
  assert.doesNotMatch(helper, /is_verified,status,counts/);
  assert.match(worker, /'metadata->>status': postgrestEqFilter\('suspended'\)/);
});

test('Yearbook signatures are one-per-pair and preserve their moderation identity', async () => {
  const worker = await read('backend-cf/src/index.ts');
  const start = worker.indexOf("api.post('/yearbook/profiles/:userId/signatures'");
  const end = worker.indexOf("api.delete('/yearbook/profiles/:userId/signatures/me'", start);
  const route = worker.slice(start, end);

  assert.match(route, /select: 'id,created_at'/);
  assert.match(route, /const id = publicId\(existingRows\[0\]\?\.id, 120\) \|\| uuid\(\)/);
  assert.match(route, /'profile_user_id,signer_user_id'/);
  assert.match(route, /created_at: existingRows\[0\]\?\.created_at \|\| now\(\)/);
  assert.doesNotMatch(route, /metadata:/);
});

test('Dating interest is private, adult-only, opted-in, and revealed only when mutual', async () => {
  const worker = await read('backend-cf/src/index.ts');

  assert.match(worker, /intent === 'dating'[\s\S]*viewerYearbookProfile\?\.dating_enabled === true[\s\S]*Number\(viewerYearbookProfile\?\.age \|\| 0\) >= 18/);
  assert.match(worker, /!viewerDatingEligible[\s\S]*dating_unavailable: true/);
  assert.match(worker, /!viewer\?\.dating_enabled \|\| Number\(viewer\?\.age \|\| 0\) < 18/);
  assert.match(worker, /!target\?\.dating_enabled \|\| Number\(target\?\.age \|\| 0\) < 18/);
  assert.match(worker, /return \{ sent, mutual: sent && reverseRows\.length > 0 \}/);
  assert.match(worker, /interest_available: interestAvailable/);
});

test('Yearbook discovery does not turn missing age filters into an age-16-only query', async () => {
  const worker = await read('backend-cf/src/index.ts');
  const helperStart = worker.indexOf('async function supabaseYearbookDiscover');
  const helperEnd = worker.indexOf('async function supabaseUpsertYearbookProfile', helperStart);
  const helper = worker.slice(helperStart, helperEnd);
  const routeStart = worker.indexOf("api.get('/yearbook/discover'");
  const routeEnd = worker.indexOf("api.get('/yearbook/me'", routeStart);
  const route = worker.slice(routeStart, routeEnd);

  assert.match(helper, /const hasAgeMin = Number\.isFinite\(rawAgeMin\) && rawAgeMin > 0/);
  assert.match(helper, /const hasAgeMax = Number\.isFinite\(rawAgeMax\) && rawAgeMax > 0/);
  assert.match(helper, /const hasAgeFilter = hasAgeMin \|\| hasAgeMax/);
  assert.match(route, /ageMin: ageMinQuery \? Number\(ageMinQuery\) : undefined/);
  assert.match(route, /ageMax: ageMaxQuery \? Number\(ageMaxQuery\) : undefined/);
  assert.doesNotMatch(route, /Number\(c\.req\.query\('age_(?:min|max)'\) \|\| 0\)/);
});

test('native Yearbook is a real tab with editor, privacy controls, and non-swipe discovery', async () => {
  const root = await read('ios_native/MIRA/Sources/MIRANative/App/MIRANativeRootView.swift');
  const screen = await read('ios_native/MIRA/Sources/MIRANative/Screens/YearbookNativeView.swift');
  const models = await read('ios_native/MIRA/Sources/MIRANative/Models/MIRAYearbookModels.swift');

  assert.match(root, /case yearbook/);
  assert.match(root, /MIRAYearbookNativeView\(api: api, currentUser: authSession\.user\)/);
  assert.match(root, /Label\("Yearbook", systemImage: "book\.closed\.fill"\)/);
  assert.match(screen, /YearbookEditorView/);
  assert.match(screen, /YearbookSignatureComposer/);
  assert.match(screen, /MIRAReportSheet/);
  assert.match(screen, /updateConnection\(\)/);
  assert.match(screen, /interestAvailable == true/);
  assert.match(screen, /URLQueryItem\(name: "city"/);
  assert.match(screen, /sectionOrderSection/);
  assert.match(screen, /resolvedSectionOrder/);
  assert.match(models, /enum MIRAYearbookVisibility/);
  assert.match(models, /fieldVisibility: \[String: String\]/);
  assert.match(screen, /NavigationLink[\s\S]*YearbookProfileDetailView/);
  assert.doesNotMatch(screen, /swipeToReject|swipeToMatch/i);
});

test('Yearbook browse spreads are compact, deduplicated, and use privacy-filtered prompt previews', async () => {
  const worker = await read('backend-cf/src/index.ts');
  const screen = await read('ios_native/MIRA/Sources/MIRANative/Screens/YearbookNativeView.swift');
  const helperStart = worker.indexOf('function yearbookDiscoverCardPayload');
  const helperEnd = worker.indexOf('async function supabaseUpsertYearbookProfile', helperStart);
  const helper = worker.slice(helperStart, helperEnd);

  assert.match(screen, /deduplicatedProfiles/);
  assert.match(screen, /Set<String>\(\)/);
  assert.match(screen, /profilesPerLeaf: Int \{\s*2\s*\}/);
  assert.match(screen, /profilesPerSpread: Int \{ profilesPerLeaf \* 2 \}/);
  assert.match(screen, /let columnCount = 1/);
  assert.match(screen, /LazyVGrid\(columns: columns/);
  assert.match(screen, /prefix\(profilesPerLeaf\)/);
  assert.match(helper, /'yearbook_prompt_answers'/);
  assert.match(helper, /const promptsByUser = new Map<string, any\[\]>/);
  assert.match(helper, /copyIfVisible\('prompts'/);
  assert.match(helper, /prompts: promptsByUser\.get\(uid\) \|\| \[\]/);
});
