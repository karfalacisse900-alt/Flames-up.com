import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { validatedStampVariant } from '../src/stamp-style.ts';

test('stamp values are allowlisted and bound to their family', () => {
  assert.equal(validatedStampVariant('moment-paper', 'social'), 'moment-paper');
  assert.equal(validatedStampVariant('event-ticket', 'social'), null);
  assert.equal(validatedStampVariant('<svg onload=alert(1)>', 'social'), null);
  assert.equal(validatedStampVariant({ approved: true }, 'social'), null);
});
test('stamp metadata is saved and returned, including expired attachment state', () => {
  const source = readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8');
  assert.match(source, /stamp_variant: validatedStampVariant\(input.stampVariant, input.postType\)/);
  assert.match(source, /stamp_variant: validatedStampVariant\(\(metadata as any\).stamp_variant, row\?\.post_type\)/);
  const commerce = readFileSync(new URL('../src/commerce.ts', import.meta.url), 'utf8');
  assert.match(commerce, /active,sold_out,expired,cancelled,canceled/);
});
