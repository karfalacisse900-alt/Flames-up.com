import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

test('website association uses the verified app identity and only scoped opaque return references',()=>{
  const read=path=>readFileSync(new URL('../../'+path,import.meta.url),'utf8');
  const association=JSON.parse(read('captro-site/.well-known/apple-app-site-association'));
  assert.deepEqual(Object.keys(association),['applinks'],'No shared credentials or unrelated domains');
  const details=association.applinks.details;
  assert.equal(details.length,1);assert.deepEqual(details[0].appIDs,['56C9MBK53P.com.captro.app']);
  assert.equal(details[0].components.length,1);
  assert.equal(details[0].components[0]['/'],'/support-creator/return');
  assert.deepEqual(details[0].components[0]['?'],{purchase_id:'????????-????-????-????-????????????'});
  assert.match(read('captro-site/_headers'),/\/\.well-known\/apple-app-site-association\s+Content-Type: application\/json/);
  // Publishing the server half is not evidence that the signed app can open it.
  assert.match(read('captro-site/support-creator/config.js'),/universalLinksVerified: false/);
  assert.doesNotMatch(read('ios_native/MIRA/AppTarget/Info.plist'),/<key>CaptroCreatorSupportEnabled<\/key>\s*<true\s*\/>/);
});
