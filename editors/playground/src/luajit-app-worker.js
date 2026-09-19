import {runNuppLuaJITApp} from '../../../runtime/luajit/app-runtime.mjs';
import {sha256,loadPackedAsset} from '../../../runtime/luajit/assets.mjs';
const encoder = new TextEncoder();
let controller;
self.addEventListener('message', async ({data}) => {
  if (data?.type === 'cancel') { controller?.abort(new Error('Program stopped')); return; }
  if (data?.type !== 'run' || typeof data.code !== 'string' || controller) return;
  controller = new AbortController();
  try {
    const initialize = await loadPackedAsset(new URL(`./${__NUPP_LUAJIT_APP_RUNTIME__}`, import.meta.url),
      {sha256:__NUPP_LUAJIT_APP_RUNTIME_SHA256__, bytes:__NUPP_LUAJIT_APP_BYTES__, decodedBytes:__NUPP_LUAJIT_APP_DECODED_BYTES__});
    const app = encoder.encode(data.code);
    const digest = await sha256(app);
    const result = await runNuppLuaJITApp({
      manifestUrl: new URL(`./${__NUPP_LUAJIT_MANIFEST__}`, import.meta.url).href,
      app, initialize, managed: true, signal: controller.signal,
      limits: {maxEffects: 128, maxEffectBytes: 2 * 1024 * 1024,
        maxResponseBytes: 4 * 1024 * 1024, maxStorageValueBytes: 512 * 1024, deadlineMs: 5000},
      storageName: `nupp-playground-${digest.slice(0, 24)}`,
    });
    self.postMessage({ok: true, result});
  } catch (error) { self.postMessage({ok: false, error: String(error.message || error)}); }
});
