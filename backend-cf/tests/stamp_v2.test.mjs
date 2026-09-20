import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { validatedStampVariant, stampFamily } from '../src/stamp-style.ts';
import { attachPublicCommerce } from '../src/commerce.ts';

const native = JSON.parse(readFileSync(new URL('../../ios_native/MIRA/Sources/MIRANative/Resources/CaptroStampTemplates.json', import.meta.url)));
test('all 15 source variants compile to both native densities and validate in their own family', () => {
  assert.equal(Object.keys(native).length, 15);
  assert.deepEqual([...new Set(Object.values(native).map(t => t.type))].sort(), ['club','deal','event','meetup','moment']);
  for (const [id, template] of Object.entries(native)) {
    assert.equal(validatedStampVariant(id, template.type), id);
    for (const [density,height] of [['compact',224],['full',288]]) {
      const layout = template[density];
      assert.equal(layout.width,640); assert.equal(layout.height,height);
      assert.ok(layout.layers.length > 4);
      assert.ok(layout.fields.some(f=>f.key==='title'));
      for (const layer of layout.layers) {
        if (layer.texture) assert.ok(layer.opacity >= .02 && layer.opacity <= .05);
        for (const command of layer.commands) {
          assert.ok(command.every(Number.isFinite));
          assert.equal(command.length, [3,3,5,7,1][command[0]]);
        }
      }
    }
  }
});
test('style cannot change product type or inject arbitrary artwork', () => {
  for (const invalid of ['<svg onload=evil()>', 'https://example.com/frame.svg', {}, 3, 'deal-drop']) {
    assert.equal(validatedStampVariant(invalid,'club'),null);
  }
  assert.equal(stampFamily('general'),'moment');
  assert.equal(stampFamily('offer'),'deal');
  assert.equal(validatedStampVariant('club-tag','group'),'club-tag');
});
test('cancelled and expired attachments keep the real attachment ID, independent of post ID', async () => {
  const posts = [{supabase_post_id:'post-1'}];
  await attachPublicCommerce(posts, async (table, filters) => {
    if (table === 'app_purchasables') {
      assert.match(filters.status,/cancelled/); assert.match(filters.status,/expired/);
      return [{id:'event-99',post_id:'post-1',content_type:'event',status:'cancelled',title:'Cancelled event'}];
    }
    return [];
  });
  assert.equal(posts[0].detail.commerce.id,'event-99');
  assert.equal(posts[0].detail.commerce.status,'cancelled');
  assert.equal(posts[0].detail.commerce.lowestPrice,null);
});
