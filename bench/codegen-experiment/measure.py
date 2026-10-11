#!/usr/bin/env python3
"""Nine processes, nine rotated rounds, 20 ms CPU-time samples. Geometric mean of
process-median paired ratios with t95 log intervals (df=8), per size."""
import hashlib, json, math, os, statistics, subprocess, sys, time
from pathlib import Path
HERE = Path(__file__).resolve().parent
BIN = Path(os.environ.get('CODEGEN_BIN', HERE.parents[1] / 'build/rust/target/release/codegen-experiment'))
OUT = Path(os.environ.get('CODEGEN_EVIDENCE', HERE / 'evidence'))
OUT.mkdir(parents=True, exist_ok=True)
env = os.environ.copy()
env.setdefault('HAND_KERNELS', str(HERE / 'libhand.dylib'))
env.setdefault('SAMPLE_SECONDS', '0.02')
env.setdefault('ROUNDS', '9')
PAIRS = [('map_jit', 'map_llvm'), ('map_jit_u2', 'map_llvm'), ('map_jit', 'map_hand'),
         ('dot_jit', 'dot_llvm'), ('dot_jit_u2', 'dot_llvm'), ('dot_jit_u2', 'dot_hand'),
         ('sha_jit', 'sha_c'),
         ('chunk_jit_direct', 'chunk_rust_llvm'), ('chunk_jit_extern', 'chunk_rust_llvm'), ('chunk_rust_jit', 'chunk_rust_llvm')]
files = [BIN, HERE / 'src/jit.rs', HERE / 'src/kernels.rs', HERE / 'src/main.rs', Path(env['HAND_KERNELS'])]
meta = {'hashes': {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in files if p.exists()},
        'environment': {k: env.get(k) for k in ('HAND_KERNELS', 'LLVM_KERNELS', 'SHA_CONTROL', 'SAMPLE_SECONDS', 'ROUNDS', 'OPT_LEVEL')},
        'processes': [], 'compile_micros': []}
processes = []
for i in range(9):
    if '--summarize' in sys.argv:
        text = (OUT / f'process-{i+1:02d}.tsv').read_text(); err = (OUT / f'process-{i+1:02d}.log').read_text()
        rows = {}
        for line in text.splitlines():
            n, name, sample, calls, ns = line.split()
            rows.setdefault(int(n), {}).setdefault(name, []).append(float(ns) / int(calls))
        processes.append(rows)
        meta['compile_micros'].append({l.split('\t')[1]: int(l.split('\t')[2]) for l in err.splitlines() if l.startswith('compile')})
        continue
    start = time.monotonic()
    run = subprocess.run([str(BIN)], cwd=HERE, env=env, text=True, capture_output=True)
    (OUT / f'process-{i+1:02d}.tsv').write_text(run.stdout)
    (OUT / f'process-{i+1:02d}.log').write_text(run.stderr)
    run.check_returncode()
    rows = {}
    for line in run.stdout.splitlines():
        n, name, sample, calls, ns = line.split()
        rows.setdefault(int(n), {}).setdefault(name, []).append(float(ns) / int(calls))
    processes.append(rows)
    meta['processes'].append({'index': i + 1, 'wall_seconds': time.monotonic() - start})
    meta['compile_micros'].append({l.split('\t')[1]: int(l.split('\t')[2]) for l in run.stderr.splitlines() if l.startswith('compile')})
    print('process', i + 1, 'done', flush=True)
summary = []
for n in sorted(processes[0]):
    row = {'elements': n, 'median_ns': {name: statistics.median(statistics.median(p[n][name]) for p in processes) for name in processes[0][n]}, 'comparisons': {}}
    for a, b in PAIRS:
        if a not in processes[0][n] or b not in processes[0][n]:
            continue
        ratios = [statistics.median(x / y for x, y in zip(p[n][a], p[n][b])) for p in processes]
        logs = [math.log(r) for r in ratios]
        m = statistics.mean(logs)
        h = 2.306004135 * statistics.stdev(logs) / 3
        row['comparisons'][f'{a}/{b}'] = {'ratio': math.exp(m), 'low95': math.exp(m - h), 'high95': math.exp(m + h), 'cv': statistics.stdev(ratios) / statistics.mean(ratios)}
    summary.append(row)
(OUT / 'metadata.json').write_text(json.dumps(meta, indent=2) + '\n')
(OUT / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
for row in summary:
    print(row['elements'], {k: round(v, 1) for k, v in row['median_ns'].items()})
    for k, c in row['comparisons'].items():
        print('   %-34s %.3fx (%.3f-%.3f) cv %.1f%%' % (k, c['ratio'], c['low95'], c['high95'], c['cv'] * 100))
