import { spawn } from 'node:child_process';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

const url = new URL(process.argv[2] || 'http://127.0.0.1:8112/').href;
const initialUrl = 'about:blank';
const resultFile = process.argv[3];
const chrome = process.env.CHROME || (process.platform === 'darwin'
  ? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' : 'google-chrome');
const profile = process.env.NUPP_BENCH_PROFILE_DIR || await mkdtemp(path.join(os.tmpdir(), 'nupp-luajit-bench-'));
await mkdir(profile, {recursive: true});
const extraFlags = JSON.parse(process.env.NUPP_BENCH_CHROME_FLAGS || '[]');
if (!Array.isArray(extraFlags) || !extraFlags.every(flag => typeof flag === 'string')) throw new Error('Invalid Chrome flags');
const child = spawn(chrome, [
  ...extraFlags,
  '--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
  '--disable-background-networking', `--user-data-dir=${profile}`, '--remote-debugging-port=0', initialUrl,
], { detached: process.platform !== 'win32', stdio: ['ignore', 'ignore', 'pipe'] });
const deadline = Date.now() + Number(process.env.NUPP_BENCH_TIMEOUT_MS || 240000);
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
let stderr = '';
let endpoint;
let socket;
let lastState;
let launchError;
const errors = [];
child.on('error', error => { launchError = error; });
child.stderr.setEncoding('utf8');
child.stderr.on('data', chunk => {
  stderr += chunk;
  endpoint ||= stderr.match(/DevTools listening on (ws:\/\/\S+)/)?.[1];
});
async function until(fn) {
  while (Date.now() < deadline) {
    if (launchError) throw launchError;
    const value = await fn();
    if (value) return value;
    if (child.exitCode !== null) throw new Error(`Chrome exited: ${stderr}`);
    await pause(100);
  }
  throw new Error(`Browser timeout: ${JSON.stringify(lastState)}\n${errors.join('\n')}`);
}
let sequence = 0;
const pending = new Map();
function rpc(method, params = {}) {
  return new Promise((resolve, reject) => {
    const id = ++sequence;
    const timer = setTimeout(() => { pending.delete(id); reject(new Error(`CDP timeout: ${method}`)); }, 15000);
    pending.set(id, { resolve, reject, timer });
    socket.send(JSON.stringify({ id, method, params }));
  });
}
function kill(signal) {
  try { process.kill(process.platform === 'win32' ? child.pid : -child.pid, signal); } catch {}
}
try {
  await until(() => endpoint);
  const port = new URL(endpoint).port;
  const page = await until(async () => {
    const pages = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
    return pages.find(page => page.type === 'page' && page.url === initialUrl);
  });
  socket = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    socket.addEventListener('open', resolve, { once: true });
    socket.addEventListener('error', reject, { once: true });
  });
  socket.addEventListener('message', event => {
    const message = JSON.parse(event.data);
    if (message.method === 'Runtime.exceptionThrown') errors.push(JSON.stringify(message.params));
    if (message.method === 'Runtime.consoleAPICalled' && message.params.type === 'error') {
      errors.push(message.params.args.map(arg => arg.value || arg.description).join(' '));
    }
    const item = pending.get(message.id);
    if (!item) return;
    clearTimeout(item.timer);
    pending.delete(message.id);
    if (message.error) item.reject(new Error(message.error.message));
    else item.resolve(message.result);
  });
  await rpc('Runtime.enable');
  await rpc('Emulation.setDeviceMetricsOverride', {width: 1000, height: 900, deviceScaleFactor: 1, mobile: false});
  if (initialUrl !== url) await rpc('Page.navigate', {url});
  let lastProgress = 0;
  let lastOutput = '';
  const state = await until(async () => {
    const evaluated = await rpc('Runtime.evaluate', {
      expression: `({status:document.querySelector('#result')?.dataset.status, result:document.querySelector('#result')?.textContent, output:document.querySelector('#terminal')?.textContent, userAgent:navigator.userAgent, isolated:crossOriginIsolated})`,
      returnByValue: true,
    });
    lastState = evaluated.result.value;
    if (Date.now() - lastProgress > 15000 && lastOutput !== (lastState?.output || lastState?.result)) {
      lastProgress = Date.now();
      lastOutput = lastState?.output || lastState?.result;
      process.stderr.write((lastState?.output || lastState?.result || 'Loading').slice(-1200) + '\n');
    }
    if (lastState?.status && lastState.status !== 'running') return lastState;
    return null;
  });
  const result = { ...JSON.parse(state.result), userAgent: state.userAgent, isolated: state.isolated, browserErrors: errors };
  if (process.env.NUPP_BENCH_SCREENSHOT) {
    const screenshot = await rpc('Page.captureScreenshot', {format: 'png'});
    await writeFile(process.env.NUPP_BENCH_SCREENSHOT, Buffer.from(screenshot.data, 'base64'));
  }
  if (resultFile) await writeFile(resultFile, JSON.stringify(result, null, 2) + '\n');
  if (state.status !== 'passed' || !result.ok || errors.length) throw new Error(JSON.stringify(result));
  const {output, resources, samples, phaseMarkers, ...summary} = result;
  process.stdout.write(JSON.stringify(summary, null, 2) + '\n');
} finally {
  socket?.close();
  kill('SIGTERM');
  await Promise.race([new Promise(resolve => child.once('exit', resolve)), pause(1000)]);
  kill('SIGKILL');
  if (!process.env.NUPP_BENCH_PROFILE_DIR) await rm(profile, { recursive: true, force: true, maxRetries: 20, retryDelay: 100 });
}
