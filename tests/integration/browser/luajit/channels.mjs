import {runPackagedNuppLuaJITApp} from './channels-app/app-runtime.mjs';

const output = document.querySelector('#result');
try {
  const result = await runPackagedNuppLuaJITApp(new URL('./channels-app/nupp-browser-app.json', location.href));
  if (result.count !== 256 || result.sum !== 32896 || result.cancelled !== true) {
    throw new Error(`Nupp worker channel contract failed: ${JSON.stringify(result)}`);
  }
  output.textContent = JSON.stringify({ok: true, result});
  output.dataset.status = 'passed';
} catch (error) {
  output.textContent = JSON.stringify({ok: false, error: String(error.stack || error)});
  output.dataset.status = 'failed';
}
