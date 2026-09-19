import path from 'node:path';
import {copyFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {packageBrowserApp} from '../../runtime/luajit/package-browser-app.mjs';
const root = fileURLToPath(new URL('../../', import.meta.url));
const guest = path.resolve(process.argv[2] || 'build/browser-guest');
for (const name of ['aot', 'workers', 'http', 'platform', 'gpu']) {
  const project = path.join(root, name === 'aot' ? 'tests/luajit-browser/aot-project' : `tests/wasm-aot/${name}-project`);
  await packageBrowserApp({project, target: name === 'aot' ? 'app' : 'luajit', output: path.join(guest, `${name}-app`), guest});
}
for (const name of ['packaged.html', 'packaged.mjs']) copyFileSync(path.join(root, 'tests/luajit-browser', name), path.join(guest, name));
