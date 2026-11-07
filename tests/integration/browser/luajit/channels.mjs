import {runPackagedNuppLuaJITApp} from './channels-app/app-runtime.mjs';

const output = document.querySelector('#result');
let blockMs = 0;
try {
  const result = await runPackagedNuppLuaJITApp(new URL('./channels-app/nupp-browser-app.json', location.href), {
    effectHandlers: {channeltest(effect) {
      if (effect.operation !== 'block') throw new Error('invalid channel test operation');
      const start = performance.now();
      while (performance.now() - start < 3000) { /* Deliberately stall the page. */ }
      blockMs = performance.now() - start;
      return {};
    }},
  });
  if (result.count !== 256 || result.sum !== 32896 || result.cancelled !== true ||
      result.firstAfterStart < 0 || result.progressAfterStart >= blockMs) {
    throw new Error(`Nupp workers did not advance their bounded route during the page stall: ${JSON.stringify({result, blockMs})}`);
  }
  output.textContent = JSON.stringify({ok: true, result, blockMs});
  output.dataset.status = 'passed';
} catch (error) {
  output.textContent = JSON.stringify({ok: false, error: String(error.stack || error)});
  output.dataset.status = 'failed';
}
