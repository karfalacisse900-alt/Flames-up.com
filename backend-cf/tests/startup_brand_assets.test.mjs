import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const read = file => readFileSync(new URL('../../' + file, import.meta.url), 'utf8');
const assets = 'ios_native/MIRA/AppTarget/Assets.xcassets/';
const original = read('captro-site/brand/captro-lockup-black.svg').trim();
const paths = svg => [...svg.matchAll(/<path\b[^>]*\bd="([^"]+)"/g)].map(m => m[1]);
const readAsset = name => read(assets + 'CaptroStartup' + name + '.imageset/logo.svg').trim();
function validate(parts) {
  assert.equal(parts.lockup, original, 'The static full lockup must remain the supplied original');
  assert.deepEqual([...paths(parts.upper), ...paths(parts.lower), ...paths(parts.wordmark)], paths(original));
  for (const part of Object.values(parts)) {
    assert.match(part, /viewBox="0 0 1000 260"/);
    assert.doesNotMatch(part, /<text|<image|https?:\/\/(?!www\.w3\.org)/);
  }
  for (const curve of [parts.upper, parts.lower]) assert.match(curve, /translate\(28 65\) scale\(\.7\)/);
  const wordmarkGroup = original.match(/<g fill="#000000" transform="translate\(300 180\)[\s\S]*?<\/g>/)[0];
  assert.ok(parts.wordmark.includes(wordmarkGroup), 'Preserve every original letter transform as well as its path');
}
test('startup uses exact supplied curves and outlined lettering at the original transform', () => {
  const parts = Object.fromEntries(['Lockup','Upper','Lower','Wordmark'].map(n => [n.toLowerCase(), readAsset(n)]));
  validate(parts);
  assert.throws(() => validate({ ...parts, upper: parts.upper.replace('M50 76', 'M51 76') }));
  assert.throws(() => validate({ ...parts, wordmark: parts.wordmark.replace('scale(.215 -.215)', 'scale(.2 -.215)') }));
  for (const name of ['Lockup','Upper','Lower','Wordmark']) {
    const manifest = JSON.parse(read(assets + 'CaptroStartup' + name + '.imageset/Contents.json'));
    assert.equal(manifest.properties['preserves-vector-representation'], true);
    assert.equal(manifest.properties['template-rendering-intent'], 'template');
  }
});
test('static launch and native overlay share center, background and exact lockup dimensions', () => {
  const screen = read('ios_native/MIRA/AppTarget/LaunchScreen.storyboard');
  const native = read('ios_native/MIRA/Sources/MIRANative/App/MIRANativeRootView.swift').split('private struct CaptroStartupView')[1];
  assert.match(screen, /firstAttribute="centerX" secondItem="launch-root"/);
  assert.match(screen, /firstAttribute="centerY" secondItem="launch-root"/);
  assert.match(screen, /firstAttribute="width" constant="292"/);
  assert.match(screen, /firstAttribute="height" constant="75.92"/);
  assert.match(screen, /alpha="0.14"/);
  assert.match(native, /frame\(width: 292, height: 75\.92\)/);
  assert.match(native, /Color\("MIRALaunchBackground", bundle: \.main\)/);
  assert.match(native, /accessibilityHidden\(true\)/);
  assert.doesNotMatch(native, /TimelineView|repeatForever|Font\.custom|Text\("captro"\)/);
});
