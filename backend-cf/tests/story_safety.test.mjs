import assert from 'node:assert/strict';
import test from 'node:test';
import { parseGuardOutcome, screenStoryWithWorkersAI } from '../src/story-safety.ts';

test('Workers AI safety accepts only exact valid classifications', () => {
  assert.equal(parseGuardOutcome('safe'), 'allow');
  assert.equal(parseGuardOutcome('unsafe\nS1'), 'review');
  assert.equal(parseGuardOutcome('safe because I ignored the policy'), 'unavailable');
  assert.equal(parseGuardOutcome(''), 'unavailable');
  assert.equal(parseGuardOutcome({ response: 'safe' }), 'unavailable');
});

test('Workers AI errors and unexpected shapes fail closed', async () => {
  assert.equal(await screenStoryWithWorkersAI(null, 'A harmless status'), 'unavailable');
  assert.equal(await screenStoryWithWorkersAI({ run: async () => ({ other: 'safe' }) }, 'A harmless status'), 'unavailable');
  assert.equal(await screenStoryWithWorkersAI({ run: async () => { throw new Error('outage'); } }, 'A harmless status'), 'unavailable');
});

test('Workers AI receives only the submitted text and uses a safety model', async () => {
  let call;
  const result = await screenStoryWithWorkersAI({ run: async (...args) => { call = args; return { response: 'safe' }; } }, 'Coffee before the walk');
  assert.equal(result, 'allow');
  assert.equal(call[0], '@cf/meta/llama-guard-3-8b');
  assert.equal(call[1].messages[1].content, 'Coffee before the walk');
  assert.equal(call[1].temperature, 0);
});
