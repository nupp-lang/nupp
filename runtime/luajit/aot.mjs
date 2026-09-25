// Independent Wasm kernels use their own bounded linear memory. Guest pointers
// never cross this interface; spans are copied, with field-wise layout conversion.
const LIMIT = 2 * 1024 * 1024;
const scalarBytes = {bool:1,f32:4,f64:8,i32:4,u32:4,i64:8,u64:8};
const narrowBytes = {uint8:1,int8:1,uint16:2,int16:2};
const integer = (n, label, max = LIMIT) => {
  if (!Number.isSafeInteger(n) || n < 0 || n > max) throw new Error(`Invalid Wasm ${label}`);
  return n;
};
export async function createKernels(records, verified) {
  const units = new Map();
  for (const record of records || []) {
    if (record.abi !== 1 || units.has(record.unit)) throw new Error('Invalid independent Wasm unit');
    const bytes = await verified(record.file);
    // A tier above scalar the engine cannot validate (SIMD128 on an engine
    // without it) is left out; its sources name the scalar unit as well.
    if (record.tier && record.tier !== 'scalar' && !WebAssembly.validate(bytes)) continue;
    const module = await WebAssembly.compile(bytes);
    // Pure kernels need no Lua, filesystem, clocks, or operating-system imports.
    const imports = WebAssembly.Module.imports(module);
    if (imports.some(x => x.kind !== 'function' || !(x.module === 'wasi_snapshot_preview1' && x.name === 'proc_exit' || x.module === 'env' && x.name === 'emscripten_notify_memory_growth')))
      throw new Error(`Unexpected independent Wasm import: ${JSON.stringify(imports)}`);
    const instance = await WebAssembly.instantiate(module, {env:{emscripten_notify_memory_growth() {}},wasi_snapshot_preview1:{proc_exit(code) {throw new Error(`Wasm kernel aborted (${code})`);}}});
    const api = instance.exports;
    api._initialize?.();
    if (!(api.memory instanceof WebAssembly.Memory) || typeof api.malloc !== 'function' || typeof api.free !== 'function') throw new Error('Invalid independent Wasm exports');
    const entries = new Map();
    for (const entry of record.entries) {
      if (entries.has(entry.symbol) || typeof api[entry.call] !== 'function') throw new Error('Invalid Wasm kernel entry');
      const layouts = new Map();
      for (const layout of entry.layouts || []) {
        const size = integer(api[`${layout.prefix}_size`](), 'layout size');
        const fields = layout.fields.map(name => ({name,
          offset:integer(api[`${layout.prefix}_offset_${name}`](), 'field offset'),
          bytes:integer(api[`${layout.prefix}_size_${name}`](), 'field size')}));
        if (fields.some(field => field.offset + field.bytes > size)) throw new Error('Wasm field exceeds its layout');
        layouts.set(layout.name, {size, fields});
      }
      entries.set(entry.symbol, {...entry, layouts});
    }
    units.set(record.unit, {api, entries});
  }
  return async function perform(effect, options) {
    const candidates = Array.isArray(effect.unit) ? effect.unit : [effect.unit];
    const unit = units.get(candidates.find(id => units.has(id))), entry = unit?.entries.get(effect.symbol);
    if (!entry) throw new Error('Wasm kernel is not in the verified application');
    const {api} = unit, allocated = [], spans = [], leases = [];
    const allocate = size => {
      integer(size, 'allocation');
      const pointer = api.malloc(Math.max(1,size));
      if (!pointer || pointer + size > api.memory.buffer.byteLength) throw new Error('Wasm kernel memory exhausted');
      allocated.push(pointer); return pointer;
    };
    try {
      const countCount = entry.independentCounts ? entry.params.filter(p => p.kind.endsWith('_span')).length : 1;
      const argsLength = (entry.params.length + countCount) * 8;
      const args = options.transfers.lease(effect.lease, argsLength, false); leases.push(effect.lease);
      const results = options.transfers.lease(effect.resultLease, entry.results.length * 8, true); leases.push(effect.resultLease);
      const argsPointer = allocate(argsLength), resultPointer = allocate(results.bytes);
      new Uint8Array(api.memory.buffer,argsPointer,argsLength).set(args.view);
      if (!Array.isArray(effect.spans)) throw new Error('Invalid Wasm spans');
      let nextCount = entry.params.length, nextSpan = 0;
      for (let index=0; index<entry.params.length; index++) {
        const param = entry.params[index];
        if (!param.kind.endsWith('_span')) continue;
        const supplied = effect.spans[nextSpan++];
        const countIndex = entry.independentCounts ? nextCount++ : entry.params.length;
        const count = new DataView(args.view.buffer,args.view.byteOffset,args.view.byteLength).getUint32(countIndex*8,true);
        const writable = param.kind === 'write_span';
        const layoutName = param.type.startsWith('struct:') ? param.type.slice(7) : null;
        const layout = layoutName ? entry.layouts.get(layoutName) : null;
        const stride = layout ? layout.size : narrowBytes[param.sourceType] || scalarBytes[param.type];
        if (!stride) throw new Error('Unknown Wasm span layout');
        const sourceStride = integer(supplied?.stride,'guest stride');
        if (!sourceStride || count > LIMIT / Math.max(stride,sourceStride)) throw new Error('Wasm span exceeds transfer budget');
        const lease = options.transfers.lease(supplied.lease, count*sourceStride,writable); leases.push(supplied.lease);
        const fields = layout ? layout.fields.map(field => {
          const from = supplied.fields?.find(item => item.name === field.name);
          if (!from || integer(from.offset,'guest offset')+field.bytes > sourceStride || from.bytes !== field.bytes) throw new Error('Wasm span field layout mismatch');
          return {source:from.offset, target:field.offset, bytes:field.bytes};
        }) : [{source:0,target:0,bytes:stride}];
        if (!layout && sourceStride !== stride) throw new Error('Wasm scalar span layout mismatch');
        const pointer = allocate(count*stride);
        const target = new Uint8Array(api.memory.buffer,pointer,count*stride);
        for (let row=0; row<count; row++) for (const field of fields)
          target.set(lease.view.subarray(row*sourceStride+field.source,row*sourceStride+field.source+field.bytes),row*stride+field.target);
        new DataView(api.memory.buffer).setUint32(argsPointer+index*8,pointer,true);
        spans.push({pointer,lease,count,stride,sourceStride,fields,writable});
      }
      if (nextSpan !== effect.spans.length) throw new Error('Unexpected Wasm span');
      api[entry.call](argsPointer,resultPointer);
      results.view.set(new Uint8Array(api.memory.buffer,resultPointer,results.bytes));
      for (const span of spans) if(span.writable) {
        const source = new Uint8Array(api.memory.buffer,span.pointer,span.count*span.stride);
        for(let row=0;row<span.count;row++) for(const field of span.fields)
          span.lease.view.set(source.subarray(row*span.stride+field.target,row*span.stride+field.target+field.bytes),row*span.sourceStride+field.source);
      }
      return {};
    } finally {
      for (const pointer of allocated) api.free(pointer);
      for (const id of leases) options.transfers.release(id);
    }
  };
}
