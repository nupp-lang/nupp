function hostError(module) {
  const pointer = module._nupp_app_last_error();
  return pointer ? module.UTF8ToString(pointer) : "unknown Nupp Wasm app error";
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
