#!/usr/bin/env node
import {prepareGuest} from './prepare-guest.mjs';
import {copyGuest} from './package-assets.mjs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const repo = fileURLToPath(new URL('../../', import.meta.url));
const [output, supplied] = process.argv.slice(2);
if (!output) throw new Error('usage: build-runtime-package.mjs OUTPUT [GUEST]');
if (process.env.NUPP_BROWSER_DEV === '1') throw new Error('Release runtime packaging cannot use development overlays');
const guest = await prepareGuest(repo, supplied);
const manifest = copyGuest(repo, guest, path.resolve(output));
console.log(JSON.stringify({runtime:'luajit-v86', buildKey:manifest.buildKey, output:path.resolve(output)}));
