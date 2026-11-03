import {createGuest} from './host.mjs';
const output = document.querySelector('#result'), terminal = document.querySelector('#terminal');
try {
  const app = new Uint8Array(await (await fetch('./features.lua')).arrayBuffer()), results = [];
  for (const mode of ['stale', 'corrupt', 'extent', 'invalid-state']) {
    const fallbacks = [];
    const guest = createGuest({manifestUrl: `./recovery-${mode}.json`, app, deadlineMs: 180000,
      onProgress: message => {
        if (message.log) terminal.textContent = message.log;
        if (message.type === 'snapshot-fallback') fallbacks.push(message.reason);
      }});
    try {
      const result = await guest.receive();
      if (result.type !== 'done' || !result.result.ok || fallbacks.length !== 1)
        throw new Error(JSON.stringify({mode, result, fallbacks}));
      results.push({mode, fallbacks});
    } finally { guest.close(); }
  }
  output.textContent = JSON.stringify({ok: true, results});
  output.dataset.status = 'passed';
} catch (error) {
  output.textContent = JSON.stringify({ok: false, error: String(error.stack || error)});
  output.dataset.status = 'failed';
}
