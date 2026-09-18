import {startGuest} from './guest-runtime.mjs';
import {createWorkerPool} from './runtime/worker-pool.mjs';
const output = document.querySelector('#result');
const terminal = document.querySelector('#terminal');
const progress = document.querySelector('#progress');
const query = new URL(location.href).searchParams;
const mode = query.get('mode') || 'services';
const report = {ok: false, mode};
let pool;
const frameTimes = [];
let runStarted = 0;
let move = false, clicks = 0, keyEvents = 0, audioState = 'unstarted';
const canvas = document.querySelector('#game');
const drawing = canvas.getContext('2d');
document.querySelector('#input').addEventListener('click', async () => {
  clicks++; move = true;
  const audio = new AudioContext();
  await audio.resume();
  const oscillator = audio.createOscillator();
  const gain = audio.createGain(); gain.gain.value = 0.03;
  oscillator.connect(gain).connect(audio.destination);
  oscillator.start(); oscillator.stop(audio.currentTime + 0.08);
  audioState = audio.state;
  oscillator.onended = () => audio.close();
});
document.addEventListener('keydown', event => { if (event.key === 'ArrowRight') { move = true; keyEvents++; } });
try {
  const handlers = {
    async asset(effect) {
      if (effect.path !== 'kernel.wgsl') throw new Error('Unknown test asset');
      const response = await fetch('./kernel.wgsl');
      if (!response.ok) throw new Error('Missing generated shader');
      return await response.text();
    },
    async frame(effect) {
      await new Promise(requestAnimationFrame);
      frameTimes.push(performance.now());
      if (frameTimes.length === 1) report.firstFrameMs = performance.now() - runStarted;
      window.spikeFrame = effect.frame;
      drawing.fillStyle = '#091214'; drawing.fillRect(0, 0, canvas.width, canvas.height);
      drawing.fillStyle = '#7ae6b1'; drawing.fillRect(40 + effect.x % 520, 95, 40, 40);
      drawing.font = '18px system-ui'; drawing.fillText(`LuaJIT frame ${effect.frame} · checksum ${effect.checksum}`, 24, 32);
      const answer = {move}; move = false; return answer;
    },
    'transfer-test'(effect, options) {
      const module = options.wasmModule;
      const pointer = module._nupp_wasm_lease_address(effect.lease);
      const bytes = module.HEAPU8.subarray(pointer, pointer + module._nupp_wasm_lease_size(effect.lease));
      if (!pointer) throw new Error('Expired transfer');
      if (effect.operation === 'read') return {sum: bytes.reduce((sum, byte) => sum + byte, 0)};
      if (module._nupp_wasm_lease_writable(effect.lease) !== 1) throw new Error('Read-only transfer');
      for (let i = 0; i < bytes.length; i++) bytes[i] = (i * 7) % 256;
      return {};
    },
  };
  if (mode === 'workers' || mode === 'deadline') {
    let laneId = 0;
    class ObservedWorker extends Worker {
      constructor(...args) {
        super(...args);
        const id = ++laneId;
        this.addEventListener('message', ({data}) => {
          if (data.type === 'progress') terminal.textContent = `Lane ${id}: ` + JSON.stringify(data.progress).slice(-3500);
        });
      }
    }
    pool = createWorkerPool({laneUrl: new URL('./worker-lane.mjs', import.meta.url),
      manifestUrl: new URL('./app.ljbc', import.meta.url).href, maxLanes: 2, WorkerClass: ObservedWorker});
    handlers.workers = effect => pool.perform(effect);
  }
  const run = async selected => {
    progress.textContent = 'Running ' + selected;
    runStarted = performance.now();
    if (selected === 'game' && query.has('portable')) {
      const [{default: createHost}, {runNuppWasmApp}] = await Promise.all([
        import('./nupp-runner.mjs'), import('./runtime/app-runtime.mjs'),
      ]);
      const started = performance.now();
      const app = new Uint8Array(await (await fetch('./portable-app.lua')).arrayBuffer());
      const value = await runNuppWasmApp({createHost, locateFile: name => new URL(name, import.meta.url).href,
        app, sideModules: [], effectHandlers: handlers, limits: {deadlineMs: 120000}});
      return {value, metrics: {totalMs: performance.now() - started}, backend: 'lua51-wasm'};
    }
    return await startGuest({appUrl: selected === 'native' ? './native-modules.lua' : './app.ljbc',
      config: {mode: selected, base: location.origin, traceRequires: query.has('trace'), jit: !query.has('no-jit')},
      effectHandlers: handlers, deadlineMs: 240000,
      onProgress: message => { if (selected !== 'game' || query.has('trace')) terminal.textContent = message.log || JSON.stringify(message); }}).result;
  };
  if (mode === 'lifecycle') {
    const expectFailure = async (promise, pattern) => {
      try { await promise; } catch (error) {
        if (!pattern.test(String(error))) throw error;
        return String(error.message).split('\n')[0];
      }
      throw new Error('Expected failure did not occur');
    };
    const failure = await expectFailure(startGuest({config: {mode: 'failure'}}).result, /intentional guest failure/);
    const cancel = new AbortController();
    let enteredBusy = false;
    const busy = startGuest({config: {mode: 'busy'}, signal: cancel.signal,
      effectHandlers: {'busy-ready': () => { enteredBusy = true; setTimeout(() => cancel.abort(new Error('intentional busy cancellation')), 250); return {}; }}});
    const cancellation = await expectFailure(busy.result, /intentional busy cancellation/);
    if (!enteredBusy) throw new Error('Never reached the CPU-bound guest');
    const timeout = await expectFailure(startGuest({deadlineMs: 50}).result, /exceeded 50 ms/);
    report.lifecycle = {failure, cancellation, timeout, enteredBusy};
  } else report[mode] = await run(mode);
  if (mode === 'workers') {
    const value = JSON.parse(report.workers.value);
    for (const [name, result] of Object.entries(value)) {
      if (typeof result === 'boolean' && !result) throw new Error('Worker check failed: ' + name);
    }
    if (value.deadlineOutcome !== 'cancelled') throw new Error('Worker deadline was not cancelled');
    report.workers.value = value;
  }
  if (mode === 'services') report.persistence = await run('persistence');
  if (mode === 'gpu') {
    const adapter = await navigator.gpu.requestAdapter();
    const info = adapter?.info;
    report.adapter = info && {vendor: info.vendor, architecture: info.architecture, device: info.device, description: info.description};
  }
  if (mode === 'game') {
    const intervals = frameTimes.slice(1).map((time, i) => time - frameTimes[i]);
    const sorted = [...intervals].sort((a, b) => a - b);
    const offline = new OfflineAudioContext(1, 4800, 48000);
    const tone = offline.createOscillator(); tone.connect(offline.destination); tone.start();
    const sound = await offline.startRendering();
    const peak = Math.max(...sound.getChannelData(0).map(Math.abs));
    if (!clicks || !keyEvents || audioState !== 'running' || peak < 0.5) throw new Error('Input or audio integration failed');
    const pixel = drawing.getImageData(40 + (report.game.value.x % 520) + 2, 100, 1, 1).data;
    if (pixel[1] < 150) throw new Error('Canvas did not render the guest state');
    report.interaction = {clicks, keyEvents, audioState, offlineAudioPeak: peak, canvasPixel: [...pixel]};
    const warm = intervals.slice(30);
    report.frameTiming = {samples: intervals.length, medianMs: sorted[Math.floor(sorted.length / 2)], p95Ms: sorted[Math.floor(sorted.length * 0.95)], averageFps: 1000 * intervals.length / intervals.reduce((a, b) => a + b, 0),
      warmFrames: warm.length, warmAverageFps: 1000 * warm.length / warm.reduce((a, b) => a + b, 0), intervalsMs: intervals};
  }
  report.ok = true;
  progress.textContent = 'Passed';
} catch (error) {
  report.error = String(error.stack || error);
  progress.textContent = 'Failed';
} finally {
  pool?.close();
  output.textContent = JSON.stringify(report, null, 2);
  output.dataset.status = report.ok ? 'passed' : 'failed';
}
