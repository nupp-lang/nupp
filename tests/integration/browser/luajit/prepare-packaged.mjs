import path from 'node:path';
import {copyFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {packageBrowserApp} from '../../../../runtime/luajit/package-browser-app.mjs';
const root = fileURLToPath(new URL('../../../../', import.meta.url));
const destination = path.resolve(process.argv[2] || 'build/browser-guest');
const guest = path.resolve(process.argv[3] || destination);
for (const name of ['aot', 'native', 'workers', 'http', 'platform', 'gpu', 'simd', 'channels']) {
  const local = name === 'aot' || name === 'native' || name === 'channels';
  const project = path.join(root, local ? `tests/integration/browser/luajit/${name}-project` : `tests/integration/browser/wasm-aot/${name}-project`);
  await packageBrowserApp({project, target: local || name === 'simd' ? 'app' : 'luajit', output: path.join(destination, `${name}-app`), guest});
}
for (const name of ['packaged.html', 'packaged.mjs', 'channels.html', 'channels.mjs']) copyFileSync(path.join(root, 'tests/integration/browser/luajit', name), path.join(destination, name));
