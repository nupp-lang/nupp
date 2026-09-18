// Staged into the existing worker alongside its unchanged mailbox protocol.
const startup = {};
function mark(name) {
  startup[name] = performance.now();
  self.postMessage({type: 'startup', name, at: performance.timeOrigin + startup[name]});
}
async function fetchBytes(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`Cannot fetch ${url}: ${response.status}`);
  const bytes = new Uint8Array(await response.arrayBuffer());
  mark('fetched:' + new URL(url, import.meta.url).pathname.split('/').at(-1));
  return bytes;
}
async function boot(message) {
  if (booted) throw new Error('VM was already booted');
  booted = true;
  mark('workerBoot');
  traceMessages = message.config.traceRequires === true;
  mailboxToken = 'NUPP_MAILBOX_' + [...crypto.getRandomValues(new Uint8Array(32))].map(n => n.toString(16).padStart(2, '0')).join('');
  if (!self.crossOriginIsolated) throw new Error('Spike clock requires cross-origin isolation');
  const options = {
    memory_size: 64 * 1024 * 1024, vga_memory_size: 1024 * 1024,
    disable_speaker: true, disable_mouse: true, disable_keyboard: true,
  };
  let app, entropy;
  const instantiate = async (imports, bytes) => {
    mark('wasmInstantiateBegin');
    const {instance} = await WebAssembly.instantiate(bytes, imports);
    mark('wasmInstantiateEnd');
    return instance.exports;
  };
  if (STARTUP_VARIANT === 'snapshot') {
    const fetched = await Promise.all([
      fetchBytes('./guest-state.bin'), fetchBytes(message.appUrl), fetchBytes('./assets/v86.wasm'),
    ]);
    const [state, code, wasm] = fetched;
    app = code;
    entropy = crypto.getRandomValues(new Uint8Array(32));
    options.initial_state = {buffer: state.buffer};
    options.wasm_fn = imports => instantiate(imports, wasm);
    options.autostart = false;
  } else {
    let initrd;
    const initrdName = STARTUP_VARIANT === 'parallel-raw' ? './initramfs.cpio' : './initramfs.gz';
    if (STARTUP_VARIANT === 'serial') {
      [initrd, app] = await Promise.all([fetchBytes(initrdName), fetchBytes(message.appUrl)]);
      options.wasm_fn = async imports => instantiate(imports, await fetchBytes('./assets/v86.wasm'));
      options.bios = {url: new URL('./assets/seabios.bin', import.meta.url).href};
      options.vga_bios = {url: new URL('./assets/vgabios.bin', import.meta.url).href};
      options.bzimage = {url: new URL('./assets/bzimage.bin', import.meta.url).href};
    } else {
      const fetched = await Promise.all([initrdName, message.appUrl, './assets/v86.wasm',
        './assets/seabios.bin', './assets/vgabios.bin', './assets/bzimage.bin'].map(fetchBytes));
      const [rootfs, code, wasm, bios, vga, kernel] = fetched;
      initrd = rootfs; app = code;
      options.wasm_fn = imports => instantiate(imports, wasm);
      options.bios = {buffer: bios.buffer}; options.vga_bios = {buffer: vga.buffer};
      options.bzimage = {buffer: kernel.buffer};
    }
    options.initrd = {buffer: await new Blob([initrd, await overlayArchive({...message.config, mailboxToken}, app)]).arrayBuffer()};
    options.cmdline = 'console=ttyS0,115200 quiet rootfstype=ramfs rdinit=/init mem=48M iomem=relaxed tsc=reliable random.trust_cpu=on nupp.bridge=1';
    options.autostart = true;
  }
  mark('emulatorConstruct');
  emulator = new V86(options);
  emulator.add_listener('emulator-loaded', () => {
    mark('emulatorLoaded');
    if (STARTUP_VARIANT !== 'snapshot') return;
    try {
      const config = encoder.encode(JSON.stringify({...message.config, mailboxToken}));
      if (!config.length || config.length > 65536 || !app.length || app.length > 2 * 1024 * 1024) throw new Error('Startup mailbox capacity exceeded');
      const header = new Uint8Array(24);
      const view = new DataView(header.buffer);
      const now = Date.now();
      [0x5350554e, 1, config.length, app.length, Math.floor(now / 1000), (now % 1000) * 1000]
        .forEach((value, index) => view.setUint32(index * 4, value, true));
      emulator.write_memory(header, PHYSICAL_MAILBOX);
      emulator.write_memory(entropy, PHYSICAL_MAILBOX + 512);
      emulator.write_memory(config, PHYSICAL_MAILBOX + 4096);
      emulator.write_memory(app, PHYSICAL_MAILBOX + 1024 * 1024);
      emulator.serial0_send('start\n');
      emulator.run();
    } catch (error) { fail(error); }
  });
  emulator.add_listener('emulator-started', () => mark('emulatorStarted'));
  emulator.add_listener('download-error', error => fail(new Error(JSON.stringify(error))));
  emulator.add_listener('serial0-output-byte', byte => {
    const text = String.fromCharCode(byte);
    log = (log + text).slice(-16000);
    if (text === '\r') return;
    if (text !== '\n') { partial += text; return; }
    const line = partial; partial = '';
    if (mailbox === undefined || traceMessages) self.postMessage({type: 'log', log});
    if (line.includes('@@NUPP_BRIDGE_READY@@')) mark('guestReady');
    if (line === '@@NUPP_MAILBOX@@') mark('mailboxReady');
    if (line === '@@NUPP_BRIDGE_REQUEST@@ 1') mark('firstEffect');
    try { lineReceived(line); } catch (error) { fail(error); }
  });
}
