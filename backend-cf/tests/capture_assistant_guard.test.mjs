import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const read = (file) => readFileSync(path.join(root, file), 'utf8');
const capture = read('ios_native/MIRA/Sources/MIRANative/Screens/CaptroCameraNativeView.swift');
const captureService = read('ios_native/MIRA/Sources/MIRANative/Services/CaptroCameraCaptureService.swift');
const rootView = read('ios_native/MIRA/Sources/MIRANative/App/MIRANativeRootView.swift');
const camera = read('ios_native/MIRA/Sources/MIRANative/Components/MIRACameraCaptureView.swift');
const backend = read('backend-cf/src/index.ts');
const realtimeConfig = read('backend-cf/src/realtime-session.ts');
const editorial = read('ios_native/MIRA/Sources/MIRANative/Components/CaptroEditorialOverlayCard.swift');
const viewer = read('ios_native/MIRA/Sources/MIRANative/Screens/DiscoverNativeView.swift');
const editor = read('ios_native/MIRA/Sources/MIRANative/Screens/MIRANativeMediaEditorView.swift');

test('Capture opens the live native camera and does not reintroduce receipt or voice entry points', () => {
  assert.match(rootView, /CaptroCameraNativeView\(api: api, isActive: selectedTab == \.scan\)/);
  assert.match(capture, /@StateObject private var camera = CaptroCameraCaptureService\(\)/);
  assert.match(capture, /CaptroLiveCameraPreview\(session: camera.session/);
  assert.match(captureService, /AVCapturePhotoOutput\(\)/);
  assert.match(captureService, /AVCaptureMovieFileOutput\(\)/);
  assert.doesNotMatch(capture, /CaptroScanView|CaptroReceiptCameraView|CaptroCaptureAssistantView|PhotosPicker|fileImporter|hubMode\(/);
  assert.doesNotMatch(capture, /Looking for documents|Choose photo|Import document|Upload receipt/);
});

test('Post Assist uses the same server-side OpenAI key and does not return fake suggestions on failure', () => {
  assert.match(backend, /generatePostAssistWithOpenAI\(c\.env, input, deterministicCategory\)/);
  assert.match(backend, /source: 'openai'/);
  assert.match(backend, /Your draft is safe; try again later/);
});

test('new post text, captions, and comment replies are screened before publication', () => {
  const create = backend.split("api.post('/posts', authMiddleware")[1].split("api.get('/posts/feed'")[0];
  const comments = backend.split("api.post('/posts/:postId/comments', authMiddleware")[1].split("api.get('/posts/:postId/comments'")[0];
  assert.match(create, /screenCaptroText\(c\.env, \[postTitle, postContent, \.\.\.mediaWriting\.map\(item => item\.writing\.text\)\]/);
  assert.match(create, /TEXT_NEEDS_REVISION/);
  assert.match(create, /TEXT_SCREENING_UNAVAILABLE/);
  assert.match(comments, /surface: parentId \? 'comment_reply' : 'comment'/);
  assert.match(backend, /event: 'text_moderation_decision'/);
  assert.doesNotMatch(backend.split("event: 'text_moderation_decision'")[1].split('return decision')[0], /content: text|input: text/);
});

test('Story viewer and default editor preserve the entire original frame', () => {
  const storyMedia = viewer.split('private var storyMediaLayer: some View')[1].split('private var storyThoughtOverlay')[0];
  assert.match(storyMedia, /contentMode: \.fit/);
  assert.doesNotMatch(storyMedia, /contentMode: \.fill/);
  assert.match(editor, /if mode == \.story \{[\s\S]*?initialAspectRatio = \.original/);
  assert.match(editor, /return \[\.original, \.story9x16/);
});

test('Capture hands reviewed media to existing composers and voice recording remains retired', () => {
  assert.doesNotMatch(capture, /MIRACameraCaptureView|CaptroVoiceRecorderSheet/);
  assert.match(capture, /CreatePostNativeView\(api: api, initialMedia: media/);
  assert.match(capture, /CreateStoryNativeView\(api: api, initialMedia: media/);
  assert.match(capture, /Button\("Retake"\)/);
  assert.match(capture, /Button\(media.kind == \.image \? "Use photo" : "Use video"\)/);
  assert.match(camera, /galleryButton\.isHidden = simpleCaptureUI/);
  assert.match(camera, /guard !simpleCaptureUI else \{ return \}/);
  assert.doesNotMatch(read('ios_native/MIRA/Sources/MIRANative/Screens/NotificationLibrarySearchCreateViews.swift'), /CaptroVoiceRecorderSheet|Record voice attachment|CaptroVoiceUploadService/);
});

test('feed caption overflow uses rendered height instead of character count', () => {
  assert.match(editorial, /CaptroMeasuredCaption/);
  assert.match(editorial, /fullHeight > visibleHeight \+ 1/);
  assert.match(editorial, /\.lineLimit\(maxLines\)/);
  assert.doesNotMatch(read('ios_native/MIRA/Sources/MIRANative/Screens/CaptroFeedPostView.swift'), /caption\.count > 110/);
});
