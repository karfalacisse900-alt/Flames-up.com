import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
const native = new URL('../../ios_native/MIRA/Sources/MIRANative/', import.meta.url);
const read = path => readFileSync(new URL(path, native), 'utf8');

test('ordinary publisher requires media, retains legacy draft data, and never submits response choices', () => {
  const draft = read('Models/CaptroCompositionDraft.swift');
  const composer = read('Screens/NotificationLibrarySearchCreateViews.swift');
  assert.match(draft, /!structured && mediaItems\.isEmpty/);
  assert.match(composer, /draft\.mediaRequirementMessage == nil/);
  assert.match(composer, /postResponse: nil/);
  assert.match(composer, /postResponse = draft\.postResponse/);
  assert.match(composer, /postResponse: postResponse/); // Save legacy draft metadata, not publish.
  assert.doesNotMatch(composer, /CaptroPostResponsePicker|case response|title: "Responses"/);
});
test('poll presentation is removed without touching server-authorized membership and RSVP', () => {
  assert.equal(existsSync(new URL('Components/CaptroPostResponseView.swift', native)), false);
  assert.doesNotMatch(read('Screens/CaptroFeedPostView.swift'), /CaptroTextOnlyStampCard|CaptroPostResponseView/);
  assert.doesNotMatch(read('Screens/CaptroPostDetailSections.swift'), /CaptroPostResponseView/);
  assert.match(read('Screens/CaptroPostDetailSections.swift'), /model\.toggleAttendance/);
  assert.match(read('Screens/CaptroCommerceDetailViews.swift'), /commerce\.isActiveForViewer/);
  assert.match(read('Screens/CaptroCommerceDetailViews.swift'), /model\.loadCommercePass/);
});
test('legacy visibility is Home-only and pagination retains raw server offsets', () => {
  const feed = read('Screens/MainFeedView.swift');
  assert.match(feed, /model\.posts\.filter \{ !\$0\.isLegacyOrdinaryTextPost \}/);
  assert.match(feed, /pageOffsets\[section\] = skip \+ loaded\.count/);
  assert.match(feed, /isLastVisible/);
  assert.doesNotMatch(read('Screens/ProfileChatVerificationStudio.swift'), /isLegacyOrdinaryTextPost/);
});
test('Story asynchronous results and playback are owned by the selected stable identity', () => {
  const story = read('Screens/DiscoverNativeView.swift');
  assert.match(story, /updateStory\(id: story\.id/);
  assert.match(story, /currentStory\?\.id == story\.id/);
  assert.match(story, /!storyPresentationPaused && scenePhase == \.active/);
  assert.match(story, /guard shouldPlayCurrentStory, resumeStoryAudioAfterInterruption/);
});
