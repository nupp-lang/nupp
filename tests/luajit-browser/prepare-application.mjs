import {build} from '../../editors/playground/node_modules/esbuild/lib/main.js';
import {readFileSync,writeFileSync,copyFileSync,readdirSync} from 'node:fs';
import path from 'node:path';
const destination = process.argv[2];
if(!destination)throw new Error('usage: prepare-application.mjs GUEST_DIRECTORY');
const sources = {};
for (const name of readdirSync('editors/playground/src/examples').filter(x=>x.endsWith('.nupp') && x!=='gpu-xor.nupp'))
  sources[name]=readFileSync(path.join('editors/playground/src/examples',name),'utf8');
sources['typed-ffi.nupp']='local ffi = require("ffi")\nlocal cell = ffi.new("int[1]", 42)\nprint(cell[0])';
writeFileSync(path.join(destination,'application-sources.json'),JSON.stringify(sources,null,2)+'\n');
copyFileSync('build/browser-luajit/nupp-app-runtime.lua',path.join(destination,'app-runtime.lua'));
copyFileSync('tests/luajit-browser/application.html',path.join(destination,'application.html'));
await build({entryPoints:['tests/luajit-browser/application.mjs'],outfile:path.join(destination,'application.mjs'),bundle:true,format:'esm',platform:'browser',target:'es2022'});
