import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const read = (file) => readFileSync(path.join(root, file), 'utf8');
const capture = read('ios_native/MIRA/Sources/MIRANative/Screens/CaptroScanView.swift');
const camera = read('ios_native/MIRA/Sources/MIRANative/Components/MIRACameraCaptureView.swift');
const assistant = read('ios_native/MIRA/Sources/MIRANative/Screens/CaptroCaptureAssistantView.swift');
const realtime = read('ios_native/MIRA/Sources/MIRANative/Services/CaptroRealtimeVoiceSession.swift');
const backend = read('backend-cf/src/index.ts');
const realtimeConfig = read('backend-cf/src/realtime-session.ts');
const editorial = read('ios_native/MIRA/Sources/MIRANative/Components/CaptroEditorialOverlayCard.swift');
const viewer = read('ios_native/MIRA/Sources/MIRANative/Screens/DiscoverNativeView.swift');
const editor = read('ios_native/MIRA/Sources/MIRANative/Screens/MIRANativeMediaEditorView.swift');

test('Capture opens only the live receipt camera', () => {
  assert.match(capture, /@State private var stage: CaptroReceiptStage = \.capture/);
  assert.match(capture, /CaptroReceiptCameraView\(/);
  assert.doesNotMatch(capture, /CaptroCaptureAssistantView|PhotosPicker|fileImporter|hubMode\(|captureMode: \.videoOnly/);
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

test('ordinary post camera and voice comments remain separate from receipt Capture', () => {
  assert.doesNotMatch(capture, /MIRACameraCaptureView|CaptroVoiceRecorderSheet/);
  assert.match(camera, /galleryButton\.isHidden = simpleCaptureUI/);
  assert.match(camera, /guard !simpleCaptureUI else \{ return \}/);
  assert.match(read('ios_native/MIRA/Sources/MIRANative/Screens/NotificationLibrarySearchCreateViews.swift'), /CaptroVoiceRecorderSheet\(limit: 60\)/);
});

test('feed caption overflow uses rendered height instead of character count', () => {
  assert.match(editorial, /CaptroMeasuredCaption/);
  assert.match(editorial, /fullHeight > visibleHeight \+ 1/);
  assert.match(editorial, /\.lineLimit\(maxLines\)/);
  assert.doesNotMatch(read('ios_native/MIRA/Sources/MIRANative/Screens/CaptroFeedPostView.swift'), /caption\.count > 110/);
});
