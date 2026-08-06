import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { test } from 'node:test';

const repoRoot = path.resolve(import.meta.dirname, '..', '..');

async function read(relativePath) {
  return readFile(path.join(repoRoot, relativePath), 'utf8');
}

test('conversation starter analytics is authenticated, rate-limited, and anonymous', async () => {
  const worker = await read('backend-cf/src/index.ts');
  const start = worker.indexOf("api.post('/analytics/conversation-starters'");
  const end = worker.indexOf("// Library", start);
  const route = worker.slice(start, end);

  assert.ok(start >= 0, 'conversation starter route must exist');
  assert.match(route, /api\.post\('\/analytics\/conversation-starters', authMiddleware/);
  assert.match(route, /requireSupabasePrimaryDatabase\(c, 'conversation_starter_analytics'\)/);
  assert.match(route, /enforceRateLimit\(c, 'conversation_starter_analytics', clientIp\(c\), 30, 60\)/);
  assert.match(route, /event_name: 'conversation_starter_selected'/);
  assert.match(route, /user_id: null/);
  assert.match(route, /metadata: \{ starter_id: starterId, surface \}/);
  assert.doesNotMatch(route, /post_id/);
  assert.doesNotMatch(route, /comment_text|commentText|body_text/);
});

test('conversation starters are local templates that only prefill the existing composer', async () => {
  const component = await read('ios_native/MIRA/Sources/MIRANative/Components/MIRAConversationStarters.swift');
  const discover = await read('ios_native/MIRA/Sources/MIRANative/Screens/DiscoverNativeView.swift');
  const detail = await read('ios_native/MIRA/Sources/MIRANative/Screens/PostDetailNativeView.swift');

  assert.match(component, /enum MIRAConversationStarterEngine/);
  assert.match(component, /templates\.prefix\(3\)/);
  assert.match(component, /guard !post\.feedMediaURLs\.isEmpty else \{ return false \}/);
  assert.match(component, /visibility.*!= "private"/);
  assert.match(component, /return post\.userId != viewerID/);
  assert.match(component, /accessibilityLabel\("Conversation starter:/);
  assert.doesNotMatch(component, /api\.get|api\.post|URLSession|OpenAI|Workers AI/i);

  assert.match(discover, /conversationStarterDraft = starter\.text/);
  assert.match(discover, /isCommentsPresented = true/);
  assert.match(detail, /draft = starter\.text/);
  assert.match(detail, /isCommentFocused = true/);
  assert.doesNotMatch(discover, /sendComment\(starter\.text\)/);
  assert.doesNotMatch(detail, /sendComment\(starter\.text\)/);
});
