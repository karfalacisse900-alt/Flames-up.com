import {readFileSync,readdirSync} from 'node:fs';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {resolve,join} from 'node:path';
const root=fileURLToPath(new URL('../',import.meta.url));
const catalog=join(root,'ios_native/MIRA/AppTarget/Assets.xcassets');
const icon=readFileSync(join(catalog,'AppIcon.appiconset/AppIcon-1024.png'));
assert.equal(icon.subarray(0,8).toString('hex'),'89504e470d0a1a0a');
assert.equal(icon.readUInt32BE(16),1024);assert.equal(icon.readUInt32BE(20),1024);
assert.equal(icon[24],8);assert.equal(icon[25],2,'Opaque RGB PNG, no alpha channel');
assert.equal(createHash('sha256').update(icon).digest('hex'),'375806c16a5753d86600396773445db3b6db1f7c95cb46a73b8e164c4fc975d5');
const appIcons=readdirSync(catalog).filter(n=>n.endsWith('.appiconset'));
assert.deepEqual(appIcons,['AppIcon.appiconset']);
for(const set of ['AppIcon.appiconset','CaptroLaunchLogo.imageset','CaptroBrandWhite.imageset']) {
 const json=JSON.parse(readFileSync(join(catalog,set,'Contents.json')));
 for(const image of json.images) if(image.filename) assert.ok(readFileSync(join(catalog,set,image.filename)).length>0);
}
for(const color of ['black','white']) {
 const set=color==='black'?'CaptroLaunchLogo':'CaptroBrandWhite';
 const png=readFileSync(join(catalog,`${set}.imageset/captro-lockup-${color}.png`));
 assert.equal(png.readUInt32BE(16),2400);assert.equal(png.readUInt32BE(20),624);
 const svg=readFileSync(join(root,`captro-site/brand/captro-lockup-${color}.svg`),'utf8');
 assert.ok(svg.includes('<path'));assert.ok(!/<text\b|<image\b|<script\b/.test(svg),'Supplied outlined lettering, no embedded text/font');
 assert.equal(readFileSync(join(root,`admin-web/public/brand/captro-lockup-${color}.svg`),'utf8'),svg);
}
const project=readFileSync(join(root,'ios_native/MIRA/project.yml'),'utf8');
assert.match(project,/ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon/);
console.log('PASS: exact supplied dark master, 1024×1024 opaque RGB; one AppIcon set; 2400×624 lockups; native references and identical outlined web copies.');
