import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const readIOS = (path) => readFileSync(
  new URL(`../../ios_native/MIRA/Sources/MIRANative/${path}`, import.meta.url),
  'utf8',
);

const rootView = readIOS('App/MIRANativeRootView.swift');
const mainFeed = readIOS('Screens/MainFeedView.swift');
const postView = readIOS('Screens/CaptroFeedPostView.swift');
const mediaPager = readIOS('Screens/CaptroFeedMediaPager.swift');
const stamps = readIOS('Screens/CaptroFeedPostOverlays.swift');
const composer = readIOS('Screens/NotificationLibrarySearchCreateViews.swift');

test('guest Home reads only the public feed and keeps an isolated cache', () => {
  assert.match(rootView, /isGuest: authSession\.isGuest/);
  assert.match(mainFeed, /private let publicFeedCacheKey = "native\.main\.public\.feed\.v1"/);
  assert.match(mainFeed, /func configureGuestMode\(_ isGuest: Bool\)/);
  assert.match(mainFeed, /if isGuestFeedMode \{[\s\S]*?\/posts\/world-board\?limit=/);
  assert.match(mainFeed, /showsFeedControls: !isGuest/);
  assert.match(mainFeed, /canFollowAuthor: !isGuest/);
});

test('Home post anatomy ends at the photograph and Captro stamp', () => {
  assert.match(postView, /CaptroMediaPager\(/);
  assert.match(postView, /CaptroPostStamp\(content: post\.captroStampContent/);
  assert.doesNotMatch(postView, /CaptroExpandableCaption/);
  assert.doesNotMatch(postView, /CaptroLocationRow/);
  assert.match(mediaPager, /CaptroPostStamp\(/);
  assert.match(mediaPager, /mediaWidth \* 0\.72/);
  assert.doesNotMatch(mediaPager, /CaptroGuideOverlay|CaptroCapturedStamp/);
});

test('Captro uses a purpose-built family of stamp types and actions', () => {
  for (const kind of ['social', 'place', 'club', 'group', 'meetup', 'event', 'deal', 'localOffer']) {
    assert.match(stamps, new RegExp(`case ${kind}(?:\\s|\\s*=)`));
  }
  assert.match(stamps, /case \.club, \.meetup: return "JOIN"/);
  assert.match(stamps, /case \.event: return "ATTEND"/);
  assert.match(stamps, /case \.deal, \.localOffer: return "CLAIM"/);
  assert.match(stamps, /case \.group: return "ACCESS"/);
  assert.match(stamps, /background\(Color\.white\.opacity\(0\.96\)\)/);
  assert.doesNotMatch(stamps, /LinearGradient|Material|ultraThinMaterial/);
});

test('holding Home media temporarily reveals the unobstructed photo', () => {
  assert.match(mediaPager, /@GestureState private var isHoldingPhoto = false/);
  assert.match(mediaPager, /LongPressGesture\(minimumDuration: 0\.25, maximumDistance: 22\)/);
  assert.match(mediaPager, /\.sequenced\(before: DragGesture\(minimumDistance: 0\)\)/);
  assert.match(mediaPager, /case let \.second\(true, drag\):/);
  assert.match(mediaPager, /hypot\(drag\.translation\.width, drag\.translation\.height\) <= 22/);
  assert.match(mediaPager, /\.simultaneousGesture\(stampPeekGesture\)/);
  assert.match(mediaPager, /\.opacity\(isHoldingPhoto \? 0 : 1\)/);
  assert.match(mediaPager, /\.allowsHitTesting\(!isHoldingPhoto\)/);
  assert.match(mediaPager, /\.easeOut\(duration: 0\.11\)/);
  assert.match(mediaPager, /\.easeIn\(duration: 0\.16\)/);
  assert.match(mediaPager, /guard !suppressTapAfterStampPeek else \{ return \}/);
  assert.doesNotMatch(mediaPager, /if !isHoldingPhoto \{[\s\S]*CaptroPostStamp/);
});

test('composer persists the selected stamp and previews the production component', () => {
  assert.match(composer, /@State private var selectedStampKind: CaptroStampKind = \.social/);
  assert.match(composer, /ForEach\(CaptroStampKind\.creationCases\)/);
  assert.match(composer, /postType: selectedStampKind\.backendPostType/);
  assert.match(composer, /ComposerPreviewSheet\([\s\S]*?stampKind: selectedStampKind/);
  assert.match(composer, /CaptroPostStamp\(content: previewStampContent\)/);
});
