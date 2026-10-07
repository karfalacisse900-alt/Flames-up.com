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
const editorialCard = readIOS('Components/CaptroEditorialOverlayCard.swift');
const mediaStamp = readIOS('Components/CaptroFeedMediaStamp.swift');
const composer = readIOS('Screens/NotificationLibrarySearchCreateViews.swift');
const mediaSizing = readIOS('Components/MIRAComponents.swift');
const mediaModels = readIOS('Models/MIRAModels.swift');
const mediaUpload = readIOS('Services/MIRAMediaUploadService.swift');
const mediaEditor = readIOS('Services/MIRANativeMediaEditor.swift');
const mediaEditorView = readIOS('Screens/MIRANativeMediaEditorView.swift');
const worker = readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8');

test('guest Home reads only the public feed and keeps an isolated cache', () => {
  assert.match(rootView, /isGuest: authSession\.isGuest/);
  assert.match(mainFeed, /private let publicFeedCacheKey = "native\.main\.public\.feed\.v1"/);
  assert.match(mainFeed, /func configureGuestMode\(_ isGuest: Bool\)/);
  assert.match(mainFeed, /if isGuestFeedMode \{[\s\S]*?\/posts\/world-board\?limit=/);
  assert.match(mainFeed, /showsFeedControls: false/);
  assert.match(mainFeed, /canFollowAuthor: !isGuest/);
});

test('Home post anatomy ends at the photograph and Captro stamp', () => {
  assert.match(postView, /CaptroMediaPager\(/);
  assert.match(postView, /CaptroTextOnlyStampCard\(post: post/);
  assert.doesNotMatch(postView, /CaptroExpandableCaption/);
  assert.doesNotMatch(postView, /CaptroLocationRow/);
  assert.match(mediaPager, /CaptroFeedMediaStamp\(content: post\.captroMediaFeedCardContent/);
  assert.match(mediaStamp, /mediaWidth \* \(accessibility \? 0\.90 : 0\.73\)/);
  assert.doesNotMatch(mediaPager, /CaptroPostStamp\(/);
  assert.doesNotMatch(mediaPager, /CaptroGuideOverlay|CaptroCapturedStamp/);
});

test('Home keeps text, note, image, and video posts in the same feed', () => {
  assert.doesNotMatch(mainFeed, /photoFeedPosts/);
  assert.match(mainFeed, /let sorted = await sortedByNativeScore\(loaded\)/);
  assert.match(mainFeed, /interleavePostFormats\(merged\)/);
  assert.match(mainFeed, /let mediaPosts = rankedPosts\.filter \{ !\$0\.feedMediaURLs\.isEmpty \}/);
  assert.match(mainFeed, /let textPosts = rankedPosts\.filter \{ \$0\.feedMediaURLs\.isEmpty \}/);
  assert.match(mainFeed, /wantsMedia\.toggle\(\)/);
  assert.match(mainFeed, /loaded = try await fetchFeedPage\(skip: skip\)/);
  assert.match(mainFeed, /ForEach\(displayedPosts, id: \\.id\)/);
  assert.match(
    postView,
    /if !post\.feedMediaURLs\.isEmpty \{\s*mediaPager\s*\} else \{[\s\S]*?textOnlyStamp\(maxBodyLines: 3\)/,
  );

  const readStart = worker.indexOf('async function supabaseReadVisiblePosts');
  const readEnd = worker.indexOf('function postgrestInFilter', readStart);
  const readVisiblePosts = worker.slice(readStart, readEnd);
  assert.ok(readStart >= 0 && readEnd > readStart);
  assert.match(readVisiblePosts, /const photoOnly = options\.photoOnly === true \|\| isDiscoverQuery/);
  assert.match(readVisiblePosts, /photoOnly \? feedPhotoPostsOnly\(ordered\) : ordered/);

  const homeStart = worker.indexOf("api.get('/posts/feed'");
  const homeEnd = worker.indexOf("api.get('/posts/world-board'", homeStart);
  const homeRoute = worker.slice(homeStart, homeEnd);
  assert.ok(homeStart >= 0 && homeEnd > homeStart);
  assert.doesNotMatch(homeRoute, /photoOnly:\s*true/);
});

test('Event, Meetup and Deal use one restrained listing hierarchy without changing Moment', () => {
  const listing = editorialCard.slice(
    editorialCard.indexOf('private var listingCard'),
    editorialCard.indexOf('private var legacyCard'),
  );
  const fields = ['content.headline', 'content.scheduleText', 'content.priceText',
    'content.locationText', 'content.summaryText'];
  let previous = -1;
  for (const field of fields) {
    const position = listing.indexOf(field);
    assert.ok(position > previous, field + ' must follow the editorial hierarchy');
    previous = position;
  }
  assert.match(editorialCard, /if \[\.event, \.meetup, \.deal\]\.contains\(content\.type\)/);
  assert.match(editorialCard, /else \{\s*legacyCard/);
  assert.match(listing, /MIRATheme\.Color\.forest/);
  assert.match(listing, /MIRATheme\.Color\.surface/);
  assert.doesNotMatch(listing, /Color\.white|Color\.black/);
  assert.doesNotMatch(listing, /chipPink|LinearGradient|\.shadow\(/);
  const adapter = readIOS('Models/CaptroEditorialCardAdapter.swift');
  assert.match(adapter, /commerce\?\.scheduleLabel/);
  assert.match(adapter, /commerce\?\.resolvedLowestPrice\?\.stampPrice/);
  assert.match(adapter, /redemptionRules/);
  assert.match(adapter, /Full qualifying conditions in details/);
});
test('Moment detail keeps writing on one editorial card without a separate caption', () => {
  const detail = readIOS('Screens/CaptroPostDetailSections.swift');
  const commerce = readIOS('Screens/CaptroCommerceDetailViews.swift');
  const adapter = readIOS('Models/CaptroEditorialCardAdapter.swift');
  const momentDetail = detail.slice(detail.indexOf('private var regularPost'), detail.indexOf('private var eventPost'));
  assert.match(momentDetail, /CaptroEditorialOverlayCard\(content: post\.captroEditorialCardContent/);
  assert.match(momentDetail, /expanded: true, showsProfileRow: false/);
  assert.doesNotMatch(momentDetail, /fullDescription/);
  assert.doesNotMatch(commerce, /CaptroEditorialOverlayCard\(/);
  const textOnly = postView.slice(postView.indexOf('if !post.feedMediaURLs.isEmpty'), postView.indexOf('if let voice = post.detail?.voice'));
  assert.match(textOnly, /textOnlyStamp\(maxBodyLines: 3\)/);
  assert.match(postView, /let content = post\.captroTextOnlyCardContent/);
  assert.doesNotMatch(textOnly, /Text\(caption\)/);
  assert.match(adapter, /var captroTextOnlyCardContent:[\s\S]*?content\.description = caption/);
});

test('Moment writing and real audio controls stay inside the Stamp surface', () => {
  assert.match(editorialCard, /content\.type == \.moment/);
  assert.match(editorialCard, /!condensed \|\| content\.type == \.moment \|\| expanded/);
  assert.match(postView, /CaptroStampAudio\(post: post, api: api, isActive:/);
  assert.match(mediaPager, /CaptroStampAudio\(post: post, api: api, isActive:/);
  const audio = readIOS('Components/CaptroStampAudio.swift');
  assert.match(audio, /CaptroCompactVoicePlayer/);
  assert.match(audio, /music\/audius\/stream/);
  const profile = readIOS('Screens/ProfileChatVerificationStudio.swift');
  assert.doesNotMatch(profile, /ProfileToolbarDestinationButton\(destination: \.bookmarks/);
});

test('Home preview omits the separate creator and location header', () => {
  const contentStart = postView.indexOf('private var postContent');
  const contentEnd = postView.indexOf('@ViewBuilder', contentStart);
  const content = postView.slice(contentStart, contentEnd);
  assert.ok(contentStart >= 0 && contentEnd > contentStart);
  assert.doesNotMatch(content, /CaptroAuthorHeader|captroFeedHeaderLocation/);
});

test('Home post is a full-width feed section without an outer card', () => {
  const postBodyStart = postView.indexOf('var body: some View');
  const postBodyEnd = postView.indexOf('private var mediaSize');
  const postBody = postView.slice(postBodyStart, postBodyEnd);

  assert.ok(postBodyStart >= 0 && postBodyEnd > postBodyStart);
  assert.match(postBody, /\.frame\(maxWidth: \.infinity, alignment: \.topLeading\)/);
  assert.doesNotMatch(postBody, /pageSize|UIScreen\.main\.bounds|frame\(.*height:.*viewport/);
  assert.doesNotMatch(postBody, /\.background\(MIRATheme\.Color\.surface\)/);
  assert.doesNotMatch(postBody, /\.clipShape\(RoundedRectangle|\.cornerRadius\(|\.shadow\(/);
  assert.doesNotMatch(mainFeed, /\.scrollTargetBehavior\(\.paging\)|horizontalPostPager/);
  assert.match(mainFeed, /\.scrollPosition\(id: \$selectedPostID, anchor: \.top\)/);
  assert.match(postView, /showsCoverMediaOnly: false/);
  assert.match(mainFeed, /LazyVStack\(spacing: 12\)/);
  assert.match(mainFeed, /safeAreaPadding\(\.bottom, bottomInset \+ 12\)/);
});

test('Home media preserves every supported source ratio inside the rectangular viewport', () => {
  assert.match(mediaPager, /declaredCoverHeightToWidthRatio[\s\S]*?MIRAMediaSizing\.mainFeedDisplayRatio/);
  assert.doesNotMatch(mediaPager, /measuredCoverHeightToWidthRatio|onMeasuredRatio:/);
  assert.match(mediaPager, /\.aspectRatio\(CGSize\(width: 1, height: mediaHeightToWidthRatio\), contentMode: \.fit\)/);
  assert.doesNotMatch(mediaPager, /CaptroNaturalMediaLayout/);
  assert.doesNotMatch(mediaPager, /\.aspectRatio\(4\.0 \/ 5\.0/);
  assert.match(mediaPager, /contentMode: \.fit/);
  assert.doesNotMatch(mediaPager, /contentMode: \.fill/);
  assert.match(mediaPager, /MIRAMediaSizing\.supportedPostHeightToWidthRatio\(ratio\)/);
  assert.doesNotMatch(mediaPager, /min\(max\(ratio/);
  const mediaBranchStart = postView.indexOf('if !post.feedMediaURLs.isEmpty');
  const mediaBranchEnd = postView.indexOf('} else {', mediaBranchStart);
  const mediaBranch = postView.slice(mediaBranchStart, mediaBranchEnd);
  assert.ok(mediaBranchStart >= 0 && mediaBranchEnd > mediaBranchStart);
  assert.match(mediaBranch, /mediaPager/);
  assert.match(postView, /pager\s*\.frame\(width: mediaSize\.width\)/);
  assert.match(mediaPager, /mediaLayers\.frame\(width: frameSize\.width, height: frameSize\.height\)/);
  assert.doesNotMatch(mediaBranch, /\.padding\(\.horizontal|mediaHorizontalMargin|RoundedRectangle|cornerRadius/);

  const pagerBodyStart = mediaPager.indexOf('var body: some View');
  const pagerBodyEnd = mediaPager.indexOf('@ViewBuilder');
  const pagerBody = mediaPager.slice(pagerBodyStart, pagerBodyEnd);
  assert.ok(pagerBodyStart >= 0 && pagerBodyEnd > pagerBodyStart);
  assert.doesNotMatch(pagerBody, /\.clipped\(\)/, 'Real stamp continuation must not be clipped to media');
  assert.match(mediaPager, /mediaLayers\.frame\(width: frameSize\.width, height: frameSize\.height\)\.clipped\(\)/);
  assert.doesNotMatch(pagerBody, /RoundedRectangle|mediaPlaceholder|cornerRadius/);

  const screenWidth = 390;
  const mediaWidth = screenWidth;
  assert.equal(mediaWidth / screenWidth, 1);
  assert.equal(Math.round(mediaWidth * (3 / 4)), 293);
  assert.equal(Math.round(mediaWidth * (1536 / 999)), 600);
  assert.equal(Math.round(mediaWidth * (5 / 4)), 488);
  assert.equal(Math.round(mediaWidth * (4 / 3)), 520);
  assert.equal(Math.round(mediaWidth), 390);

  const swiftRatioStart = mediaModels.indexOf('public enum MIRASupportedPostAspectRatio');
  const swiftRatioEnd = mediaModels.indexOf('public struct MIRAMediaDimension', swiftRatioStart);
  const swiftRatios = mediaModels.slice(swiftRatioStart, swiftRatioEnd);
  assert.ok(swiftRatioStart >= 0 && swiftRatioEnd > swiftRatioStart);
  const expectedRatios = ['16:9', '4:3', '0.65:1', '4:5', '3:4', '1:1'];
  const swiftRatioValues = [...swiftRatios.matchAll(/case\s+\w+\s*=\s*"([^"]+)"/g)].map((match) => match[1]);
  assert.deepEqual(swiftRatioValues, expectedRatios);
  assert.doesNotMatch(swiftRatios, /2:3|1620/);

  const workerRatioStart = worker.indexOf('const SUPPORTED_FEED_MEDIA_RATIOS');
  const workerRatioEnd = worker.indexOf('function supportedFeedMediaVariant', workerRatioStart);
  const workerRatios = worker.slice(workerRatioStart, workerRatioEnd);
  assert.ok(workerRatioStart >= 0 && workerRatioEnd > workerRatioStart);
  const workerRatioValues = [...workerRatios.matchAll(/format:\s*'([^']+)'/g)].map((match) => match[1]);
  assert.deepEqual(workerRatioValues, expectedRatios);
  assert.match(workerRatios, /'4:3'[\s\S]*?1440[\s\S]*?1080/);
  assert.match(workerRatios, /'16:9'[\s\S]*?1920[\s\S]*?1080/);
  assert.match(workerRatios, /'0\.65:1'[\s\S]*?999[\s\S]*?1536/);
  assert.match(workerRatios, /'4:5'[\s\S]*?1080[\s\S]*?1350/);
  assert.match(workerRatios, /'3:4'[\s\S]*?1080[\s\S]*?1440/);
  assert.match(workerRatios, /'1:1'[\s\S]*?1080[\s\S]*?1080/);
  assert.doesNotMatch(workerRatios, /'2:3'|1620/);
  assert.match(mediaSizing, /supportedPostHeightToWidthRatios:[\s\S]*?feedWideLandscapeRatio[\s\S]*?feedLandscapeRatio[\s\S]*?feedTallPortraitRatio[\s\S]*?feedShortPortraitRatio[\s\S]*?feedPreviewRatio[\s\S]*?feedSquareRatio/);
  assert.match(mediaModels, /public var heightToWidthRatio:[\s\S]*?MIRASupportedPostAspectRatio\.from\(format: format\)[\s\S]*?feedWidth[\s\S]*?originalWidth/);
  assert.match(worker, /const explicit = SUPPORTED_FEED_MEDIA_RATIOS\.find[\s\S]*?if \(explicit\) return explicit;/);
});

test('media canvas is metadata-sized without a separate More row or viewport height', () => {
  const sizing = postView.slice(postView.indexOf('private var mediaSize:'), postView.indexOf('private struct CaptroTextOnlyStampCard'));
  assert.match(sizing, /MIRAMediaSizing\.mainFeedDisplayRatio/);
  assert.match(sizing, /height: feedWidth \* ratio/);
  assert.doesNotMatch(postView, /showsMoreButton|Button\("More"|fixedVerticalContent/);
  assert.doesNotMatch(sizing, /availableMediaHeight\s*\/|min\(pageSize\.width/);
  assert.match(postView, /frameSize: mediaSize/);
  const fixedFrame = mediaPager.slice(mediaPager.indexOf('if let frameSize {'), mediaPager.indexOf('} else {', mediaPager.indexOf('if let frameSize {')));
  assert.match(fixedFrame, /mediaLayers\.frame\(width: frameSize\.width, height: frameSize\.height\)/);
  assert.doesNotMatch(fixedFrame, /aspectRatio|padding|cornerRadius/);
  assert.match(mainFeed, /feedContent\(size: feedProxy\.size, bottomInset: feedProxy\.safeAreaInsets\.bottom\)/);
});

test('Captro uses a purpose-built family of stamp types and actions', () => {
  for (const kind of ['social', 'place', 'club', 'group', 'meetup', 'event', 'deal', 'localOffer']) {
    assert.match(stamps, new RegExp(`case ${kind}(?:\\s|\\s*=)`));
  }
  assert.match(stamps, /case \.club, \.meetup: return "JOIN"/);
  assert.match(stamps, /case \.event: return "ATTEND"/);
  assert.match(stamps, /case \.deal, \.localOffer: return "CLAIM"/);
  assert.match(stamps, /case \.group: return "ACCESS"/);
  assert.match(editorialCard, /Button\(action: onOpen\)/);
  assert.doesNotMatch(editorialCard, /Button\(action: onAction\)|Button\(action: onSave\)/);
  assert.doesNotMatch(stamps, /LinearGradient|Material|ultraThinMaterial/);
  assert.doesNotMatch(mediaPager, /feedStamp\(lines:|min\(280, max\(68/);
  assert.match(mediaStamp, /ViewThatFits\(in: \.vertical\)/);
  assert.match(mediaStamp, /card\(captionLines: nil, readingAction: nil\)/);
  assert.match(mediaStamp, /card\(captionLines: 6, readingAction: "Read more"\)/);
  assert.match(mediaStamp, /card\(captionLines: nil, readingAction: "Show less"\)/);
  assert.match(mediaStamp, /reading\.expanded\.toggle\(\)/);
  assert.match(mediaStamp, /stamp\.y \+ stamp\.size\.height \+ 12/);
  assert.match(mainFeed, /stampReadingStates\[post.id\]/);
  assert.match(editorialCard, /mediaWidth \* 0\.73/);
  assert.doesNotMatch(composer, /Picker\("Paper style"/);
});

test('holding the Home stamp temporarily reveals the unobstructed photo', () => {
  assert.match(mediaPager, /@State private var isHoldingStamp = false/);
  assert.match(mediaPager, /gesture\.minimumPressDuration = 0\.25/);
  assert.match(mediaPager, /gesture\.allowableMovement = 10/);
  assert.match(mediaPager, /gesture\.cancelsTouchesInView = false/);
  assert.doesNotMatch(mediaPager, /\.sequenced\(before: DragGesture/);
  assert.match(mediaPager, /gesture\.state == \.began \|\| gesture\.state == \.changed/);
  assert.match(
    mediaPager,
    /\.opacity\(showsStampOnCurrentSlide && !isHoldingStamp \? 1 : 0\)[\s\S]*?\.allowsHitTesting\(showsStampOnCurrentSlide\)[\s\S]*?\.animation\(stampPeekAnimation, value: isHoldingStamp\)/,
  );
  const visibleStamp = mediaPager.slice(mediaPager.indexOf('private func feedStamp('), mediaPager.indexOf('private var stampPeekAnimation'));
  assert.match(visibleStamp, /CaptroStampPeekGesture\(isHolding: \$isHoldingStamp\)/);
  const overlay = mediaPager.slice(mediaPager.indexOf('private func overlayContent('), mediaPager.indexOf('private func feedStamp('));
  assert.doesNotMatch(overlay, /\.contentShape\(Rectangle\(\)\)|\.simultaneousGesture\(stampPeekGesture\)/,
    'The transparent stamp height budget must not capture media taps or paging');
  assert.doesNotMatch(
    mediaPager,
    /\.frame\(width: proxy\.size\.width, height: proxy\.size\.height\)\s*\.simultaneousGesture\(stampPeekGesture\)/,
  );
  assert.doesNotMatch(mediaPager, /\.allowsHitTesting\(!isHoldingStamp\)/);
  assert.match(mediaPager, /\.onTapGesture\(perform: handleMediaTap\)/);
  assert.match(mediaPager, /private func handleMediaTap\(\) \{\s*guard !suppressTapAfterStampPeek/);
  assert.match(mediaPager, /\.easeOut\(duration: 0\.20\)/);
  assert.match(mediaPager, /\.easeInOut\(duration: 0\.24\)/);
  assert.match(mediaPager, /guard !suppressTapAfterStampPeek else \{ return \}/);
  assert.doesNotMatch(mediaPager, /if !isHoldingStamp \{[\s\S]*CaptroPostStamp/);
});

test('Home carousel stamp appears only on its first slide', () => {
  assert.match(mediaPager, /private var showsStampOnCurrentSlide: Bool \{[\s\S]*?selectedMediaIndex == 0[\s\S]*?\}/);
  assert.match(mediaPager, /\.opacity\(showsStampOnCurrentSlide && !isHoldingStamp \? 1 : 0\)/);
  assert.match(mediaPager, /\.allowsHitTesting\(showsStampOnCurrentSlide\)/);
  assert.match(mediaPager, /\.accessibilityHidden\(!showsStampOnCurrentSlide\)/);
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

test('composer persists one draft and hides structured setup behind the intent selector', () => {
  assert.match(composer, /@State private var draft = CaptroCompositionDraft/);
  assert.match(composer, /creationIntent: draft\.intent\.rawValue/);
  assert.match(composer, /stampType: hasSelectedStamp \? selectedStampKind\.rawValue : nil/);
  assert.match(composer, /postType: selectedStampKind\.backendPostType/);
  assert.match(composer, /private var stampPickerKinds:[\s\S]*?\[\.club, \.event, \.meetup, \.deal\]\.filter/);
  assert.match(composer, /creationCapabilities\?\.structuredTypes\.contains/);
  assert.match(composer, /fullScreenCover\(isPresented: presentationBinding\(\.structured\)/);
});

test('single-card creation preserves native mixed-media picking and original proportions', () => {
  const card = composer.slice(composer.indexOf('private var compositionCard'), composer.indexOf('private var intentSelector'));
  assert.match(card, /CaptroCompositionTextView\(text: \$draft\.bodyText/);
  assert.match(card, /compositionAttachments/);
  assert.doesNotMatch(card, /TextField\(|TextEditor\(|CaptroEditorialOverlayCard/);
  assert.match(composer, /photosPicker\([\s\S]*?matching: \.any\(of: \[\.images, \.videos\]\)/);
  assert.match(composer, /fitsOriginal: true/);
  assert.match(composer, /let remainingSlots = max\(0, 10 - mediaItems\.count\)/);
  assert.match(composer, /mediaDimensions\.append\(await item\.postMediaDimension\(\)\)/);
  assert.match(mediaUpload, /if target == \.feedPost \{[\s\S]*?dimensions = await media\.postMediaDimension\(\)/);
  assert.match(mediaEditorView, /case \.post:[\s\S]*?return \[\.landscape16x9, \.landscape4x3, \.portraitPointSixFive, \.portrait4x5, \.portrait3x4, \.square1x1\]/);
});

test('composer exposes quiet tools, native actions, and no Post category', () => {
  const canvas = composer.slice(composer.indexOf('private var mediaFirstPage:'), composer.indexOf('private var stampDetailsPage:'));
  assert.match(canvas, /Label\("Add", systemImage: "plus.circle"\)/);
  assert.match(canvas, /accessibilityLabel\("Record voice attachment"\)/);
  assert.match(composer, /ToolbarItem\(placement: \.confirmationAction\)/);
  assert.match(composer, /Text\("Create"\)/);
  assert.match(canvas, /ForEach\(CaptroWritingIntent\.allCases\)/);
  assert.doesNotMatch(canvas, /Text\("Post"\)|Text\("Create Post"\)|composerToolLabel|shadow\(|LinearGradient/);
  assert.match(canvas, /scrollDismissesKeyboard\(\.(interactively|immediately)\)/);
});

test('feed image upload preserves composition and stays within the hosted-image limit', () => {
  assert.match(mediaUpload, /let scale = min\(1, maxSide \/ max\(image\.size\.width, image\.size\.height\)\)/);
  assert.match(mediaUpload, /image\.draw\(in: CGRect\(origin: \.zero, size: targetSize\)\)/);
  assert.match(mediaUpload, /\.first \{ \$0\.count <= 9_500_000 \}/);
  assert.match(mediaUpload, /width: actualWidth,[\s\S]*?height: actualHeight/);
  assert.doesNotMatch(mediaUpload, /let drawOrigin = CGPoint/);
});

test('composer selectors use one lifecycle owner and flat content-sized sheets', () => {
  const intent = composer.slice(composer.indexOf('private var intentSelector'), composer.indexOf('private func compositionChip'));
  const audience = composer.slice(composer.indexOf('private var audiencePicker'), composer.indexOf('private var timePicker'));
  assert.doesNotMatch(intent, /Menu\s*\{/);
  assert.match(intent, /CaptroSelectionSheet\(title:/);
  assert.match(intent, /More ways to create/);
  assert.match(audience, /CaptroSelectionSheet\(title: "Audience"/);
  assert.doesNotMatch(audience, /List\s*\{|listStyle|UserDefaults/);
  assert.match(composer, /sheet\(item: selectionPresentationBinding, onDismiss:/);
  assert.match(composer, /queuedPresentation = nil; openPresentation\(next\)/);
});

test('time directly edits its optional value and Maps search never requests device location on entry', () => {
  const time = composer.slice(composer.indexOf('private var timePicker'), composer.indexOf('private var hasUnsavedPost'));
  const location = composer.slice(composer.indexOf('private struct PostLocationPickerSheet'), composer.indexOf('private struct PostPeopleTagSheet'));
  assert.match(time, /datePickerStyle\(\.wheel\)/);
  assert.match(time, /Button\("Save"\)/);
  assert.match(time, /Button\("Cancel"\)/);
  assert.match(location, /MKLocalSearch\(request:/);
  assert.match(location, /clean == cleanQuery/);
  assert.match(location, /withTaskCancellationHandler/);
  assert.doesNotMatch(location, /requestWhenInUseAuthorization|requestLocation|decorative|MIRAEmptyState|Map\(/);
});

test('native Story presentation has no extra canvas fade or delayed dismissal', () => {
  const stories = readIOS('Screens/DiscoverNativeView.swift');
  assert.doesNotMatch(stories, /isCanvasVisible/);
  const start = stories.indexOf('private func closeStoryViewer');
  const close = stories.slice(start, stories.indexOf('private func goToPreviousStory', start));
  assert.match(close, /onClose\(\)/);
  assert.doesNotMatch(close, /asyncAfter|withAnimation|opacity/);
});

test('Stamp audio belongs to the visible post, not only to video activation', () => {
  assert.match(mainFeed, /isPostActive: isCurrent && !isMediaPlaybackSuppressed/);
  assert.match(postView, /isActive: isPostActive/);
  assert.match(postView, /isAudioActive: isPostActive/);
  assert.match(mediaPager, /CaptroStampAudio\(post: post, api: api, isActive: isAudioActive\)/);
  const audio = readIOS('Components/CaptroStampAudio.swift');
  assert.match(audio, /onChange\(of: isActive\)/);
  assert.match(audio, /activeId == voice.id/);
});
