/** Own one guest worker. CPU-bound cancellation always terminates the VM. */
export function createGuest({manifestUrl, app, config = {}, profile = 'runner', signal,
  deadlineMs = 30000, snapshot = true, captureSnapshot = false, onProgress = () => {}}) {
  if (!(app instanceof Uint8Array)) throw new Error('Guest code must be bytes');
  let worker, restored = false, retried = false, ready = false;
  let closed = false, waiting, resultSequence, timer, closedReason;
  const messages = [];
  const close = (reason = new Error('Guest closed')) => {
    if (closed) return;
    closed = true;
    closedReason = reason;
    clearTimeout(timer);
    worker?.terminate();
    signal?.removeEventListener('abort', abort);
    if (waiting) { waiting.reject(reason); waiting = null; }
  };
  const abort = () => close(signal.reason || new Error('Guest cancelled'));
  function receive() {
    if (closed) return Promise.reject(closedReason);
    if (waiting) return Promise.reject(new Error('A guest receive is already pending'));
    if (messages.length) return Promise.resolve(messages.shift());
    return new Promise((resolve, reject) => { waiting = {resolve, reject}; });
  }
  function deliver(value) {
    if (waiting) { const listener = waiting; waiting = null; listener.resolve(value); }
    else if (messages.length < 2) messages.push(value);
    else close(new Error('Guest produced unsolicited frames'));
  }
  const arm = (failed = close) => { clearTimeout(timer); timer = setTimeout(() => failed(new Error('Guest request timed out')), deadlineMs); };
  function launch(useSnapshot) {
    const instance = new Worker(new URL('./vm-worker.mjs', new URL(manifestUrl, import.meta.url)), {type: 'module'});
    worker = instance;
    restored = false;
    const failed = error => {
      if (worker !== instance || closed) return;
      if (restored && !ready && !retried && !captureSnapshot) {
        retried = true;
        instance.terminate();
        onProgress({type: 'snapshot-fallback', reason: String(error.message)});
        launch(false);
      } else close(error);
    };
    instance.onmessage = ({data}) => {
      if (closed || worker !== instance) return;
      if (data.type === 'snapshot-selected') { restored = true; return; }
      if (data.type === 'failed') { failed(new Error(data.error + '\n' + data.log)); return; }
      if (data.type === 'ready') ready = true;
      if (data.type === 'log' || data.type === 'ready' || data.type === 'snapshot-fallback') { onProgress(data); return; }
      clearTimeout(timer);
      resultSequence = data.sequence;
      deliver(data);
    };
    instance.onerror = event => failed(new Error(event.message));
    arm(failed);
    const copy = app.slice();
    instance.postMessage({type: 'boot', manifestUrl: new URL(manifestUrl, import.meta.url).href,
      app: copy.buffer, config, profile, snapshot: useSnapshot, captureSnapshot,
      clockOrigin: performance.timeOrigin}, [copy.buffer]);
  }
  if (signal?.aborted) abort();
  else signal?.addEventListener('abort', abort, {once: true});
  if (!closed) launch(snapshot);
  return {
    close, receive,
    respond(response, payload = new Uint8Array()) {
      if (closed || !Number.isSafeInteger(resultSequence)) throw new Error('Guest is not waiting for input');
      const sequence = resultSequence; resultSequence = undefined;
      const copy = payload.slice();
      arm();
      worker.postMessage({type: 'response', sequence, response, payload: copy.buffer}, [copy.buffer]);
    },
  };
}
export async function createCompiler(options) {
  const guest = createGuest({...options, profile: 'compiler', config: {...options.config, mode: 'compiler', jit: false}});
  try {
    const first = await guest.receive();
    if (first.type !== 'compiler' || !first.result.ready) throw new Error(first.result?.error || 'Compiler failed to initialize');
  } catch (error) { guest.close(error); throw error; }
  let busy = false;
  return {
    close: guest.close,
    async request(request) {
      if (busy) throw new Error('A compiler request is already running');
      busy = true;
      try {
        const {source, ...header} = request;
        guest.respond({...header, ...(source === undefined ? {} : {payloadField: 'source'})},
          new TextEncoder().encode(source || ''));
        const answer = await guest.receive();
        if (answer.type !== 'compiler' || !answer.result.ok) throw new Error(answer.result.error || 'Invalid compiler result');
        return answer.result.response;
      } finally { busy = false; }
    },
  };
}
