// Read emitted identities; private names and const-specialization hashes are
// compiler output, never reconstructed from source filenames by the harness.
export function wasmBindings(source) {
  const bindings = [];
  const pattern = /\b(__nuppWasm_[A-Za-z0-9_]+)Native\s*=\s*assert\s*\(\s*\1Unit\s*\[\s*"([^"]+)"\s*\]\s*,\s*"Wasm AOT (kernel|builder) ([^"]+) is not registered"\s*\)/g;
  for (const match of source.matchAll(pattern)) {
    const unitPattern = new RegExp(`\\b${match[1]}Unit\\s*=\\s*assert\\s*\\(\\s*${match[1]}Registry\\s*\\[\\s*"([^"]+)"`);
    const unit = source.match(unitPattern)?.[1];
    if (!unit) throw new Error(`Missing emitted unit binding for ${match[4]}`);
    bindings.push({ symbol: match[2], name: match[4], unit, entryMode: match[3] });
  }
  return bindings;
}

// Lua source is a byte stream: decoding malformed UTF-8 changes byte literals
// even when the parser and program otherwise accept that source unchanged.
export function instrumentWasmSource(source, prefix, suffix) {
  if (!(source instanceof Uint8Array)) throw new TypeError('Wasm app source must retain its bytes');
  return Buffer.concat([Buffer.from(prefix, 'utf8'), Buffer.from(source), Buffer.from(suffix, 'utf8')]);
}
