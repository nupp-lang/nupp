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
      match = key.match(new RegExp(`^simd_(primitives|memory|transpose|conversions|integeredges|bitpatterns|bitmemory|masks|maps)_${element}_[0-9]+\\.(probe|fields|indexed|transpose|convert|edges|bits|memorybits|masks|mapmath)_([0-9]+|preferred)$`));
      const names = { primitives: ['probe'], memory: ['fields', 'indexed'], transpose: ['transpose'], conversions: ['convert'], integeredges: ['edges'], bitpatterns: ['bits'], bitmemory: ['memorybits'], masks: ['masks'], maps: ['mapmath'] };
      if (!match || !names[match[1]].includes(match[2])) throw new Error(`Unexpected primitive probe: ${key}`);
      add(match[2], match[3]);
    } else if (family === 'reducers') {
      match = key.match(new RegExp(`^simd_reducers_${element}_[0-9]+\\.horizontal_${element}_([0-9]+|preferred)$`));
      if (match) { add('horizontal', match[1]); continue; }
      match = key.match(new RegExp(`^simd_masked_reducers_${element}_([0-9]+|preferred)\\.masked_[A-Za-z0-9_]+$`));
      if (match) { add('masked', match[1]); continue; }
      if (new RegExp(`^simd_loop_reducers_${element}\\.loop_[A-Za-z0-9_]+$`).test(key)) { add('loop', 'scalar'); continue; }
      throw new Error(`Unexpected reducer probe: ${key}`);
    } else throw new Error(`Unknown corpus family: ${family}`);
  }
  const expected = family === 'primitives'
    ? { probe: [lanes, 1], fields: [lanes, 1],
        indexed: [lanes.filter((lane) => lane !== 'preferred' || !['int8', 'uint8', 'int16', 'uint16'].includes(element)), 1],
        convert: [lanes, 1], masks: [lanes, 1],
        transpose: [lanes.filter((lane) => lane !== 'preferred'), 1],
        ...(!['float', 'number'].includes(element) ? { edges: [lanes, 1] } : { bits: [lanes, 1], memorybits: [lanes, 1], mapmath: [lanes, 1] }) }
    : { horizontal: [lanes, 1],
        ...(['number', 'int32', 'uint32', 'int64', 'uint64'].includes(element)
          ? { masked: [lanes, element === 'number' ? 14 : 7], loop: [['scalar'], element === 'number' ? 21 : 9] } : {}) };
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
