const out = document.querySelector('#result');
const name = new URL(location.href).searchParams.get('app') || 'aot';
try {
  if (!['aot', 'workers', 'http', 'platform', 'gpu'].includes(name)) throw new Error('Invalid package name');
  const {runPackagedNuppLuaJITApp} = await import(`./${name}-app/app-runtime.mjs`);
  const started = performance.now();
  const result = await runPackagedNuppLuaJITApp(new URL(`./${name}-app/nupp-browser-app.json`, location.href).href);
  const expect = (condition, message) => {if (!condition) throw new Error(`${message}: ${JSON.stringify(result)}`);};
  if (name === 'aot' || name === 'gpu') expect(result?.ok === true, 'Kernel assertions did not complete');
  if (name === 'http') {
    expect(result.status === 200 && JSON.parse(result.body).message === 'hello from Nupp over fetch', 'HTTP streaming result mismatch');
  }
  if (name === 'workers') {
    expect(!Object.values(result).includes(false), 'Worker assertion failed');
    expect(result.failedStatus === 'failed' && result.cancelledStatus === 'cancelled', 'Worker statuses');
    expect(result.queueBound === 1024 && result.deadlineOutcome === 'cancelled' && result.deadlineMs >= 200 && result.deadlineMs < 5000, 'Worker bounds and deadlines');
  }
  if (name === 'platform') {
    expect(result.platform === 'browser' && result.architecture === 'x86' && result.pointerBits === 32 && result.endianness === 'little', 'Guest platform');
    expect(Number.isInteger(result.parallelism) && result.parallelism >= 1 && result.elapsed >= 1 && result.randomBytes === 32 && result.stored === 'persisted', 'Platform services');
    const values = {
      md5:'900150983cd24fb0d6963f7d28e17f72', sha1:'a9993e364706816aba3e25717850c26c9cd0d89d',
      sha256:'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      sha512:'ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f',
      hmac:'9c196e32dc0175f86f4b1cb89289d6619de6bee699e4c378e68309ed97a1a6ab', crc32c:true, crc64:true,
    };
    for (const [key, value] of Object.entries(values)) expect(result[key] === value, `Incorrect ${key}`);
    expect(/^[0-9a-f-]{36}$/.test(result.uuid4) && /^[0-9a-f-]{36}$/.test(result.uuid7), 'UUIDs');
  }
  out.textContent = JSON.stringify({ok:true, name, elapsedMs:performance.now()-started, result});
  out.dataset.status = 'passed';
} catch (error) {
  // Engines without WebGPU must reject the capability explicitly, not hang.
  const unsupported = name === 'gpu' && /WebGPU is not available|WebGPU adapter is not available|no WebGPU adapter is available|WebGPU is unavailable|WebGPU is not supported/.test(String(error));
  out.textContent = JSON.stringify({ok:unsupported, name, unsupported, error:String(error), stack:error.stack});
  out.dataset.status = unsupported ? 'passed' : 'failed';
}
