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
  assert.match(postView, /CaptroEditorialOverlayCard\(content: post\.captroTextOnlyCardContent/);
  assert.doesNotMatch(postView, /CaptroExpandableCaption/);
  assert.doesNotMatch(postView, /CaptroLocationRow/);
  assert.match(mediaPager, /CaptroEditorialOverlayCard\(content: post\.captroEditorialCardContent/);
  assert.match(mediaPager, /CaptroEditorialCardLayout\.width\(for: mediaWidth\)/);
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
  assert.match(mainFeed, /ForEach\(visiblePostIndices, id: \\.self\)/);
  assert.match(
    postView,
    /if !post\.feedMediaURLs\.isEmpty \{\s*mediaPager\s*\} else \{[\s\S]*?CaptroEditorialOverlayCard\(content: post\.captroTextOnlyCardContent/,
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
  assert.match(listing, /MIRATheme\.Color\.like/);
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
  assert.match(textOnly, /CaptroEditorialOverlayCard\(content: post\.captroTextOnlyCardContent/);
  assert.doesNotMatch(textOnly, /Text\(caption\)/);
  assert.match(adapter, /var captroTextOnlyCardContent:[\s\S]*?content\.description = caption/);
});

test('Moment writing stays inside its compact feed card and voice has reserved space', () => {
  assert.match(editorialCard, /content\.type == \.moment/);
  assert.match(editorialCard, /!condensed \|\| content\.type == \.moment \|\| expanded/);
  assert.match(postView, /post\.detail\?\.voice == nil \? 0 : 86/);
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
  const postBodyEnd = postView.indexOf('private var pageMediaSize');
  const postBody = postView.slice(postBodyStart, postBodyEnd);

  assert.ok(postBodyStart >= 0 && postBodyEnd > postBodyStart);
  assert.match(postBody, /\.frame\(maxWidth: \.infinity, alignment: \.topLeading\)/);
  assert.match(postBody, /\.frame\(width: pageSize\.width, height: pageSize\.height, alignment: \.topLeading\)/);
  assert.doesNotMatch(postBody, /\.background\(MIRATheme\.Color\.surface\)/);
  assert.doesNotMatch(postBody, /\.clipShape\(RoundedRectangle|\.cornerRadius\(|\.shadow\(/);
  assert.match(mainFeed, /\.simultaneousGesture\(horizontalPagerGesture\(pageWidth: size\.width\)\)/);
  assert.match(mainFeed, /showsCoverMediaOnly: true/);
});

test('Home media is a full-width rectangular frame using exactly five supported ratios', () => {
  assert.match(mediaPager, /declaredCoverHeightToWidthRatio[\s\S]*?measuredCoverHeightToWidthRatio[\s\S]*?MIRAMediaSizing\.mainFeedDisplayRatio/);
  assert.match(mediaPager, /\.aspectRatio\(CGSize\(width: 1, height: mediaHeightToWidthRatio\), contentMode: \.fit\)/);
  assert.doesNotMatch(mediaPager, /CaptroNaturalMediaLayout/);
  assert.doesNotMatch(mediaPager, /\.aspectRatio\(4\.0 \/ 5\.0/);
  assert.match(mediaPager, /contentMode: \.fill/);
  assert.match(mediaPager, /guard index == 0 else \{ return \}/);
  assert.match(mediaPager, /MIRAMediaSizing\.supportedPostHeightToWidthRatio\(ratio\)/);
  assert.doesNotMatch(mediaPager, /min\(max\(ratio/);
  const mediaBranchStart = postView.indexOf('if !post.feedMediaURLs.isEmpty');
  const mediaBranchEnd = postView.indexOf('} else {', mediaBranchStart);
  const mediaBranch = postView.slice(mediaBranchStart, mediaBranchEnd);
  assert.ok(mediaBranchStart >= 0 && mediaBranchEnd > mediaBranchStart);
  assert.match(mediaBranch, /mediaPager/);
  assert.match(postView, /pager\s*\.frame\(width: mediaSize\.width, height: mediaSize\.height\)/);
  assert.doesNotMatch(mediaBranch, /\.padding\(\.horizontal|mediaHorizontalMargin|RoundedRectangle|cornerRadius/);

  const pagerBodyStart = mediaPager.indexOf('var body: some View');
  const pagerBodyEnd = mediaPager.indexOf('@ViewBuilder');
  const pagerBody = mediaPager.slice(pagerBodyStart, pagerBodyEnd);
  assert.ok(pagerBodyStart >= 0 && pagerBodyEnd > pagerBodyStart);
  assert.match(pagerBody, /\.clipped\(\)[\s\S]*?\.contentShape\(Rectangle\(\)\)/);
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

test('viewport height can crop Home media but never reduce its width', () => {
  const sizing = postView.slice(postView.indexOf('private var pageMediaSize:'), postView.indexOf('private var showsMoreButton:'));
  assert.match(sizing, /CGSize\(width: pageSize\.width, height: min\(availableMediaHeight, pageSize\.width \* ratio\)\)/);
  assert.doesNotMatch(sizing, /availableMediaHeight\s*\/|min\(pageSize\.width/);
  assert.match(postView, /frameSize: pageMediaSize/);
  const fixedFrame = mediaPager.slice(mediaPager.indexOf('if let frameSize {'), mediaPager.indexOf('} else {', mediaPager.indexOf('if let frameSize {')));
  assert.match(fixedFrame, /mediaLayers\.frame\(width: frameSize\.width, height: frameSize\.height\)/);
  assert.doesNotMatch(fixedFrame, /aspectRatio|padding|cornerRadius/);
  assert.match(mainFeed, /feedContent\(size: feedProxy\.size\)\s*\}\s*\.ignoresSafeArea\(\.container, edges: \.horizontal\)/);
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
  assert.match(mediaPager, /CaptroEditorialCardLayout\.width\(for: mediaWidth\)/);
  assert.match(editorialCard, /mediaWidth \* 0\.73/);
  assert.doesNotMatch(composer, /Picker\("Paper style"/);
});

test('holding the Home stamp temporarily reveals the unobstructed photo', () => {
  assert.match(mediaPager, /@GestureState private var isHoldingStamp = false/);
  assert.match(mediaPager, /LongPressGesture\(minimumDuration: 0\.25, maximumDistance: 10\)/);
  assert.match(mediaPager, /\.sequenced\(before: DragGesture\(minimumDistance: 0\)\)/);
  assert.match(mediaPager, /case let \.second\(true, drag\):/);
  assert.match(mediaPager, /hypot\(drag\.translation\.width, drag\.translation\.height\) <= 22/);
  assert.match(
    mediaPager,
    /CaptroEditorialOverlayCard\([\s\S]*?\.contentShape\(Rectangle\(\)\)[\s\S]*?\.opacity\(showsStampOnCurrentSlide && !isHoldingStamp \? 1 : 0\)[\s\S]*?\.allowsHitTesting\(showsStampOnCurrentSlide\)[\s\S]*?\.animation\(stampPeekAnimation, value: isHoldingStamp\)[\s\S]*?\.simultaneousGesture\(stampPeekGesture\)/,
  );
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

test('composer persists the selected stamp and previews the production component', () => {
  assert.match(composer, /@State private var selectedStampKind: CaptroStampKind = \.social/);
  assert.match(composer, /private var stampPickerKinds:[\s\S]*?\[\.social, \.club, \.event, \.meetup, \.deal\]/);
  assert.match(composer, /stampType: hasSelectedStamp \? selectedStampKind\.rawValue : nil/);
  assert.match(composer, /postType: selectedStampKind\.backendPostType/);
  assert.match(composer, /ComposerPreviewSheet\([\s\S]*?stampKind: selectedStampKind/);
  assert.match(composer, /CaptroEditorialOverlayCard\(content: CaptroEditorialCardContent\(draftStamp: previewStampContent\)/);
});

test('post creation matches the simple Photo, Video, Voice composer and keeps media proportions', () => {
  const firstPageStart = composer.indexOf('private var mediaFirstPage');
  const firstPageEnd = composer.indexOf('private func removeMedia(');
  const firstPage = composer.slice(firstPageStart, firstPageEnd);

  assert.ok(firstPageStart >= 0 && firstPageEnd > firstPageStart);
  assert.match(firstPage, /Text\("What's on your mind\?"\)/);
  assert.match(firstPage, /PhotosPicker\([\s\S]*?matching: \.any\(of: \[\.images, \.videos\]\)/);
  assert.match(firstPage, /composerToolLabel\(icon: "photo", title: "Photo"\)/);
  assert.match(firstPage, /composerToolLabel\(icon: "video", title: "Video"\)/);
  assert.match(firstPage, /composerToolLabel\(icon: voiceDraft == nil \? "mic" : "mic\.fill", title: "Voice"\)/);
  assert.match(firstPage, /title: hasSelectedStamp \? stampPickerDetails\(for: selectedStampKind\)\.title : "Add stamp"/);
  assert.match(firstPage, /composerMediaPreview\(first\)[\s\S]*?composerPrompt/);
  assert.match(firstPage, /width \* coverMediaRatio/);
  assert.doesNotMatch(firstPage, /MIRAStoryLiveCameraView/);
  assert.doesNotMatch(firstPage, /Color\.black\.ignoresSafeArea/);
  assert.match(composer, /let remainingSlots = max\(0, 10 - mediaItems\.count\)/);
  assert.match(composer, /mediaDimensions\.append\(await item\.postMediaDimension\(\)\)/);
  assert.match(mediaUpload, /if target == \.feedPost \{[\s\S]*?dimensions = await media\.postMediaDimension\(\)/);
  assert.match(mediaEditorView, /case \.post:[\s\S]*?return \[\.landscape16x9, \.landscape4x3, \.portraitPointSixFive, \.portrait4x5, \.portrait3x4, \.square1x1\]/);
  assert.match(mediaEditor, /case landscape16x9 = "16:9"/);
  assert.match(mediaEditor, /case landscape4x3 = "4:3"/);
  assert.match(mediaEditor, /case portraitPointSixFive = "0\.65:1"/);
  assert.match(mediaEditor, /case square1x1 = "1:1"/);
  assert.match(mediaEditorView, /postAspectRatio: \.nearest\(width: Double\(image\.size\.width\), height: Double\(image\.size\.height\)\)/);
});

test('composer stays on a single writing page with compact tools and an explicit stamp picker', () => {
  const root = composer.slice(composer.indexOf('private var composerPage:'), composer.indexOf('private var postDetailSheetPresentedBinding:'));
  assert.match(root, /mediaFirstPage/);
  assert.doesNotMatch(root, /if isEditingPostDetails|finalPostPage|AnyView/);
  const tool = composer.slice(composer.indexOf('private func composerToolLabel'), composer.indexOf('private func composerVoiceAttachment'));
  assert.match(tool, /Image\(systemName: icon\)/);
  assert.match(tool, /Text\(title\)/);
  assert.match(tool, /accessibilityLabel\(title\)/);
  assert.doesNotMatch(tool, /background\(|clipShape\(/);
  assert.match(composer, /fullScreenCover\(isPresented: \$isEditingPostDetails/);
  assert.match(composer, /fullScreenCover\(isPresented: \$showStampPicker\)/);
  assert.match(composer, /navigationTitle\("Add Stamp"\)/);
  for (const title of ['Moment', 'Club', 'Event', 'Meetup', 'Deal']) {
    assert.match(composer, new RegExp(`case \\.${title === 'Moment' ? 'social' : title.toLowerCase()}: return \\("${title}"`));
  }
  assert.match(composer, /private var stampDetailsPage:[\s\S]*?case \.social:[\s\S]*?case \.club:[\s\S]*?case \.event:[\s\S]*?case \.meetup:[\s\S]*?case \.deal:/);
  assert.match(composer, /accessibilityIdentifier\("post\.option\.\\\(title\)"\)/);
  assert.match(composer, /matching: \.videos/);
  assert.match(composer, /scrollDismissesKeyboard\(\.interactively\)/);
  assert.doesNotMatch(composer, /private var finalPostPage/);
});

test('feed image upload preserves composition and stays within the hosted-image limit', () => {
  assert.match(mediaUpload, /let scale = min\(1, maxSide \/ max\(image\.size\.width, image\.size\.height\)\)/);
  assert.match(mediaUpload, /image\.draw\(in: CGRect\(origin: \.zero, size: targetSize\)\)/);
  assert.match(mediaUpload, /\.first \{ \$0\.count <= 9_500_000 \}/);
  assert.match(mediaUpload, /width: actualWidth,[\s\S]*?height: actualHeight/);
  assert.doesNotMatch(mediaUpload, /let drawOrigin = CGPoint/);
});
