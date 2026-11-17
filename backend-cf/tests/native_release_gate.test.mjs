import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { verifyNativeValidation, verifyFromEnvironment, cameraValidationSource, verifyPolishEvidence } from '../../scripts/app-store/verify-native-validation.mjs';

const sha = '1'.repeat(40), tree = '2'.repeat(40);
const run = { path: '.github/workflows/native-stamps-validation.yml', head_branch: 'fix', status: 'completed', conclusion: 'success', head_sha: sha };
const attestation = { version: 1, validationRun: '123', sourceSHA: sha, nativeTree: tree };
const valid = { run, branch: 'fix', targetTree: tree, validatedTree: tree, attestation, runID: '123' };

test('serial phone evidence requires both runtime stages and matching downloaded attestation', () => {
  const job = { name: 'simulator (large)', status: 'completed', conclusion: 'success', steps:
    ['Native screens and regression checks', 'Smaller iPhone screens and interactions'].map(name => ({ name, conclusion: 'success' })) };
  const artifacts = ['native-validation-source', 'native-polish'].map(name => ({ name, expired: false }));
  const verify = (jobs = [job], inventory = artifacts, source = attestation) => verifyFromEnvironment({
    VALIDATION_RUN: '123', GITHUB_REPOSITORY: 'owner/repo', GITHUB_REF_NAME: 'fix', GITHUB_SHA: sha,
  }, (command, args) => {
    if (command === 'git') return args[0] === 'rev-parse' ? tree : '';
    if (args[0] === 'run' && args[1] === 'download') {
      fs.writeFileSync(path.join(args[args.indexOf('--dir') + 1], 'source.json'), JSON.stringify(source));
      return '';
    }
    if (args[1].includes('/artifacts?')) return JSON.stringify({ artifacts: inventory });
    if (args[1].includes('/jobs?')) return JSON.stringify({ jobs });
    return JSON.stringify({ ...run, path: '.github/workflows/native-polish-validation.yml' });
  });
  assert.equal(verify().nativeTree, tree);
  for (const jobs of [[], [job, job], [{ ...job, status: 'in_progress' }],
    [{ ...job, conclusion: 'failure' }], [{ ...job, steps: job.steps.slice(0, 1) }],
    [{ ...job, steps: job.steps.map(s => ({ ...s, conclusion: 'skipped' })) }]]) {
    assert.throws(() => verify(jobs));
  }
  for (const inventory of [artifacts.slice(0, 1), [...artifacts, artifacts[0]], artifacts.map(a => ({ ...a, expired: true }))]) {
    assert.throws(() => verify([job], inventory));
  }
  assert.throws(() => verify([job], artifacts, { ...attestation, nativeTree: '3'.repeat(40) }));
});

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

test('runtime deferral is manual, exact-source, and never reported as a passed run', () => {
  const env = { GITHUB_EVENT_NAME: 'workflow_dispatch', GITHUB_SHA: sha, DEFER_RUNTIME_FOR_NATIVE_TREE: tree };
  const execute = (command, args) => {
    assert.equal(command, 'git');
    assert.deepEqual(args, ['rev-parse', `${sha}:ios_native/MIRA`]);
    return tree;
  };
  assert.deepEqual(verifyFromEnvironment(env, execute), { runtimeDeferred: true, sourceSHA: sha, nativeTree: tree });
  for (const patch of [{ GITHUB_EVENT_NAME: 'push' }, { DEFER_RUNTIME_FOR_NATIVE_TREE: 'true' },
    { VALIDATION_RUN: '123' }, { GITHUB_SHA: '' }]) {
    assert.throws(() => verifyFromEnvironment({ ...env, ...patch }, () => assert.fail('Must reject before command execution')));
  }
  assert.throws(() => verifyFromEnvironment(env, () => '3'.repeat(40)), /does not match/);
});

test('runtime deferral on IPA retry uses the preserved source and rejects a different tree', () => {
  const preserved = '4'.repeat(40);
  const env = { GITHUB_EVENT_NAME: 'workflow_dispatch', GITHUB_SHA: sha, IPA_SOURCE_SHA: preserved, DEFER_RUNTIME_FOR_NATIVE_TREE: tree };
  const result = verifyFromEnvironment(env, (command, args) => {
    assert.deepEqual(args, ['rev-parse', `${preserved}:ios_native/MIRA`]);
    return tree;
  });
  assert.equal(result.sourceSHA, preserved);
  assert.equal(result.runtimeDeferred, true);
  assert.throws(() => verifyFromEnvironment(env, () => '5'.repeat(40)), /does not match/);
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


test('polish release evidence requires both successful runtime jobs and identical source records', () => {
  const jobs = ['small', 'large'].map(phone => ({ name: `simulator (${phone})`, status: 'completed', conclusion: 'success', steps: [{ name: 'Native screens and regression checks', conclusion: 'success' }] }));
  const sources = { small: attestation, large: attestation };
  const artifacts = ['small', 'large'].flatMap(phone => [{ name: `native-validation-source-${phone}`, expired: false }, { name: `native-polish-${phone}`, expired: false }]);
  const evidence = { jobs, sources, artifacts, runID: '123', sourceSHA: sha, nativeTree: tree };
  assert.deepEqual(verifyPolishEvidence(evidence), attestation);
  assert.doesNotThrow(() => verifyNativeValidation({ ...valid, run: { ...run, path: '.github/workflows/native-polish-validation.yml' } }));
  for (const badJobs of [[], jobs.slice(1), [...jobs, jobs[0]], jobs.map(j => ({ ...j, conclusion: 'failure' })), jobs.map(j => ({ ...j, status: 'in_progress' })), jobs.map(j => ({ ...j, steps: [] }))]) {
    assert.throws(() => verifyPolishEvidence({ ...evidence, jobs: badJobs }));
  }
  for (const phone of ['small', 'large']) {
    for (const patch of [{ validationRun: '456' }, { sourceSHA: '3'.repeat(40) }, { nativeTree: '4'.repeat(40) }, { version: 2 }]) {
      assert.throws(() => verifyPolishEvidence({ ...evidence, sources: { ...sources, [phone]: { ...attestation, ...patch } } }));
    }
  }
  assert.throws(() => verifyPolishEvidence({ ...evidence, artifacts: artifacts.slice(1) }));
  assert.throws(() => verifyPolishEvidence({ ...evidence, artifacts: artifacts.map(a => ({ ...a, expired: true })) }));
});
