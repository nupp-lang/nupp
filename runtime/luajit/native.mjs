// Native AOT shares the guest's real LuaJIT ABI. These are i386/musl libraries,
// distinct from independent Wasm kernels. Initialization stays inside the VM.
const limit = 1024 * 1024;
export function validateNativeLibrary(name, bytes) {
  if (!/^[A-Za-z0-9_.-]+\.so$/.test(name)) throw new Error('Invalid guest library name');
  if (!(bytes instanceof Uint8Array) || bytes.length < 52 || bytes.length > limit)
    throw new Error('Guest library must contain at most one MiB');
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (view.getUint32(0, false) !== 0x7f454c46 || bytes[4] !== 1 || bytes[5] !== 1 ||
      view.getUint16(16, true) !== 3 || view.getUint16(18, true) !== 3)
    throw new Error('Browser native AOT requires an i386 Linux shared library built against musl; select aotTarget = "i686-unknown-linux-gnu" and an i386/musl NUPP_NATIVE_CC');
}

export async function nativeInitialization(records = [], verified) {
  const names = new Set(), chunks = [];
  let total = 0;
  for (const {file, name} of records) {
    if (names.has(name)) throw new Error('Duplicate guest library name');
    names.add(name);
    const bytes = await verified(file);
    validateNativeLibrary(name, bytes);
    total += bytes.length;
    if (total > limit) throw new Error('Guest native libraries exceed one MiB in total');
    // Decimal escapes preserve every byte, including NUL and non-UTF8 data.
    // Chunk the writes to avoid a single enormous Lua string constant.
    chunks.push(`do local f=assert(io.open("/lib/${name}","wb"))\n`);
    for (let offset = 0; offset < bytes.length; offset += 16384) {
      let literal = '';
      for (const byte of bytes.subarray(offset, offset + 16384)) literal += '\\' + String(byte).padStart(3, '0');
      chunks.push(`assert(f:write("${literal}"))\n`);
    }
    chunks.push('assert(f:close()) end\n');
  }
  return new TextEncoder().encode(chunks.join(''));
}
