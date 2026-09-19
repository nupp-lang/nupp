import {createGuest} from './host.mjs';
const output = document.querySelector('#result');
const terminal = document.querySelector('#terminal');
try {
  const app = new Uint8Array(await (await fetch('./features.lua')).arrayBuffer());
  const results = [];
  for (const profile of ['runner', 'runner', 'compiler']) {
    const guest = createGuest({manifestUrl: './guest-manifest.json', app, profile, deadlineMs: 180000,
      onProgress: message => { if (message.log) terminal.textContent = message.log; }});
    try {
      const result = await guest.receive();
      if (result.type !== 'done' || !result.result.ok) throw new Error(JSON.stringify(result));
      results.push(result.result.value);
    } finally { guest.close(); }
  }
  if (new Set(results.map(result => result.seed)).size !== 3) throw new Error('Guest entropy was reused');
  output.textContent = JSON.stringify({ok: true, crossOriginIsolated, results});
  output.dataset.status = 'passed';
} catch (error) {
  output.textContent = JSON.stringify({ok: false, error: String(error.stack || error)});
  output.dataset.status = 'failed';
}
