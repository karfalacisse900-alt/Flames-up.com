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

test('Capture Voice opens the AI assistant, not a voice-post recorder', () => {
  assert.match(capture, /hubMode\("Voice", detail: "Talk to Captro"/);
  assert.match(capture, /CaptroCaptureAssistantView\(api: api/);
  assert.doesNotMatch(capture, /CaptroVoiceRecorderSheet|Create voice post|Use text as post caption/);
  assert.match(realtime, /"\/ai\/realtime\/session"/);
  assert.match(realtime, /input_audio_buffer\.append/);
  assert.match(realtime, /input_audio_buffer\.speech_started/);
  assert.match(realtime, /input_audio_buffer\.committed/);
  assert.doesNotMatch(realtime, /"type": "response\.create"/);
  assert.match(realtime, /"create_response": true/);
  assert.match(realtime, /recoverTransport\(\)/);
  assert.match(realtime, /response\.output_audio\.delta/);
  assert.doesNotMatch(assistant, /Send to Captro|Record again|uploadMultipart/);
  assert.doesNotMatch(assistant, /supportsOnDeviceRecognition|SFSpeechRecognizer/);
  assert.match(backend, /api\.post\('\/ai\/realtime\/session', authMiddleware/);
  assert.match(backend, /https:\/\/api\.openai\.com\/v1\/realtime\/client_secrets/);
  assert.match(backend, /semantic_vad/);
  assert.match(realtimeConfig, /create_response: true, interrupt_response: true/);
  assert.match(backend, /store: false/);
  assert.match(backend, /c\.env\.OPENAI_API_KEY/);
  assert.match(backend, /trim_duration_seconds/);
  assert.match(editor, /suggestedPlan\.trimDurationSeconds/);
  assert.match(assistant, /Button\("Done"\)/);
  assert.match(capture, /showingRecordPreview = true/);
});

test('Post Assist uses the same server-side OpenAI key and does not return fake suggestions on failure', () => {
  assert.match(backend, /generatePostAssistWithOpenAI\(c\.env, input, deterministicCategory\)/);
  assert.match(backend, /source: 'openai'/);
  assert.match(backend, /Your draft is safe; try again later/);
});

test('new post text, captions, and comment replies are screened before publication', () => {
  const create = backend.split("api.post('/posts', authMiddleware")[1].split("api.get('/posts/feed'")[0];
  const comments = backend.split("api.post('/posts/:postId/comments', authMiddleware")[1].split("api.get('/posts/:postId/comments'")[0];
  assert.match(create, /screenCaptroText\(c\.env, \[postTitle, postContent\]/);
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

test('Capture Record is new video only and has no gallery route', () => {
  assert.match(capture, /captureMode: \.videoOnly/);
  assert.match(capture, /simpleCaptureUI: true/);
  assert.doesNotMatch(capture, /onGallerySelection:/);
  assert.match(camera, /galleryButton\.isHidden = simpleCaptureUI/);
  assert.match(camera, /guard !simpleCaptureUI else \{ return \}/);
  assert.match(capture, /Button\("Ask Captro"/);
  assert.match(capture, /Button\("Retake"/);
});

test('feed caption overflow uses rendered height instead of character count', () => {
  assert.match(editorial, /CaptroMeasuredCaption/);
  assert.match(editorial, /fullHeight > visibleHeight \+ 1/);
  assert.match(editorial, /\.lineLimit\(maxLines\)/);
  assert.doesNotMatch(read('ios_native/MIRA/Sources/MIRANative/Screens/CaptroFeedPostView.swift'), /caption\.count > 110/);
});
