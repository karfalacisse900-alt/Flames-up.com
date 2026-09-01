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
const visualFixture = readIOS('Screens/CaptroHomeFeedVisualTestView.swift');
const composer = readIOS('Screens/NotificationLibrarySearchCreateViews.swift');
const mediaSizing = readIOS('Components/MIRAComponents.swift');
const mediaModels = readIOS('Models/MIRAModels.swift');
const mediaUpload = readIOS('Services/MIRAMediaUploadService.swift');

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
  assert.match(mediaPager, /venueReviewStampWidth\(mediaWidth:/);
  assert.match(mediaPager, /guideCoverStampWidth\(mediaWidth:/);
  assert.match(mediaPager, /simplePostStampWidth\(mediaWidth:/);
  assert.doesNotMatch(mediaPager, /CaptroGuideOverlay|CaptroCapturedStamp/);
});

test('Home post is a full-width feed section without an outer card', () => {
  const postBodyStart = postView.indexOf('var body: some View');
  const postBodyEnd = postView.indexOf('private func visibleRatio');
  const postBody = postView.slice(postBodyStart, postBodyEnd);

  assert.ok(postBodyStart >= 0 && postBodyEnd > postBodyStart);
  assert.match(postBody, /\.frame\(maxWidth: \.infinity, alignment: \.topLeading\)/);
  assert.match(postBody, /\.containerRelativeFrame\(\.horizontal, alignment: \.leading\)/);
  assert.doesNotMatch(postBody, /\.background\(MIRATheme\.Color\.surface\)/);
  assert.doesNotMatch(postBody, /\.clipShape\(RoundedRectangle|\.cornerRadius\(|\.shadow\(/);
  assert.match(mainFeed, /LazyVStack\(spacing: 0\)[\s\S]*?\.frame\(maxWidth: \.infinity, alignment: \.leading\)[\s\S]*?\.padding\(\.bottom, 112\)/);
});

test('Home media follows each upload aspect ratio within editorial bounds', () => {
  assert.match(mediaPager, /declaredCoverHeightToWidthRatio[\s\S]*?measuredCoverHeightToWidthRatio[\s\S]*?MIRAMediaSizing\.mainFeedDisplayRatio/);
  assert.match(mediaPager, /CaptroNaturalMediaLayout\(heightToWidthRatio: mediaHeightToWidthRatio\)/);
  assert.match(mediaPager, /CGSize\(width: width, height: width \* heightToWidthRatio\)/);
  assert.doesNotMatch(mediaPager, /\.aspectRatio\(4\.0 \/ 5\.0/);
  assert.match(mediaPager, /contentMode: \.fit/);
  assert.match(mediaPager, /guard index == 0 else \{ return \}/);
  assert.match(mediaPager, /min\(max\(ratio, 9\.0 \/ 16\.0\), 3\.0 \/ 2\.0\)/);
  assert.match(postView, /CaptroMediaPager\([\s\S]*?\.frame\(maxWidth: \.infinity\)[\s\S]*?\.padding\(\.horizontal, 14\)/);

  const screenWidth = 390;
  const mediaWidth = screenWidth - (14 * 2);
  assert.equal(mediaWidth, 362);
  assert.ok(mediaWidth / screenWidth >= 0.92 && mediaWidth / screenWidth <= 0.94);
  assert.equal(Math.round(mediaWidth * (5 / 4)), 453);
  assert.equal(Math.round(mediaWidth), 362);
  assert.equal(Math.round(mediaWidth * (3 / 4)), 272);
  assert.equal(Math.round(mediaWidth * (4 / 3)), 483);
});

test('Captro uses a purpose-built family of stamp types and actions', () => {
  for (const kind of ['social', 'place', 'club', 'group', 'meetup', 'event', 'deal', 'localOffer']) {
    assert.match(stamps, new RegExp(`case ${kind}(?:\\s|\\s*=)`));
  }
  assert.match(stamps, /case \.club, \.meetup: return "JOIN"/);
  assert.match(stamps, /case \.event: return "ATTEND"/);
  assert.match(stamps, /case \.deal, \.localOffer: return "CLAIM"/);
  assert.match(stamps, /case \.group: return "ACCESS"/);
  assert.match(stamps, /background\(Color\.white\)/);
  assert.doesNotMatch(stamps, /LinearGradient|Material|ultraThinMaterial/);
});

test('Home stamps use distinct editorial venue, guide, and simple overlays', () => {
  assert.match(stamps, /private var venueReviewOverlay: some View/);
  assert.match(stamps, /private var guideCoverOverlay: some View/);
  assert.match(stamps, /private var simplePostOverlay: some View/);
  assert.match(stamps, /private var actionPostOverlay: some View/);
  assert.match(stamps, /usesCompactTypography \? 24 : 28/);
  assert.match(stamps, /CaptroStampPalette\.savesPink/);
  assert.match(stamps, /creatorUsername: cleanedCaptroFeedValue\(userUsername\)/);
  assert.match(stamps, /creatorProfileImage: cleanedCaptroFeedValue\(userProfileImage\)/);
  assert.match(stamps, /RoundedRectangle\(cornerRadius: 2[\s\S]*?lineWidth: 1\.25/);
  assert.match(stamps, /RoundedRectangle\(cornerRadius: 1[\s\S]*?lineWidth: 1\.25/);
  assert.doesNotMatch(stamps, /cornerRadius: (?:9|1[0-9]|[2-9][0-9])/);

  assert.match(mediaPager, /case \.place:[\s\S]*?\.padding\(\.leading, 22\)[\s\S]*?\.padding\(\.bottom, mediaURLs\.count > 1 \? 38 : 28\)/);
  assert.match(mediaPager, /case \.guide:[\s\S]*?\.offset\(y: -mediaHeight \* 0\.09\)/);
  assert.match(mediaPager, /CaptroContributorAvatars\([\s\S]*?avatarSize: 34/);
  assert.match(mediaPager, /descriptionLength > 110 \? 0\.72 : \(descriptionLength > 54 \? 0\.68 : 0\.62\)/);
  assert.match(mediaPager, /title\.count > 36 \? 0\.78 : 0\.72/);

  assert.match(visualFixture, /"id": "home-feed-visual-place"/);
  assert.match(visualFixture, /"id": "home-feed-visual-guide"/);
  assert.match(visualFixture, /"id": "home-feed-visual-moment"/);
});

test('holding the Home stamp temporarily reveals the unobstructed photo', () => {
  assert.match(mediaPager, /@GestureState private var isHoldingStamp = false/);
  assert.match(mediaPager, /LongPressGesture\(minimumDuration: 0\.25, maximumDistance: 10\)/);
  assert.match(mediaPager, /\.sequenced\(before: DragGesture\(minimumDistance: 0\)\)/);
  assert.match(mediaPager, /case let \.second\(true, drag\):/);
  assert.match(mediaPager, /hypot\(drag\.translation\.width, drag\.translation\.height\) <= 22/);
  assert.match(
    mediaPager,
    /CaptroPostStamp\([\s\S]*?\.contentShape\(Rectangle\(\)\)[\s\S]*?\.opacity\(isHoldingStamp \? 0 : 1\)[\s\S]*?\.animation\(stampPeekAnimation, value: isHoldingStamp\)[\s\S]*?\.simultaneousGesture\(stampPeekGesture\)/,
  );
  assert.doesNotMatch(
    mediaPager,
    /\.frame\(width: proxy\.size\.width, height: proxy\.size\.height\)\s*\.simultaneousGesture\(stampPeekGesture\)/,
  );
  assert.doesNotMatch(mediaPager, /\.allowsHitTesting\(!isHoldingStamp\)/);
  assert.match(mediaPager, /\.onTapGesture\(perform: openPostUnlessPeeking\)/);
  assert.match(mediaPager, /\.easeOut\(duration: 0\.20\)/);
  assert.match(mediaPager, /\.easeInOut\(duration: 0\.24\)/);
  assert.match(mediaPager, /guard !suppressTapAfterStampPeek else \{ return \}/);
  assert.doesNotMatch(mediaPager, /if !isHoldingStamp \{[\s\S]*CaptroPostStamp/);
});

test('Home carousel locks each touch to horizontal or vertical intent', () => {
  assert.match(mediaPager, /CaptroCarouselDirectionGateInstaller\(\)/);
  assert.match(mediaPager, /CaptroVerticalIntentGestureRecognizer\(threshold: 10\)/);
  assert.match(mediaPager, /verticalDistance >= horizontalDistance \? \.began : \.failed/);
  assert.match(mediaPager, /panGestureRecognizer\.require\(toFail: directionGate\)/);
  assert.match(mediaPager, /scrollView\.isDirectionalLockEnabled = true/);
  assert.match(mediaPager, /shouldRecognizeSimultaneouslyWith/);
  assert.match(mediaPager, /cancelsTouchesInView = false/);
  assert.doesNotMatch(mediaPager, /highPriorityGesture/);
});

test('composer persists the selected stamp and previews the production component', () => {
  assert.match(composer, /@State private var selectedStampKind: CaptroStampKind = \.social/);
  assert.match(composer, /ForEach\(CaptroStampKind\.creationCases\)/);
  assert.match(composer, /postType: selectedStampKind\.backendPostType/);
  assert.match(composer, /ComposerPreviewSheet\([\s\S]*?stampKind: selectedStampKind/);
  assert.match(composer, /CaptroPostStamp\(content: previewStampContent\)/);
});

test('post creation is Photos-first and keeps selected media proportions', () => {
  const firstPageStart = composer.indexOf('private var mediaFirstPage');
  const firstPageEnd = composer.indexOf('private var finalPostPage');
  const firstPage = composer.slice(firstPageStart, firstPageEnd);

  assert.ok(firstPageStart >= 0 && firstPageEnd > firstPageStart);
  assert.match(firstPage, /Text\("What do you want to share\?"\)/);
  assert.match(firstPage, /PhotosPicker\([\s\S]*?matching: \.images/);
  assert.match(firstPage, /title: "Photos"/);
  assert.match(firstPage, /title: "Add Stamp"/);
  assert.match(firstPage, /media\.composerHeightToWidthRatio/);
  assert.doesNotMatch(firstPage, /MIRAStoryLiveCameraView/);
  assert.doesNotMatch(firstPage, /Color\.black\.ignoresSafeArea/);
  assert.match(composer, /let remainingSlots = max\(0, 10 - mediaItems\.count\)/);
});

test('feed uploads preserve image proportions instead of center-cropping', () => {
  assert.match(mediaUpload, /cropMode: "preserve_aspect"/);
  assert.match(mediaUpload, /let scale = min\(1, maxSide \/ max\(image\.size\.width, image\.size\.height\)\)/);
  assert.match(mediaUpload, /image\.draw\(in: CGRect\(origin: \.zero, size: targetSize\)\)/);
  assert.doesNotMatch(mediaUpload, /let drawOrigin = CGPoint/);
});
