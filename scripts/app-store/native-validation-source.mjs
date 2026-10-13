import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

// Run before XcodeGen/build steps. The validation workflow can intentionally
// check out a historical baseline, so GITHUB_SHA alone does not attest sources.
const git = (...args) => execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
git('diff', '--exit-code', 'HEAD', '--', 'ios_native/MIRA');
const source = {
  version: 1,
  sourceSHA: git('rev-parse', 'HEAD'),
  nativeTree: git('rev-parse', 'HEAD:ios_native/MIRA'),
  validationRun: process.env.GITHUB_RUN_ID,
};
if (!process.env.RUNNER_TEMP) throw new Error('Missing runner temporary directory.');
const directory = join(process.env.RUNNER_TEMP, 'native-validation-source');
mkdirSync(directory, { recursive: true });
writeFileSync(join(directory, 'source.json'), JSON.stringify(source));
console.log(`Recording actual native validation source ${source.sourceSHA} (tree ${source.nativeTree}).`);
