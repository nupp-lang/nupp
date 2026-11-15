// Derive coverage from names whose emitted native entries actually returned.
// Environment selection and generator coverage metadata cannot prove execution.
export function verifyWasmInventory(execution, family, element, requested) {
  const lanes = requested.map(String);
  const groups = new Map();
  const add = (group, lane) => {
    const widths = groups.get(group) ?? new Map();
    widths.set(lane, (widths.get(lane) ?? 0) + 1);
    groups.set(group, widths);
  };
  const symbols = Object.keys(execution.symbols ?? {});
  if (symbols.length !== execution.probes) throw new Error('Executed probe inventory/count mismatch');
  for (const key of symbols) {
    let match;
    if (family === 'primitives') {
      match = key.match(new RegExp(`^simd_(primitives|memory|transpose|conversions|integeredges|bitpatterns|bitmemory|masks|maps|widen)_${element}_[0-9]+\\.(probe|fields|interleaved|indexed|transpose|convert|edges|bits|memorybits|masks|mapmath|widen|narrow)_([0-9]+|preferred)$`));
      const names = { primitives: ['probe'], memory: ['fields', 'interleaved', 'indexed'], transpose: ['transpose'], conversions: ['convert'], integeredges: ['edges'], bitpatterns: ['bits'], bitmemory: ['memorybits'], masks: ['masks'], maps: ['mapmath'], widen: ['widen', 'narrow'] };
      if (!match || !names[match[1]].includes(match[2])) throw new Error(`Unexpected primitive probe: ${key}`);
      add(match[2], match[3]);
    } else if (family === 'reducers') {
      match = key.match(new RegExp(`^simd_reducers_${element}_[0-9]+\\.horizontal_${element}_([0-9]+|preferred)$`));
      if (match) { add('horizontal', match[1]); continue; }
      match = key.match(new RegExp(`^simd_masked_reducers_${element}_([0-9]+|preferred)\\.masked_[A-Za-z0-9_]+$`));
      if (match) { add('masked', match[1]); continue; }
      if (new RegExp(`^simd_loop_reducers_${element}\\.loop_[A-Za-z0-9_]+$`).test(key)) { add('loop', 'scalar'); continue; }
      match = key.match(new RegExp(`^simd_mixed_reducers_${element}_([0-9]+)\\.mixed_[A-Za-z0-9_]+$`));
      if (match) { add('mixed', match[1]); continue; }
      throw new Error(`Unexpected reducer probe: ${key}`);
    } else throw new Error(`Unknown corpus family: ${family}`);
  }
  const expected = family === 'primitives'
    ? { probe: [lanes, 1], fields: [lanes, 1], interleaved: [lanes, 1],
        indexed: [lanes.filter((lane) => lane !== 'preferred' || !['int8', 'uint8', 'int16', 'uint16'].includes(element)), 1],
        convert: [lanes, 1], masks: [lanes, 1],
        // A species widens to the next element of its ladder and narrows to the previous one.
        ...(['number', 'int64', 'uint64'].includes(element) ? {} : { widen: [lanes, 1] }),
        ...(['float', 'int8', 'uint8'].includes(element) ? {} : { narrow: [lanes, 1] }),
        transpose: [lanes.filter((lane) => lane !== 'preferred'), 1],
        ...(!['float', 'number'].includes(element) ? { edges: [lanes, 1] } : { bits: [lanes, 1], memorybits: [lanes, 1], mapmath: [lanes, 1] }) }
    : { horizontal: [lanes, 1], ...authoredReducers(element, lanes) };
  for (const [group, [widths, count]] of Object.entries(expected)) {
    const actual = groups.get(group) ?? new Map();
    if (actual.size !== widths.length || widths.some((width) => actual.get(width) !== count)) {
      throw new Error(`Incomplete executed ${family}/${element}/${group} width inventory`);
    }
    groups.delete(group);
  }
  if (groups.size) throw new Error('Unexpected executed probe group');
  return { family, element, lanes, probes: symbols.length };
}

// The authored reducers take the floating elements and the 32- and 64-bit
// integers: one probe per contract through a scalar loop, a masked region at
// every requested width, and the mixed scalar-region-scalar shape at widths 2
// and 8. native-inventory.lua holds the same account.
function authoredReducers(element, lanes) {
  const contracts = { number: 21, float: 18, int32: 9, uint32: 9, int64: 9, uint64: 9 }[element];
  return contracts === undefined ? {}
    : { masked: [lanes, contracts], loop: [['scalar'], contracts], mixed: [['2', '8'], contracts] };
}

export function verifyCountedRuntime(execution, scalarC) {
  const expected = ['simdcounted.counted', 'simdcounted.literal', 'simdcounted.vector'];
  for (const [result, route] of [[execution, 'simd'], [scalarC, 'scalar-c']]) {
    const names = Object.keys(result?.symbols ?? {});
    if (!result?.ok || result.tier !== "simd128" || result.executionPath !== route || result.probes !== 3 ||
        !(result.cases > 0) || !(result.nativeCalls >= expected.length) || names.length !== 3 ||
        expected.some((name) => !names.includes(name))) {
      throw new Error(`Incomplete counted-runtime ${route} execution`);
    }
  }
  if (execution.cases !== scalarC.cases) throw new Error('Counted-runtime routes ran different cases');
}
