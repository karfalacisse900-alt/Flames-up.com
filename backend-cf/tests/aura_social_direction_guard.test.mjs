import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { test } from 'node:test';

const repoRoot = path.resolve(import.meta.dirname, '..', '..');

async function read(relativePath) {
  return readFile(path.join(repoRoot, relativePath), 'utf8');
}

function section(source, startNeedle, endNeedle) {
  const start = source.indexOf(startNeedle);
  const end = source.indexOf(endNeedle, start + startNeedle.length);
  assert.ok(start >= 0, `missing section start: ${startNeedle}`);
  assert.ok(end > start, `missing section end: ${endNeedle}`);
  return source.slice(start, end);
}

test('Aura community feed admits text-only Small Posts and only the two adopted post types', async () => {
  const worker = await read('backend-cf/src/index.ts');
  const renderability = section(
    worker,
    'const AURA_SMALL_POST_CATEGORIES',
    'function normalizeAuraAtomicAmount',
  );

  assert.match(renderability, /AURA_COMMUNITY_POST_TYPES = new Set\(\['small_post', 'meetup'\]\)/);
  assert.match(renderability, /postType === 'small_post'/);
  assert.match(renderability, /!!\(title \|\| content \|\| supabaseAppPostHasRenderableMedia\(row\)\)/);
  assert.doesNotMatch(renderability, /receipt|invoice|proof/i);

  const readPath = section(worker, 'function supabaseCandidatePostRows', 'async function augmentAuraMeetupState');
  assert.match(readPath, /supabaseAppPostHasRenderablePhotoMedia\(row\) \|\| auraCommunityPostHasRenderableContent\(row\)/);
  assert.doesNotMatch(readPath, /feedPhotoPostsOnly\(mapped\)|feedPhotoPostsOnly\(engaged\)/);
});

test('Friends and city feeds use stable cursor pages while preserving the legacy array route', async () => {
  const [worker, paginationModule] = await Promise.all([
    read('backend-cf/src/index.ts'),
    read('backend-cf/src/aura-community-pagination.js'),
  ]);
  const cityHelpers = `${paginationModule}\n${section(worker, 'function auraCommunityPostCity', 'function feedPhotoPostWhere')}`;
  const readPath = section(worker, 'function supabaseCandidatePostRows', 'async function augmentAuraMeetupState');
  const route = section(worker, "api.get('/posts/community-feed'", "api.get('/posts/community-mine'");

  assert.match(route, /authMiddleware/);
  assert.match(route, /scope !== 'friends' && scope !== 'city'/);
  assert.match(route, /socialScope: scope/);
  assert.match(route, /cache-control', 'no-store'/);

  assert.match(readPath, /if \(options\.socialScope \|\| options\.communityOnly\) \{\s*filters\.post_type = postgrestInFilter\(Array\.from\(AURA_COMMUNITY_POST_TYPES\)\)/s);
  assert.match(readPath, /user_id: postgrestInFilter\(viewerAliases\)/);
  assert.match(readPath, /const viewerSet = new Set\(viewerAliases\)/);
  assert.match(readPath, /collectAuraCommunityCursorPage<any, any>/);
  assert.match(readPath, /order: 'created_at\.desc,id\.desc'/);
  assert.match(readPath, /auraCommunityFeedCursorFilter\(position\)/);
  assert.match(readPath, /next_cursor:/);

  const friendsFilter = section(readPath, "if (options.socialScope === 'friends')", "if (options.socialScope === 'city')");
  assert.match(friendsFilter, /connectedIds\.has\(authorId\)/);
  assert.match(friendsFilter, /followingIds\.has\(authorId\)/);
  assert.doesNotMatch(friendsFilter, /connectedOrFollowingIds\.has\(authorId\)/);

  assert.match(cityHelpers, /newYorkCityAliases/);
  assert.match(cityHelpers, /'newyorkny'/);
  assert.match(cityHelpers, /'brooklynny'/);
  assert.match(cityHelpers, /\(place as any\)\.city \|\| \(raw as any\)\.display_city \|\| \(metadata as any\)\.display_city/);
  assert.match(cityHelpers, /author\?\.city \|\| \(authorProfile as any\)\.city \|\| \(authorMetadata as any\)\.city/);
  assert.match(readPath, /auraCommunityPostCity\(row, author\) === requestedCity/);
  assert.match(route, /pagination === 'cursor'/);
  assert.match(route, /items: page\.items\.map/);
  assert.match(route, /next_cursor: page\.next_cursor/);
  assert.match(route, /has_more: page\.has_more/);
  assert.match(route, /event: 'aura_community_feed_read'/);
  assert.match(route, /returned_count: rows\.length/);

  const mineRoute = section(worker, "api.get('/posts/community-mine'", "api.get('/posts/world-board'");
  assert.match(mineRoute, /ownerId: userId,\s*communityOnly: true/s);
});

test('community audience controls persisted visibility and friends are not treated as followers', async () => {
  const worker = await read('backend-cf/src/index.ts');
  const visibility = section(worker, 'function supabaseAppPostVisibleToViewer', 'function supabaseAppPostToLegacy');
  const create = section(worker, "api.post('/posts'", "api.get('/posts/feed'");

  assert.match(create, /let visibility = normalizeVisibility\(b\.visibility\)/);
  assert.match(create, /if \(isAuraCommunityPostType\(postType\)\) \{\s*visibility = normalizeVisibility\(communityResult\.value\?\.audience\)/s);
  assert.match(visibility, /visibility === 'followers'[^\n]+followingIds\.has\(appUserId\)/);
  assert.match(visibility, /visibility === 'friends'[^\n]+friendIds\.has\(appUserId\)/);
  assert.doesNotMatch(visibility, /visibility === 'followers' \|\| visibility === 'friends'/);
});

test('meetup creation, participation, and replies are bounded and server-authoritative', async () => {
  const worker = await read('backend-cf/src/index.ts');
  const metadata = section(worker, 'function auraCommunityMetadataFromBody', 'function auraCommunityMetadataFromRow');
  const create = section(worker, "api.post('/posts'", "api.get('/posts/feed'");
  const join = section(worker, "api.post('/posts/:postId/meetup/join'", "api.delete('/posts/:postId/meetup/join'");
  const comments = section(worker, "api.post('/posts/:postId/comments'", "api.get('/posts/:postId/comments'");

  assert.match(metadata, /AURA_SMALL_POST_CATEGORIES\.has\(category\)/);
  assert.match(metadata, /AURA_COMMUNITY_AUDIENCES\.has\(audience\)/);
  assert.match(metadata, /Date\.parse\(endsAt\) <= Date\.parse\(startsAt\)/);
  assert.match(metadata, /normalizeAuraAtomicAmount/);
  assert.match(metadata, /clampNumber\([^\n]+2, 500, 12\)/);
  assert.match(create, /code: 'EMPTY_SMALL_POST'/);
  assert.match(create, /code: 'INCOMPLETE_MEETUP'/);
  assert.match(create, /community: communityResult\.value/);

  assert.match(join, /authMiddleware/);
  assert.match(join, /enforceRateLimit/);
  assert.match(join, /enforceUserRestriction/);
  assert.match(join, /auraJoinFreeMeetup\(c, postId, userId\)/);
  assert.doesNotMatch(join, /payment_txid|amount_atoms|balance/);

  assert.match(comments, /community_allow_replies === false/);
  assert.match(comments, /code: 'REPLIES_DISABLED'/);
});

test('meetup migration keeps joins private, serializes capacity, and rejects paid joins', async () => {
  const migration = await read('supabase/migrations/20260825143000_aura_social_meetups.sql');

  assert.match(migration, /unique \(post_id, app_user_id\)/i);
  assert.match(migration, /unique index[^;]+payment_txid[^;]+where payment_txid is not null/is);
  assert.match(migration, /alter table public\.aura_meetup_joins enable row level security/i);
  assert.match(migration, /revoke all on table public\.aura_meetup_joins from public, anon, authenticated/i);
  assert.match(migration, /grant select, insert, update, delete on table public\.aura_meetup_joins to service_role/i);

  assert.match(migration, /security definer\s+set search_path = pg_catalog, public/i);
  assert.match(migration, /revoke all on function public\.aura_join_free_meetup\(text, text\) from public, anon, authenticated/i);
  assert.match(migration, /grant execute on function public\.aura_join_free_meetup\(text, text\) to service_role/i);
  assert.match(migration, /PAID_MEETUP_REQUIRES_CONFIRMED_AUR/);

  const lockPosition = migration.indexOf('for update;');
  const countPosition = migration.indexOf('select count(*)::integer');
  const insertPosition = migration.indexOf('insert into public.aura_meetup_joins');
  assert.ok(lockPosition >= 0 && lockPosition < countPosition, 'the meetup row must be locked before capacity is counted');
  assert.ok(countPosition < insertPosition, 'capacity must be checked before insertion');
  assert.match(migration, /if v_joined >= v_capacity then/);
  assert.match(migration, /on conflict \(post_id, app_user_id\) do update/i);
});

test('social backend and migration do not inject reference-image sample content', async () => {
  const [worker, migration] = await Promise.all([
    read('backend-cf/src/index.ts'),
    read('supabase/migrations/20260825143000_aura_social_meetups.sql'),
  ]);
  const source = `${worker}\n${migration}`;
  assert.doesNotMatch(source, /Blank Street Coffee|Funny Study Group|1,248\.50 AUR|Welcome to Claim/i);
});

test('active Aura iOS shell follows the adopted social direction without moving dedicated features into Home', async () => {
  const [home, composer, models, root] = await Promise.all([
    read('ios_native/MIRA/Sources/MIRANative/Screens/Aura/AuraHomeView.swift'),
    read('ios_native/MIRA/Sources/MIRANative/Screens/Aura/AuraCreateCommunityPostView.swift'),
    read('ios_native/MIRA/Sources/MIRANative/Models/AuraCommunityModels.swift'),
    read('ios_native/MIRA/Sources/MIRANative/App/MIRANativeRootView.swift'),
  ]);

  assert.match(home, /feedScopeButton\(\.friends, title: "Friends"\)/);
  assert.match(home, /private let cityName = "New York City"/);
  assert.match(home, /components\.path = "\/posts\/community-feed"/);
  assert.match(home, /URLQueryItem\(name: "skip", value: String\(offset\)\)/);
  assert.match(home, /loadNextPage\(scope: scope, city: cityName\)/);
  assert.match(home, /AuraCreateCommunityPostView/);
  assert.match(home, /AuraSmallPostFeedCard/);
  assert.match(home, /AuraMeetupFeedCard/);
  assert.doesNotMatch(home, /walletFeed|proofFeed|networkStrip|receiptFeed|AuraTicketCard/);

  const modeEnum = section(models, 'public enum AuraCommunityPostMode', 'public enum AuraSmallPostCategory');
  assert.match(modeEnum, /case smallPost = "small_post"/);
  assert.match(modeEnum, /case meetup/);
  assert.doesNotMatch(modeEnum, /receipt|invoice|proof/i);
  assert.match(composer, /AuraCommunityPostMode\.allCases/);
  assert.match(composer, /Small Post or Meetup/);
  assert.doesNotMatch(composer, /Receipt Place|receipt post|case receipt/i);

  const tabEnum = section(root, 'public enum MIRATab', 'public enum MIRAStartupPhase');
  assert.match(tabEnum, /case home/);
  assert.match(tabEnum, /case scan/);
  assert.match(tabEnum, /case wallet/);
  assert.match(tabEnum, /case me/);
  assert.doesNotMatch(tabEnum, /case proofs|case reputation|case trade|case feed/);
});
