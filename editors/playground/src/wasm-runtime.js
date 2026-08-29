const encoder = new TextEncoder();
const decoder = new TextDecoder();

function lastError(module) {
  const pointer = module._nupp_last_error();
  return pointer ? module.UTF8ToString(pointer) : "unknown Wasm host error";
}

/** The lowercase hexadecimal SHA-256 of `bytes`, the way the digest is written
 * into the Wasm and into the asset manifest. */
export async function bundleSha256(bytes) {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

function copiedBytes(module, pointer, length) {
  return module.HEAPU8.slice(pointer, pointer + length);
}

export async function createCompilerHost({
  moduleUrl,
  wasmUrl,
  compilerUrl,
  expectedDigest,
  fetchImpl = fetch,
  wasmBinary,
}) {
  const started = performance.now();
  const imported = await import(moduleUrl);
  const instantiatedAt = performance.now();
  const module = await imported.default({
    locateFile: (name) => name.endsWith(".wasm") ? wasmUrl : new URL(name, moduleUrl).href,
    ...(wasmBinary ? { wasmBinary } : {}),
  });
  const instantiated = performance.now();
  const compiledDigest = module.UTF8ToString(module._nupp_bundle_sha256());
  if (compiledDigest !== expectedDigest) {
    throw new Error(
      `Wasm host digest mismatch: expected ${expectedDigest}, got ${compiledDigest}`
    );
  }

  const response = await fetchImpl(compilerUrl);
  if (!response.ok) {
    throw new Error(`fetching ${compilerUrl}: ${response.status}`);
  }
  const bundle = new Uint8Array(await response.arrayBuffer());
  const fetched = performance.now();

  // The compiler bundle is fetched separately from the Wasm that runs it, so
  // it is checked against the digest compiled into that Wasm before a byte of
  // it is handed over. This used to happen inside the module, in C, over an
  // implementation of SHA-256 carried for this one call. It happens here now,
  // where the bytes already are: `crypto.subtle` is in every environment this
  // runs in, and the check cannot be weaker for having moved, because this is
  // the code that decides which bytes reach the module in the first place.
  const bundleDigest = await bundleSha256(bundle);
  if (bundleDigest !== compiledDigest) {
    throw new Error(
      `compiler bundle SHA-256 mismatch: expected ${compiledDigest}, got ${bundleDigest}`
    );
  }

  const bundlePointer = module._malloc(bundle.length || 1);
  if (!bundlePointer) throw new Error("cannot allocate the compiler bundle in Wasm memory");
  let bootCode;
  try {
    module.HEAPU8.set(bundle, bundlePointer);
    bootCode = module._nupp_boot(bundlePointer, bundle.length);
  } finally {
    module._free(bundlePointer);
  }
  if (bootCode !== 0) {
    throw new Error(lastError(module));
  }
  const booted = performance.now();

  return {
    timings: {
      importMs: instantiatedAt - started,
      instantiateMs: instantiated - instantiatedAt,
      fetchCompilerMs: fetched - instantiated,
      bootCompilerMs: booted - fetched,
      totalMs: booted - started,
    },
    request(value) {
      const requestBytes = encoder.encode(JSON.stringify(value));
      const requestPointer = module._malloc(requestBytes.length || 1);
      if (!requestPointer) throw new Error("cannot allocate the compiler request");
      let handle = 0;
      try {
        module.HEAPU8.set(requestBytes, requestPointer);
        handle = module._nupp_request(requestPointer, requestBytes.length);
        if (!handle) throw new Error(lastError(module));
        const pointer = module._nupp_response_data(handle);
        const length = module._nupp_response_size(handle);
        if (!pointer && length !== 0) throw new Error("the Wasm host returned an invalid response");
        return JSON.parse(decoder.decode(copiedBytes(module, pointer, length)));
      } finally {
        if (handle) module._nupp_response_free(handle);
        module._free(requestPointer);
      }
    },
  };
}
