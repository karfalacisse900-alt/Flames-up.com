import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { test } from 'node:test';

const repoRoot = path.resolve(import.meta.dirname, '..', '..');

async function readRepoFile(relativePath) {
  return readFile(path.join(repoRoot, relativePath), 'utf8');
}

test('iOS engagement hydration uses fresh server state before stale local cache', async () => {
  const engagementSync = await readRepoFile('ios_native/MIRA/Sources/MIRANative/Services/MIRAPostEngagementSync.swift');
  const appCacheStore = await readRepoFile('ios_native/MIRA/Sources/MIRANative/Services/MIRAAppCacheStore.swift');

  assert.match(
    engagementSync,
    /private static func mergedViewerFlag[\s\S]*?if let fresh \{ return fresh \}[\s\S]*?return cached/,
    'MIRAPostEngagementSync must prefer fresh server liked/saved flags over cached flags'
  );
  assert.doesNotMatch(
    engagementSync,
    /private static func mergedViewerFlag[\s\S]*?if let cached \{ return cached \}[\s\S]*?return fresh/,
    'MIRAPostEngagementSync must not let stale cached flags override fresh server state'
  );

  assert.match(
    appCacheStore,
    /private func mergedViewerFlag[\s\S]*?if let fresh \{ return fresh \}[\s\S]*?return cached/,
    'MIRAAppCacheStore must prefer fresh server liked/saved flags over cached flags'
  );
  assert.doesNotMatch(
    appCacheStore,
    /private func mergedViewerFlag[\s\S]*?if let cached \{ return cached \}[\s\S]*?return fresh/,
    'MIRAAppCacheStore must not preserve stale liked/saved flags over fresh server state'
  );
});

test('post detail refresh does not merge current stale engagement over refreshed server post', async () => {
  const detailView = await readRepoFile('ios_native/MIRA/Sources/MIRANative/Screens/PostDetailNativeView.swift');

  assert.doesNotMatch(
    detailView,
    /liked:\s*mergedViewerFlag\(cached:\s*current\.viewerLikedValue/,
    'Post detail refresh must not override refreshed liked state with current stale state'
  );
  assert.doesNotMatch(
    detailView,
    /saved:\s*mergedViewerFlag\(cached:\s*current\.viewerSavedValue/,
    'Post detail refresh must not override refreshed saved state with current stale state'
  );
});

test('Worker engagement mutations return the requested viewer state after canonical repair', async () => {
  const worker = await readRepoFile('backend-cf/src/index.ts');

  assert.match(
    worker,
    /const legacyAuthLikeAppId = isUuidText\(appUserId\);[\s\S]*?return `auth:\$\{legacyAuthLikeAppId\}`;/,
    'legacy UUID-only interaction rows must collapse to one canonical auth actor instead of a second app actor'
  );
  assert.match(
    worker,
    /const state = await getCanonicalPostEngagementState\(c, canonicalPostId, userId\);[\s\S]*?state\.liked = nextLiked;[\s\S]*?const changed = nextLiked !== wasLiked;/,
    'like response must return the explicit requested viewer state after repair'
  );
  assert.match(
    worker,
    /const state = await getCanonicalPostEngagementState\(c, canonicalPostId, userId\);[\s\S]*?state\.saved = saved;[\s\S]*?const changed = saved !== wasSaved;/,
    'save response must return the explicit requested viewer state after repair'
  );
});
