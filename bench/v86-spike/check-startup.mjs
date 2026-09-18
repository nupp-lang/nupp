import {startGuest} from './guest-runtime.mjs';

const output = document.querySelector('#result');
const report = {ok: false, checks: []};
try {
  const seenEntropy = new Set(), seenRandom = new Set();
  for (let launch = 0; launch < 4; launch++) {
    const nonce = crypto.randomUUID();
    const code = `
local ffi = require("ffi")
ffi.cdef[[int getrandom(void *, size_t, unsigned int);]]
local random = ffi.new("uint8_t[32]")
assert(ffi.C.getrandom(random, 32, 1) == 32)
local function hex(bytes)
    return (bytes:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end
local seed = assert(io.open("/nupp/entropy.bin", "rb"))
local entropy = seed:read("*a"); seed:close()
assert(#entropy == 32)
local buffer = require("string.buffer").new()
buffer:put("snapshot", "-ready")
assert(buffer:get() == "snapshot-ready")
assert(require("bit").bxor(255, 170) == 85)
assert(_G.__qemuConfig.nonce == ${JSON.stringify(nonce)})
return {appNonce = ${JSON.stringify(nonce)}, configNonce = _G.__qemuConfig.nonce,
    entropy = hex(entropy), random = hex(ffi.string(random, 32)), now = os.time(), jit = jit.status()}
`;
    const appUrl = URL.createObjectURL(new Blob([code]));
    let result;
    try { result = await startGuest({appUrl, config: {nonce}, deadlineMs: 10000}).result; }
    finally { URL.revokeObjectURL(appUrl); }
    const value = result.value;
    if (value.appNonce !== nonce || value.configNonce !== nonce || !value.jit ||
        seenEntropy.has(value.entropy) || seenRandom.has(value.random) ||
        Math.abs(value.now - Date.now() / 1000) > 3) throw new Error('Restored guest freshness failed');
    seenEntropy.add(value.entropy); seenRandom.add(value.random);
    report.checks.push({launch, freshApp: true, freshConfig: true, freshEntropy: true,
      freshKernelRandom: true, currentWallClock: true, ffi: true, bit: true, stringBuffer: true, jit: value.jit});
  }
  report.native = await startGuest({appUrl: './native-modules.lua', config: {}, deadlineMs: 10000}).result;
  report.ok = true;
} catch (error) { report.error = String(error.stack || error); }
output.textContent = JSON.stringify(report, null, 2);
output.dataset.status = report.ok ? 'passed' : 'failed';
