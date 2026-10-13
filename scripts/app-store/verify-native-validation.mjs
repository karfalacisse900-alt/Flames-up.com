import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

// Used by both fresh archives and preserved-IPA retries. Refuse a missing,
// incomplete, foreign, or different-source result rather than accepting a build
// merely because it compiled. This is a release gate, not performance proof.
export function verifyNativeValidation({ run, branch, targetTree, validatedTree, attestation, runID }) {
  if (run.path !== '.github/workflows/native-stamps-validation.yml') throw new Error('Wrong validation workflow.');
  if (run.head_branch !== branch) throw new Error('Validation belongs to a different branch.');
  if (run.status !== 'completed' || run.conclusion !== 'success') throw new Error('Native validation has not completed successfully.');
  if (!/^[a-f0-9]{40}$/.test(run.head_sha ?? '')) throw new Error('Validation source identity is invalid.');
  if (!/^[a-f0-9]{40}$/.test(targetTree ?? '') || targetTree !== validatedTree) {
    throw new Error('Native validation does not match the IPA source tree.');
  }
  if (attestation?.version !== 1 || attestation.validationRun !== runID ||
      attestation.sourceSHA !== run.head_sha || attestation.nativeTree !== validatedTree) {
    throw new Error('Native validation has no matching actual-source runtime attestation.');
  }
}

export function cameraValidationSource({ source, interaction, regression, runID, sourceSHA, nativeTree }) {
  // This older validation route recorded the checkout and clean diff before
  // building, but exported source.txt rather than the common JSON manifest.
  const expected = `${sourceSHA}\n\nDriver: ${sourceSHA}\nBaseline: false`;
  if (source.replace(/\r\n/g, '\n').trim() !== expected) {
    throw new Error('Camera validation source is modified, baseline, or mismatched.');
  }
  for (const [summary, minimum] of [[interaction, 4], [regression, 146]]) {
    if (summary?.result !== 'Passed' || !Number.isInteger(summary.totalTestCount) ||
        summary.totalTestCount < minimum || summary.passedTests !== summary.totalTestCount ||
        summary.failedTests !== 0 || summary.skippedTests !== 0 || summary.expectedFailures !== 0) {
      throw new Error('Camera runtime and regression evidence is incomplete.');
    }
  }
  return { version: 1, validationRun: runID, sourceSHA, nativeTree };
}

function downloadSource(runID, repository, execute, context) {
  const directory = mkdtempSync(join(tmpdir(), 'captro-validation-'));
  try {
    const options = { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] };
    const inventory = JSON.parse(execute('gh', ['api', `repos/${repository}/actions/runs/${runID}/artifacts?per_page=100`], options));
    const available = inventory.artifacts.filter(item => !item.expired);
    const standard = available.some(item => item.name === 'native-validation-source');
    const name = standard ? 'native-validation-source' : 'camera-carousel-implementation';
    if (available.filter(item => item.name === name).length !== 1) throw new Error('Missing unique native validation evidence.');
    execute('gh', ['run', 'download', runID, '--repo', repository, '--name', name, '--dir', directory],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    if (standard) return JSON.parse(readFileSync(join(directory, 'source.json'), 'utf8'));
    return cameraValidationSource({
      source: readFileSync(join(directory, 'source.txt'), 'utf8'),
      interaction: JSON.parse(readFileSync(join(directory, 'Interaction-summary.json'), 'utf8')),
      regression: JSON.parse(readFileSync(join(directory, 'Regression-summary.json'), 'utf8')),
      runID, ...context,
    });
  } finally {
    // This exact path was freshly allocated by mkdtemp, never a caller path.
    rmSync(directory, { recursive: true, force: true });
  }
}

export function verifyFromEnvironment(env = process.env, execute = execFileSync, loadSource = downloadSource) {
  const runID = env.VALIDATION_RUN ?? '';
  if (!/^\d+$/.test(runID)) throw new Error('A successful matching validation_run is required for every TestFlight upload.');
  const repository = env.GITHUB_REPOSITORY ?? '';
  if (!/^[\w.-]+\/[\w.-]+$/.test(repository)) throw new Error('Repository identity is missing.');
  const sourceSHA = env.IPA_SOURCE_SHA || env.GITHUB_SHA;
  if (!/^[a-f0-9]{40}$/.test(sourceSHA ?? '')) throw new Error('IPA source identity is missing.');
  const read = (command, args) => execute(command, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  const run = JSON.parse(read('gh', ['api', `repos/${repository}/actions/runs/${runID}`]));
  if (!/^[a-f0-9]{40}$/.test(run.head_sha ?? '')) throw new Error('Validation source identity is invalid.');
  // Fetch only the attested commits; never evaluate API output as shell code.
  read('git', ['fetch', '--no-tags', '--depth=1', 'origin', run.head_sha]);
  read('git', ['fetch', '--no-tags', '--depth=1', 'origin', sourceSHA]);
  const validatedTree = read('git', ['rev-parse', `${run.head_sha}:ios_native/MIRA`]);
  const targetTree = read('git', ['rev-parse', `${sourceSHA}:ios_native/MIRA`]);
  const attestation = loadSource(runID, repository, execute, { sourceSHA: run.head_sha, nativeTree: validatedTree });
  verifyNativeValidation({ run, branch: env.GITHUB_REF_NAME, targetTree, validatedTree, attestation, runID });
  return { runID, sourceSHA, nativeTree: targetTree };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const result = verifyFromEnvironment();
    console.log(`Native validation ${result.runID} passed for IPA source ${result.sourceSHA} (tree ${result.nativeTree}).`);
  } catch (error) {
    // Never dump child-process stdout/stderr, which may contain auth context.
    console.error(`::error::${error instanceof Error && !('stdout' in error) ? error.message : 'Native validation verification failed.'}`);
    process.exitCode = 1;
  }
}
