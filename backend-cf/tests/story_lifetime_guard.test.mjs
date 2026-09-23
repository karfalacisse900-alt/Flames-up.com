import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { test } from 'node:test';

const repoRoot = path.resolve(import.meta.dirname, '..', '..');

async function readRepoFile(relativePath) {
  return readFile(path.join(repoRoot, relativePath), 'utf8');
}

test('new statuses expire after 24 hours and legacy reports use the same window', async () => {
  const worker = await readRepoFile('backend-cf/src/index.ts');
  assert.match(worker, /const storyLifetimeMs = 24 \* 60 \* 60 \* 1000;/);
  assert.match(worker, /s\.created_at >= datetime\('now', '-1 day'\)/);
  assert.match(worker, /expires_at: `gt\.\${now\(\)\}`/);
});

test('story viewers are owner-only and replies are private direct messages', async () => {
  const worker = await readRepoFile('backend-cf/src/index.ts');
  assert.match(worker, /api\.get\('\/statuses\/:statusId\/viewers'/);
  assert.match(worker, /publicId\(stories\[0\]\.user_id, 120\) !== userId/);
  assert.match(worker, /api\.post\('\/statuses\/:statusId\/reply'/);
  assert.match(worker, /validateDirectMessagePeer\(c, userId, receiverId\)/);
  assert.match(worker, /story_reply_id: storyId/);
});

test('story links are validated against an active public Captro post', async () => {
  const worker = await readRepoFile('backend-cf/src/index.ts');
  assert.match(worker, /linkedPostId = publicId/);
  assert.match(worker, /status: postgrestEqFilter\('active'\)/);
  assert.match(worker, /normalizeVisibility\(linkedPost.visibility\) !== 'public'/);
});

test('story text and media must pass server-side publication checks', async () => {
  const worker = await readRepoFile('backend-cf/src/index.ts');
  assert.match(worker, /moderations\.create\(\{ model: c\.env\.OPENAI_MODERATION_MODEL/);
  assert.match(worker, /Story text screening is unavailable/);
  assert.match(worker, /if \(result\.flagged\)/);
  assert.match(worker, /moderation_status: postgrestEqFilter\('approved'\)/);
  assert.match(worker, /submittedMediaUrl === safeMediaReference\(asset\.public_url\)/);
});

test('database enforces the 24-hour story expiry cap', async () => {
  const migration = await readRepoFile('supabase/migrations/20260922213005_story_24_hour_expiry_guard.sql');
  assert.match(migration, /app_stories_max_24h/);
  assert.match(migration, /as restrictive/);
  assert.match(migration, /created_at > now\(\) - interval '24 hours'/);
});

test('status editor keeps the writing area clear of the publish button', async () => {
  const editor = await readRepoFile('ios_native/MIRA/Sources/MIRANative/Screens/NotificationLibrarySearchCreateViews.swift');
  const publishPage = editor.slice(editor.indexOf('private func storyPublishPage'), editor.indexOf('private func storyDetailRow'));
  assert.match(publishPage, /TextEditor\(text: \$storyCaption\)[\s\S]*?\.focused\(\$isStoryCaptionFocused\)/);
  assert.match(publishPage, /if isStoryCaptionFocused \{[\s\S]*?Button\("Done"\)/);
  assert.match(publishPage, /if !isStoryCaptionFocused \{\s*Button \{/);
  assert.match(publishPage, /\.scrollDismissesKeyboard\(\.interactively\)/);
});
