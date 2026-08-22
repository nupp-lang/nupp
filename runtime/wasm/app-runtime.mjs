function hostError(module) {
  const pointer = module._nupp_app_last_error();
  return pointer ? module.UTF8ToString(pointer) : "unknown Nupp Wasm app error";
}

function relativeAsset(name, label) {
  if (typeof name !== "string" || name.length === 0 || name.includes("\\")) {
    throw new Error(`${label} must be a nonempty relative asset path`);
  }
  const parts = name.split("/");
  if (name.startsWith("/") || parts.some((part) => part === "" || part === "." || part === "..")) {
    throw new Error(`${label} must stay inside the browser application package`);
  }
  return name;
}

async function digest(bytes) {
  if (!globalThis.crypto?.subtle) {
    throw new Error("Web Crypto SHA-256 is unavailable in this host");
  }
  const answer = await globalThis.crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(answer), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function verifiedAsset(fetchAsset, base, record, label) {
  const file = relativeAsset(record?.file, `${label}.file`);
  if (!/^[0-9a-f]{64}$/.test(record?.sha256 || "")) {
    throw new Error(`${label}.sha256 must be a lowercase SHA-256 digest`);
  }
  const response = await fetchAsset(new URL(file, base));
  if (!response.ok) throw new Error(`cannot fetch ${label}: HTTP ${response.status}`);
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (record.bytes !== undefined && bytes.length !== record.bytes) {
    throw new Error(`${label} has ${bytes.length} bytes; expected ${record.bytes}`);
  }
  const actual = await digest(bytes);
  if (actual !== record.sha256) {
    throw new Error(`${label} SHA-256 mismatch: expected ${record.sha256}, found ${actual}`);
  }
  return bytes;
}

export async function runNuppWasmApp({
  createHost,
  locateFile,
  app,
  sideModules,
  wasmBinary,
}) {
  const module = await createHost({
    locateFile,
    ...(wasmBinary ? { wasmBinary } : {}),
  });
  const state = module._nupp_app_boot();
  if (!state) throw new Error(hostError(module));

  const sideStacks = [];
  for (const side of sideModules) {
    const stackSize = side.stackSize || 1024 * 1024;
    const stack = module._malloc(stackSize);
    if (!stack) throw new Error("cannot allocate the Wasm AOT side-module stack");
    sideStacks.push(stack);
    module.nuppSetSideStackPointer(stack + stackSize);
    const scope = {};
    await module.loadDynamicLibrary(side.url, {
      loadAsync: true,
      global: false,
      nodelete: true,
    }, scope);
    const register = scope[side.registrar];
    if (typeof register !== "function") {
      throw new Error(
        "Wasm AOT registrar " + side.registrar + " is missing; loaded " + Object.keys(scope).join(",")
      );
    }
    register(state);
  }

  const source = app instanceof Uint8Array ? app : new Uint8Array(app);
  const pointer = module._malloc(source.length || 1);
  if (!pointer) throw new Error("cannot allocate the Nupp app bundle");
  try {
    module.HEAPU8.set(source, pointer);
    const code = module._nupp_app_run(pointer, source.length);
    if (code !== 0) throw new Error(hostError(module));
  } finally {
    module._free(pointer);
  }
}

export async function runPackagedNuppWasmApp(manifestUrl, options = {}) {
  const fetchAsset = options.fetch || globalThis.fetch;
  if (typeof fetchAsset !== "function") throw new Error("fetch is unavailable in this host");
  const manifestAddress = new URL(manifestUrl, globalThis.location?.href);
  const response = await fetchAsset(manifestAddress);
  if (!response.ok) throw new Error(`cannot fetch browser application manifest: HTTP ${response.status}`);
  const manifest = await response.json();
  if (manifest.schemaVersion !== 1 || manifest.target !== "wasm32-unknown-emscripten") {
    throw new Error("unsupported Nupp browser application manifest");
  }
  const base = new URL(".", manifestAddress);
  const hostModule = relativeAsset(manifest.runtime?.module?.file, "runtime.module.file");
  if (!/^[0-9a-f]{64}$/.test(manifest.runtime?.module?.sha256 || "") ||
      !hostModule.includes(manifest.runtime.module.sha256.slice(0, 16))) {
    throw new Error("runtime.module must use its content-addressed filename");
  }
  const [app, wasmBinary] = await Promise.all([
    verifiedAsset(fetchAsset, base, manifest.app, "app"),
    verifiedAsset(fetchAsset, base, manifest.runtime.wasm, "runtime.wasm"),
  ]);
  const sideRecords = Array.isArray(manifest.sideModules) ? manifest.sideModules : [];
  const sideBytes = await Promise.all(sideRecords.map((record, index) =>
    verifiedAsset(fetchAsset, base, record, `sideModules[${index}]`)
  ));
  const createHost = (await import(new URL(hostModule, base).href)).default;
  const objectUrls = [];
  try {
    const sideModules = sideRecords.map((record, index) => {
      if (typeof record.registrar !== "string" || !/^nupp_wasm_register_[a-z0-9]+$/.test(record.registrar)) {
        throw new Error(`sideModules[${index}].registrar is invalid`);
      }
      const url = URL.createObjectURL(new Blob([sideBytes[index]], {type: "application/wasm"}));
      objectUrls.push(url);
      return {url, registrar: record.registrar, stackSize: record.stackSize};
    });
    return await runNuppWasmApp({
      createHost,
      locateFile: (name) => /^[a-z][a-z0-9+.-]*:/i.test(name) ? name : new URL(name, base).href,
      app,
      sideModules,
      wasmBinary,
    });
  } finally {
    for (const url of objectUrls) URL.revokeObjectURL(url);
  }
}
