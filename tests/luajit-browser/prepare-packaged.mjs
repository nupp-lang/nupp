import path from 'node:path';
import {copyFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {packageBrowserApp} from '../../runtime/luajit/package-browser-app.mjs';
const root = fileURLToPath(new URL('../../', import.meta.url));
const destination = path.resolve(process.argv[2] || 'build/browser-guest');
const guest = path.resolve(process.argv[3] || destination);
for (const name of ['aot', 'native', 'workers', 'http', 'platform', 'gpu']) {
  const local = name === 'aot' || name === 'native';
  const project = path.join(root, local ? `tests/luajit-browser/${name}-project` : `tests/wasm-aot/${name}-project`);
  await packageBrowserApp({project, target: local ? 'app' : 'luajit', output: path.join(destination, `${name}-app`), guest,
    nativeCc:name === 'native' ? process.env.NUPP_BROWSER_NATIVE_CC : undefined});
}
for (const name of ['packaged.html', 'packaged.mjs']) copyFileSync(path.join(root, 'tests/luajit-browser', name), path.join(destination, name));
