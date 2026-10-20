import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const resources = join(root, 'ios_native/MIRA/Sources/MIRANative/Resources/WelcomeAssets.xcassets');
const set = join(resources, 'CaptroWelcomeHero.imageset');
const manifest = JSON.parse(readFileSync(join(set, 'Contents.json')));
assert.equal(manifest.images.length, 1);
assert.equal(manifest.images[0].filename, 'CaptroWelcomeHero.png');
const png = readFileSync(join(set, manifest.images[0].filename));
assert.equal(png.subarray(0, 8).toString('hex'), '89504e470d0a1a0a');
assert.equal(png.readUInt32BE(16), 1254);
assert.equal(png.readUInt32BE(20), 1254);
assert.equal(createHash('sha256').update(png).digest('hex'),
  'f2687645b233f580215387e3b337cc6c2dc11a30f71f9a7052c0f29a748a2fa6',
  'Use the exact supplied illustration, not the full screen reference or a re-encoded image');
const view = readFileSync(join(root, 'ios_native/MIRA/Sources/MIRANative/Screens/CaptroWelcomeView.swift'), 'utf8');
assert.match(view, /sourceSize = CGSize\(width: 1254, height: 1254\)/);
assert.match(view, /CaptroBrandLogo\(\)/);
assert.match(view, /Image\("CaptroWelcomeHero", bundle: \.module\)/);
assert.ok(!view.includes('932.0 / 870.0'), 'Old artwork aspect must not stretch the square replacement');
assert.match(view, /max\(0, width\)\) \/ maximumZoom/);
assert.match(view, /max\(0, height\) \/ \(ratio \* maximumZoom\)/);
assert.match(view, /easeOut\(duration: 0\.6\)/);
assert.match(view, /easeInOut\(duration: 8\)/);
assert.match(view, /guard !hasRevealedArtwork, !reduceMotion/);
console.log('PASS supplied logo-free PNG: exact SHA256, 1254×1254, one hero reference; separate brand asset and preserved motion guards.');
console.log('Static/source checks only. Native layout/unit/UI tests require Xcode; maximum settled 480pt art needs 1440×1440 pixels at 3×.');
