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
const backend = read('backend-cf/src/index.ts');
const editorial = read('ios_native/MIRA/Sources/MIRANative/Components/CaptroEditorialOverlayCard.swift');

test('Capture Voice opens the AI assistant, not a voice-post recorder', () => {
  assert.match(capture, /hubMode\("Voice", detail: "Talk to Captro"/);
  assert.match(capture, /CaptroCaptureAssistantView\(api: api/);
  assert.doesNotMatch(capture, /CaptroVoiceRecorderSheet|Create voice post|Use text as post caption/);
  assert.match(assistant, /api\.post\("\/ai\/capture-assistant"/);
  assert.match(assistant, /On-device speech recognition|on-device speech recognition/);
  assert.match(backend, /api\.post\('\/ai\/capture-assistant', authMiddleware/);
  assert.match(backend, /store: false/);
  assert.match(backend, /c\.env\.OPENAI_API_KEY/);
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
