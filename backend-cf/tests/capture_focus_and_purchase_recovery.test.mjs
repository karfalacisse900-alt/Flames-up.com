import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { purchaseFailureMessage } from '../src/purchase-errors.ts';
const native = (path) => readFileSync(new URL('../../ios_native/MIRA/Sources/MIRANative/' + path, import.meta.url), 'utf8');
const viewer = native('Screens/DiscoverNativeView.swift').split('struct StoryViewerNativeView: View')[1];
const focus = native('Components/CaptroCaptureFocusView.swift');
test('capture navigation is capture-by-capture and identifies groups by stable ID', () => {
  assert.match(viewer, /onPrevious: goToPreviousStory/);
  assert.match(viewer, /onNext: goToNextStory/);
  assert.match(viewer, /\$0\.id == activeGroup\.id/);
  assert.doesNotMatch(viewer, /\$0\.userId == activeGroup\.userId/);
  assert.doesNotMatch(viewer, /storyProgressValue|private var storyProgress:/);
  assert.match(viewer, /selectedIndex = max\(0, \(groups\[nextIndex\]\.statuses\?\.count/);
});
test('focus chrome does not control player lifetime and details leave media mounted', () => {
  assert.match(focus, /hidden\.toggle\(\)/);
  assert.doesNotMatch(focus, /AVPlayer|\.pause\(|\.id\(hidden\)/);
  assert.match(focus, /maximumDistance: 10/);
  assert.match(viewer, /presentationDetents\(\[\.fraction\(0\.55\)\]\)/);
  assert.match(viewer, /Reply privately/);
  assert.match(viewer, /Report/);
});
test('linked details never confuse attachment IDs and post IDs', () => {
  const details = native('Components/CaptroCaptureDetailsSheet.swift');
  assert.match(details, /if let id = linked\.postId/);
  assert.match(details, /contains\(linked\.type\.lowercased\(\)\) \? linked\.id : nil/);
});
test('purchase recovery identifies ownership, inventory and seller setup without fake success', () => {
  assert.match(purchaseFailureMessage('CAPTRO_CREATOR_CANNOT_PURCHASE'), /You own this item/);
  assert.match(purchaseFailureMessage('CAPTRO_ITEM_EXPIRED'), /expired/);
  assert.match(purchaseFailureMessage('CAPTRO_CAPACITY_REACHED'), /no places left/);
  assert.match(purchaseFailureMessage('CAPTRO_PAYOUTS_NOT_READY'), /seller setup/);
  assert.doesNotMatch(purchaseFailureMessage('sk_live_private'), /sk_live_private/);
});
test('Profile restores payment access and invalid checkout has an explicit error', () => {
  assert.match(native('Screens/ProfileChatVerificationStudio.swift'), /accessibilityLabel: "Payments"/);
  assert.match(native('Screens/CaptroPaymentSheetView.swift'), /Secure checkout could not be verified/);
});
