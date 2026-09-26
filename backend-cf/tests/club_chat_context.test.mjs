import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const worker = readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8');
const native = readFileSync(new URL('../../ios_native/MIRA/Sources/MIRANative/Screens/ConversationNativeView.swift', import.meta.url), 'utf8');
const home = readFileSync(new URL('../../ios_native/MIRA/Sources/MIRANative/Screens/MainFeedView.swift', import.meta.url), 'utf8');

test('club member context remains behind group membership authorization', () => {
  const route = worker.slice(worker.indexOf("api.get('/group-chats/:groupId/messages'"), worker.indexOf("api.post('/group-chats/:groupId/messages'"));
  assert.match(route, /requireGroupMember\(c, groupId, userId\)/);
  assert.match(route, /member_count: members\.length/);
  assert.match(route, /members: memberProfiles/);
  assert.match(route, /active_count: presence \?/);
  assert.match(route, /safeMediaReference\(profile\.avatar_url\)/);
});

test('club room keeps live message transport and only shows supplied activity', () => {
  assert.match(native, /ClubChatHeader\(title: title, info: model\.groupInfo/);
  assert.match(native, /if let activity = model\.groupInfo\?\.activity/);
  assert.match(native, /\/group-chats\/\\\(groupId\)\/messages/);
  assert.match(native, /ClubChatLinkMessage\(url: link, api: model\.api\)/);
});

test('Home status rail is API-backed, neutral, and masked by fixed controls', () => {
  assert.match(home, /try await model\.api\.get\("\/statuses"\)/);
  assert.ok(home.includes('.accessibilityIdentifier("home.fixed.controls")'));
  assert.match(home, /\.clipped\(\)\s*\.accessibilityIdentifier\("home\.story\.rail"\)/);
  assert.ok(home.includes('.frame(width: 162, alignment: .leading)'));
  assert.doesNotMatch(home.slice(home.indexOf('private var homeTopBar'), home.indexOf('private func homeSectionButton')), /linearGradient|AngularGradient|rainbow/i);
});
