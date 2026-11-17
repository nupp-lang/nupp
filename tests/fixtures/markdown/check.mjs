// pulldown-cmark v0.13.4 specs/definition_lists.txt (MIT).
import {readFileSync, writeFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
const executable = process.argv[2];
if (!executable) throw new Error('pass the C-only renderer executable');
const corpus = readFileSync(new URL('definition-lists.txt', import.meta.url), 'utf8');
const examples = [...corpus.matchAll(/`{32} example\n([\s\S]*?)\n\.\n([\s\S]*?)\n`{32}/g)];
if (examples.length !== 30) throw new Error(`expected 30 fixtures, got ${examples.length}`);
const focused = JSON.parse(readFileSync(new URL('focused.json', import.meta.url), 'utf8'));
// Upstream's prose fixtures predate its current HTML layout. Freeze the exact
// pulldown-cmark 0.13.4 output separately, without changing upstream examples.
const definitions = JSON.parse(readFileSync(new URL('definition-output.json', import.meta.url), 'utf8'));
if (definitions.length !== examples.length) throw new Error('missing frozen definition outputs');
const cases = examples.map(([, source], index) => ({name: `definition-${index + 1}`, source: source + '\n', expected: definitions[index]}));
cases.push(...focused.map(({name, hex, expected}) => ({name, source: Buffer.from(hex, 'hex').toString('utf8'), expected})));
const results = cases.map(({name, source, expected}) => {
    const result = spawnSync(executable, {input: source, encoding: 'utf8'});
    const actual = result.stdout;
    const passed = result.status === 0 && actual === expected;
    return {name, passed, source, expected, actual, status: result.status, stderr: result.stderr};
});
writeFileSync('build/cmark-probe/results.json', JSON.stringify(results, null, 2));
for (const result of results.filter(x => !x.passed)) console.log(JSON.stringify(result));
console.log(`${results.filter(x => x.passed).length}/${results.length} Markdown fixtures`);
if (results.some(x => !x.passed)) process.exitCode = 1;
