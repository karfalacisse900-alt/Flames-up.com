import test from 'node:test';
import {favoritePlacement} from './helpers/native-ui-contract.mjs';
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
test('legacy text has no Home card or empty Profile tile; stored records remain accessible in an archive', () => {
  const feed = read('Screens/MainFeedView.swift');
  assert.match(feed, /model\.posts\.filter \{ !\$0\.isLegacyOrdinaryTextPost \}/);
  assert.match(feed, /pageOffsets\[section\] = skip \+ loaded\.count/);
  assert.match(feed, /isLastVisible/);
  const profile = read('Screens/ProfileChatVerificationStudio.swift');
  assert.match(profile, /ForEach\(model.posts.filter \{ !\$0.isLegacyOrdinaryTextPost \}\)/);
  assert.match(profile, /CaptroLegacyPostArchive\(posts: model.posts, api: model.api\)/);
  assert.match(profile, /DisclosureGroup\("Earlier posts/);
  assert.match(profile, /PostDetailNativeView\(post: post, api: api\)/);
});

test('media-first composer, Details chrome, and lower Favorites placement do not reintroduce voice or feed scrolling', () => {
  const composer = read('Screens/NotificationLibrarySearchCreateViews.swift');
  assert.match(composer, /composer.addRequiredMedia/);
  assert.match(composer, /if !mediaItems.isEmpty \|\| draft.structured \|\| draft.hasWriting/);
  assert.doesNotMatch(composer, /Record voice attachment|CaptroVoiceRecorder/);
  const detail = read('Screens/PostDetailNativeView.swift');
  assert.doesNotMatch(detail, /reactionRow|reactionLabel|Record voice reply/);
  assert.match(detail, /private var commentsSection/);
  const feed = read('Screens/MainFeedView.swift');
  assert.match(feed, /CaptroFeedPaginationFooter\(/);
  assert.match(read('Components/CaptroFeedPaginationFooter.swift'), /home.pagination.retry/);
  assert.doesNotMatch(feed, /ignoresSafeArea\(\.container, edges: \.bottom\)/);
  favoritePlacement(read('Screens/CaptroFeedMediaPager.swift'));
  const root = read('App/MIRANativeRootView.swift');
  assert.match(root, /configureWithOpaqueBackground/);
  assert.match(root, /tint\(selectedTab == \.scan && cameraDarkChrome \? Color.white : MIRATheme.Color.textPrimary\)/);
  assert.match(root, /toolbarBackground\(selectedTab == \.scan && cameraDarkChrome \? Color.black : MIRATheme.Color.surface, for: \.tabBar\)/);
});
test('Story asynchronous results and playback are owned by the selected stable identity', () => {
  const story = read('Screens/DiscoverNativeView.swift');
  assert.match(story, /updateStory\(id: story\.id/);
  assert.match(story, /currentStory\?\.id == story\.id/);
  assert.match(story, /!storyPresentationPaused && scenePhase == \.active/);
  assert.match(story, /guard shouldPlayCurrentStory, resumeStoryAudioAfterInterruption/);
});
