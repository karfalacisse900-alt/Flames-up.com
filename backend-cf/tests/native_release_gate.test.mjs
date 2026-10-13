import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { verifyNativeValidation, verifyFromEnvironment, cameraValidationSource } from '../../scripts/app-store/verify-native-validation.mjs';

const sha = '1'.repeat(40), tree = '2'.repeat(40);
const run = { path: '.github/workflows/native-stamps-validation.yml', head_branch: 'fix', status: 'completed', conclusion: 'success', head_sha: sha };
const attestation = { version: 1, validationRun: '123', sourceSHA: sha, nativeTree: tree };
const valid = { run, branch: 'fix', targetTree: tree, validatedTree: tree, attestation, runID: '123' };

test('camera evidence requires an exact clean non-baseline checkout and both passed suites', () => {
  const summary = count => ({ result: 'Passed', totalTestCount: count, passedTests: count, failedTests: 0, skippedTests: 0, expectedFailures: 0 });
  const evidence = { source: `${sha}\n\nDriver: ${sha}\nBaseline: false\n`, interaction: summary(4), regression: summary(146), runID: '123', sourceSHA: sha, nativeTree: tree };
  assert.deepEqual(cameraValidationSource(evidence), attestation);
  for (const source of [evidence.source.replace('false', 'true'), evidence.source.replace('Driver: ' + sha, 'Driver: ' + '3'.repeat(40)), evidence.source.replace('\n\n', '\n changed.swift | 2 +-\n')]) {
    assert.throws(() => cameraValidationSource({ ...evidence, source }));
  }
  for (const field of ['interaction', 'regression']) {
    for (const patch of [{ result: 'Failed' }, { totalTestCount: 0 }, { passedTests: 0 }, { failedTests: 1 }, { skippedTests: 1 }, { expectedFailures: 1 }]) {
      assert.throws(() => cameraValidationSource({ ...evidence, [field]: { ...evidence[field], ...patch } }));
    }
    assert.throws(() => cameraValidationSource({ ...evidence, [field]: undefined }));
  }
});

test('release gate accepts only successful matching native source', () => {
  assert.doesNotThrow(() => verifyNativeValidation(valid));
  for (const patch of [{ status: 'in_progress' }, { conclusion: 'failure' }, { head_branch: 'main' }, { path: 'other.yml' }, { head_sha: '' }]) {
    assert.throws(() => verifyNativeValidation({ ...valid, run: { ...run, ...patch } }));
  }
  assert.throws(() => verifyNativeValidation({ ...valid, validatedTree: '3'.repeat(40) }));
  assert.throws(() => verifyNativeValidation({ ...valid, attestation: undefined }));
  assert.throws(() => verifyNativeValidation({ ...valid, attestation: { ...attestation, sourceSHA: '4'.repeat(40) } }));
});

test('missing validation fails before network or build work', () => {
  assert.throws(() => verifyFromEnvironment({}, () => assert.fail('Must fail before command execution')), /required/);
});

test('retry validation compares the preserved IPA source, not current checkout', () => {
  const preserved = '4'.repeat(40), head = '5'.repeat(40);
  const commands = [];
  const result = verifyFromEnvironment({ VALIDATION_RUN: '123', GITHUB_REPOSITORY: 'owner/repo', GITHUB_REF_NAME: 'fix', IPA_SOURCE_SHA: preserved, GITHUB_SHA: head }, (command, args) => {
    commands.push([command, ...args]);
    if (command === 'gh') return JSON.stringify(run);
    if (args[0] === 'rev-parse') return tree;
    return '';
  }, () => attestation);
  assert.equal(result.sourceSHA, preserved);
  assert.ok(commands.some(command => command.includes(`${preserved}:ios_native/MIRA`)));
  assert.ok(!commands.some(command => command.includes(`${head}:ios_native/MIRA`)));
});

test('both TestFlight upload paths require the non-optional gate first', () => {
  const workflow = fs.readFileSync(new URL('../../.github/workflows/native-ios-testflight.yml', import.meta.url), 'utf8');
  const retry = workflow.slice(workflow.indexOf('  retry-upload:'), workflow.indexOf('  build-testflight:'));
  const build = workflow.slice(workflow.indexOf('  build-testflight:'), workflow.indexOf('  home-feed-visual-qa:'));
  for (const job of [retry, build]) {
    assert.ok(job.indexOf('node scripts/app-store/verify-native-validation.mjs') >= 0);
    assert.ok(job.indexOf('node scripts/app-store/verify-native-validation.mjs') < job.indexOf('--upload-app'));
    assert.doesNotMatch(job, /inputs\.validation_run != ''/);
  }
  assert.match(retry, /IPA_SOURCE_SHA=\$SOURCE_SHA/);
});
